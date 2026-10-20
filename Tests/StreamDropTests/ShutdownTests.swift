import XCTest
import Darwin
@testable import StreamDrop

extension DownloadTests {
    func testShutdownDuringConversionDrainsChildAndReloadFinishesOnce() async throws {
        guard let ffmpeg=ToolPaths.find("",name:"ffmpeg"),ToolPaths.find("",name:"yt-dlp") != nil else{throw XCTSkip("media tools missing")}
        let (queue,root)=try makeQueue();defer{try? FileManager.default.removeItem(at:root)}
        let proxy=root.appendingPathComponent("ffmpeg"),pidFile=root.appendingPathComponent("converter-child")
        let script="#!/bin/sh\nfor argument do\ncase \"$argument\" in\n*/system-compatible.mp4)\ntrap '' INT TERM\n/bin/sleep 30 &\nprintf '%s' \"$!\" > '\(pidFile.path)'\nwait\n;;\nesac\ndone\nexec '\(ffmpeg)' \"$@\"\n"
        try script.write(to:proxy,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:proxy.path)
        queue.preferences.ffmpeg=proxy.path
        try queue.add("http://127.0.0.1:18764/vp9.mp4",kind:.webpage)
        try await wait{FileManager.default.fileExists(atPath:pidFile.path)}
        let child=try XCTUnwrap(Int32(String(contentsOf:pidFile)))
        await queue.shutdown()
        XCTAssertEqual(queue.jobs[0].status,.paused)
        XCTAssertTrue(queue.history.isEmpty)
        try await wait({kill(child,0) == -1 && errno == ESRCH},seconds:3)
        let reloaded=DownloadQueue(store:StateStore(root:queue.store.root))
        reloaded.preferences.ffmpeg=ffmpeg
        reloaded.resumeAll()
        try await wait{[.completed,.failed].contains(reloaded.jobs[0].status)}
        XCTAssertEqual(reloaded.jobs[0].status,.completed,reloaded.jobs[0].detail)
        XCTAssertEqual(reloaded.history.count,1)
    }
    func testShutdownDrainsDirectDownloadAndReloadCanFinishOnce() async throws {
        let (queue,root)=try makeQueue();defer{try? FileManager.default.removeItem(at:root)}
        try queue.add("http://127.0.0.1:18764/slow.mp4",kind:.direct)
        try await wait{queue.jobs[0].received>100000}
        await queue.shutdown()
        XCTAssertEqual(queue.jobs[0].status,.paused)
        XCTAssertThrowsError(try queue.add("http://127.0.0.1:18764/video.mp4",kind:.direct))
        queue.resumeAll()
        XCTAssertEqual(queue.jobs[0].status,.paused)
        let reloaded=DownloadQueue(store:StateStore(root:queue.store.root))
        XCTAssertEqual(reloaded.jobs[0].status,.paused)
        reloaded.resumeAll()
        try await wait{reloaded.jobs[0].status == .completed}
        XCTAssertEqual(reloaded.history.count,1)
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:XCTUnwrap(reloaded.jobs[0].outputPath))).count,4*1024*1024)
        XCTAssertEqual(try reloaded.store.load().history.count,1)
    }
}
