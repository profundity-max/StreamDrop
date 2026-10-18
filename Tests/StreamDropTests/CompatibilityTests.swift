import XCTest
import AVFoundation
@testable import StreamDrop
@MainActor final class CompatibilityTests:XCTestCase {
    func testPauseAfterWebFailureQueuedSettlesAndReleasesSlot() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let tool=root.appendingPathComponent("failing-tool")
        try Data("#!/bin/sh\nprintf 'ERROR: fixture failure\\n'\nexit 1\n".utf8).write(to:tool)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:tool.path)
        let q=DownloadQueue(store:StateStore(root:root.appendingPathComponent("state")))
        q.preferences.ytDLP=tool.path
        try q.add("http://127.0.0.1:18764/webpage",kind:.webpage)
        let id=q.jobs[0].id
        let log=q.store.workDirectory(id).appendingPathComponent("yt-dlp.log")
        // Hold the main actor while the real child exits and queues its terminal event.
        let deadline=Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath:log.path),Date()<deadline{Thread.sleep(forTimeInterval:0.005)}
        XCTAssertTrue(FileManager.default.fileExists(atPath:log.path))
        Thread.sleep(forTimeInterval:0.1)
        q.pause(id)
        try await Task.sleep(nanoseconds:200_000_000)
        XCTAssertEqual(q.jobs[0].status,.paused)
        XCTAssertTrue(q.history.isEmpty)
        q.resume(id)
        try await Task.sleep(nanoseconds:200_000_000)
        XCTAssertEqual(q.jobs[0].status,.failed,"Retry must start after the previous slot is released")
    }
    func testUnknownVideoObservationSurvivesCompletionAndReload() async throws {
        guard ToolPaths.find("",name:"yt-dlp") != nil else{throw XCTSkip("yt-dlp missing")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let q=DownloadQueue(store:StateStore(root:root.appendingPathComponent("state")))
        q.preferences.folder=root.appendingPathComponent("files").path
        try q.add("http://127.0.0.1:18764/unrecognized.mp4",kind:.webpage)
        let deadline=Date().addingTimeInterval(15)
        while ![.completed,.failed].contains(q.jobs[0].status),Date()<deadline{try await Task.sleep(nanoseconds:20_000_000)}
        XCTAssertEqual(q.jobs[0].status,.completed,q.jobs[0].detail)
        XCTAssertEqual(q.jobs[0].playback?.kind,.unknown)
        XCTAssertFalse(q.jobs[0].playback?.detail.isEmpty ?? true)
        XCTAssertEqual(try q.store.load().history.first?.playback?.kind,.unknown)
    }
    func testCancelDuringCompatibilityConversionNeverCreatesHistory() async throws {
        guard ToolPaths.find("",name:"yt-dlp") != nil,ToolPaths.find("",name:"ffmpeg") != nil else{throw XCTSkip("media tools missing")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let q=DownloadQueue(store:StateStore(root:root.appendingPathComponent("state")))
        q.preferences.folder=root.appendingPathComponent("files").path
        try q.add("http://127.0.0.1:18764/vp9.mp4",kind:.webpage)
        let deadline=Date().addingTimeInterval(15)
        while !q.jobs[0].detail.contains("正在转换"),Date()<deadline,![.completed,.failed].contains(q.jobs[0].status){try await Task.sleep(nanoseconds:1_000_000)}
        guard q.jobs[0].detail.contains("正在转换") else{XCTFail("Conversion stage was not observed");return}
        q.cancel(q.jobs[0].id)
        while q.jobs[0].status.active,Date()<deadline{try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertEqual(q.jobs[0].status,.cancelled)
        XCTAssertTrue(q.history.isEmpty)
        try await Task.sleep(nanoseconds:100_000_000)
        XCTAssertTrue(q.history.isEmpty,"Late conversion completion must not become success")
    }
    func testRealVP9WebDownloadBecomesNativelyDecodable() async throws {
        guard ToolPaths.find("",name:"yt-dlp") != nil,ToolPaths.find("",name:"ffmpeg") != nil else{throw XCTSkip("media tools missing")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let queue=DownloadQueue(store:StateStore(root:root.appendingPathComponent("state")))
        queue.preferences.folder=root.appendingPathComponent("files").path
        try queue.add("http://127.0.0.1:18764/vp9.mp4",kind:.webpage)
        let deadline=Date().addingTimeInterval(30)
        while ![.completed,.failed].contains(queue.jobs[0].status),Date()<deadline {try await Task.sleep(nanoseconds:30_000_000)}
        XCTAssertEqual(queue.jobs[0].status,.completed,queue.jobs[0].detail)
        let output=URL(fileURLWithPath:try XCTUnwrap(queue.jobs[0].outputPath))
        let asset=AVURLAsset(url:output)
        let tracks=try await asset.loadTracks(withMediaType:.video)
        let track=try XCTUnwrap(tracks.first)
        let reader=try AVAssetReader(asset:asset)
        let pixels=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(pixels)
        XCTAssertTrue(reader.startReading(),String(describing:reader.error))
        XCTAssertNotNil(pixels.copyNextSampleBuffer(),"A stream entry alone does not establish that macOS can decode a frame")
        reader.cancelReading()
        let audioTracks=try await asset.loadTracks(withMediaType:.audio)
        XCTAssertFalse(audioTracks.isEmpty)
        XCTAssertEqual(queue.history.count,1)
        XCTAssertEqual(queue.jobs[0].playback?.kind,.converted)
        let reloaded=try queue.store.load()
        XCTAssertEqual(reloaded.history.first?.playback?.kind,.converted)
    }
}
