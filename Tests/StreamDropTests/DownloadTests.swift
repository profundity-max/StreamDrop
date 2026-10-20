import XCTest
import CryptoKit
import Darwin
@testable import StreamDrop
@MainActor final class DownloadTests: ReportingTestCase {
    func makeQueue() throws -> (DownloadQueue, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StreamDropTest-"+UUID().uuidString)
        let queue = DownloadQueue(store:StateStore(root:root.appendingPathComponent("state")))
        queue.preferences.folder = root.appendingPathComponent("files").path
        return (queue,root)
    }
    func wait(_ condition: @escaping () -> Bool, seconds:Double = 20) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() && Date()<end { try await Task.sleep(nanoseconds:30_000_000) }
        XCTAssertTrue(condition(),"Condition did not complete within \(seconds)s")
    }
    func testDirectTransferBytesCollisionHistoryAndReload() async throws {
        let (q,root)=try makeQueue(); defer { try? FileManager.default.removeItem(at:root) }
        let url="http://127.0.0.1:18764/video.mp4?public=kept"
        try q.add(url,kind:.direct)
        try await wait { q.jobs.first?.status == .completed }
        let first=q.jobs[0]
        let expected=Data((0..<16384).flatMap { _ in Array(UInt8.min...UInt8.max) })
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:first.outputPath!)),expected)
        try q.add(url,kind:.direct)
        try await wait { q.jobs.count==2 && q.jobs.allSatisfy{$0.status == .completed} }
        XCTAssertNotEqual(q.jobs[0].outputPath,q.jobs[1].outputPath)
        XCTAssertEqual(q.history.count,2)
        let recovered=DownloadQueue(store:q.store)
        XCTAssertEqual(recovered.history.count,2)
        XCTAssertEqual(recovered.history.first?.playback?.kind,.notChecked)
        XCTAssertEqual(recovered.jobs[0].url.query,"public=kept")
    }
    func testHTTPFailureAndHTMLNeverBecomeCompleted() async throws {
        let (q,root)=try makeQueue(); defer {try? FileManager.default.removeItem(at:root)}
        try q.add("http://127.0.0.1:18764/missing.mp4 http://127.0.0.1:18764/html.mp4",kind:.direct)
        try await wait { q.jobs.allSatisfy{$0.status == .failed} }
        XCTAssertEqual(q.history.count,0)
        XCTAssertTrue(q.jobs.allSatisfy{!$0.detail.isEmpty && $0.outputPath == nil})
    }
    func testPauseContinueAndCancelRetryOwnLateCallbacks() async throws {
        let (q,root)=try makeQueue(); defer {try? FileManager.default.removeItem(at:root)}
        try q.add("http://127.0.0.1:18764/slow.mp4",kind:.direct)
        let id=q.jobs[0].id
        try await wait { q.jobs[0].received > 100000 }
        q.pause(id)
        try await wait { q.jobs[0].status == .paused }
        XCTAssertEqual(q.history.count,0)
        q.resume(id)
        try await wait { q.jobs[0].status == .completed }
        XCTAssertEqual(q.history.count,1)
        try q.add("http://127.0.0.1:18764/slow2.mp4",kind:.direct)
        let second=q.jobs[0].id
        try await wait { q.jobs[0].received > 100000 }
        q.cancel(second)
        try await wait { q.jobs[0].status == .cancelled }
        XCTAssertEqual(q.history.count,1)
        q.resume(second)
        try await wait { q.jobs[0].status == .completed }
        XCTAssertEqual(q.history.count,2)
    }
    func testConcurrencyAndManualStart() async throws {
        let (q,root)=try makeQueue(); defer {try? FileManager.default.removeItem(at:root)}
        q.preferences.autoStart=false; q.preferences.concurrency=1
        try q.add("http://127.0.0.1:18764/slow3.mp4 http://127.0.0.1:18764/slow4.mp4",kind:.direct)
        XCTAssertTrue(q.jobs.allSatisfy{$0.status == .paused})
        q.resumeAll()
        try await wait { q.jobs.contains{$0.status == .downloading} }
        XCTAssertEqual(q.jobs.filter{$0.status.active}.count,1)
        q.pauseAll()
        try await wait { !q.jobs.contains{$0.status.active} }
        XCTAssertEqual(q.history.count,0)
    }
    func testInvalidResumeDataFallsBackToOriginalURL() async throws {
        let (q,root)=try makeQueue(); defer {try? FileManager.default.removeItem(at:root)}
        q.preferences.autoStart=false
        try q.add("http://127.0.0.1:18764/resume.mp4",kind:.direct)
        let id=q.jobs[0].id
        let work=q.store.workDirectory(id)
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
        try Data("invalid old resume record".utf8).write(to:work.appendingPathComponent("resume.data"))
        q.resume(id)
        try await wait {q.jobs[0].status == .completed || q.jobs[0].status == .failed}
        XCTAssertEqual(q.jobs[0].status,.completed,q.jobs[0].detail)
    }
    func testOwnedProcessStopsStubbornChildAndDrainsOutput() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let script=root.appendingPathComponent("child.sh"),pidFile=root.appendingPathComponent("pid")
        try "trap '' INT TERM\n/bin/sleep 30 &\nprintf '%s' \"$!\" > \"$1\"\nwait\n".write(to:script,atomically:true,encoding:.utf8)
        let exited=expectation(description:"owned group exited and output reached EOF")
        let process=OwnedProcess(onData:{_ in},onExit:{_ in exited.fulfill()})
        try process.start(executable:"/bin/sh",arguments:[script.path,pidFile.path],environment:[:])
        try await wait {FileManager.default.fileExists(atPath:pidFile.path)}
        let child=try XCTUnwrap(Int32(String(contentsOf:pidFile).trimmingCharacters(in:.whitespacesAndNewlines)))
        XCTAssertEqual(kill(child,0),0)
        process.stop()
        await fulfillment(of:[exited],timeout:7)
        XCTAssertFalse(process.isRunning)
        try await wait({kill(child,0) == -1 && errno == ESRCH},seconds:5)
    }
    func testActualHLSVideoAndAudioExtraction() async throws {
        guard ToolPaths.find("",name:"yt-dlp") != nil,ToolPaths.find("",name:"ffmpeg") != nil else {throw XCTSkip("media tools not installed")}
        let (q,root)=try makeQueue();defer{try? FileManager.default.removeItem(at:root)}
        try q.add("http://127.0.0.1:18765/playlist.m3u8",kind:.webpage,mode:.video)
        try q.add("http://127.0.0.1:18765/playlist.m3u8",kind:.webpage,mode:.audio)
        try await wait({q.jobs.allSatisfy{[.completed,.failed].contains($0.status)}},seconds:30)
        XCTAssertTrue(q.jobs.allSatisfy{$0.status == .completed},q.jobs.map{$0.detail}.joined(separator:"\n"))
        XCTAssertEqual(q.history.count,2)
        for job in q.jobs {
            let file=URL(fileURLWithPath:try XCTUnwrap(job.outputPath))
            let size=try XCTUnwrap(try file.resourceValues(forKeys:[.fileSizeKey]).fileSize)
            XCTAssertEqual(job.fileSize,Int64(size),"Completed size must describe the final merged/converted file, separately from transfer counters")
            XCTAssertEqual(q.history.first{$0.id == job.id}?.fileSize,Int64(size))
        }
        let audio=try XCTUnwrap(q.jobs.first{$0.mode == .audio}?.outputPath)
        XCTAssertEqual(URL(fileURLWithPath:audio).pathExtension,"m4a")
        XCTAssertGreaterThan(try Data(contentsOf:URL(fileURLWithPath:audio)).count,1000)
    }
    func testActualWebDownloadPauseThenResume() async throws {
        guard ToolPaths.find("",name:"yt-dlp") != nil else{throw XCTSkip("yt-dlp missing")}
        let (q,root)=try makeQueue();defer{try? FileManager.default.removeItem(at:root)}
        try q.add("http://127.0.0.1:18764/slowweb.mp4",kind:.webpage)
        let id=q.jobs[0].id
        try await wait {q.jobs[0].received>100000}
        q.pause(id)
        try await wait({q.jobs[0].status == .paused},seconds:7)
        XCTAssertEqual(q.history.count,0)
        q.resume(id)
        try await wait({[.completed,.failed].contains(q.jobs[0].status)},seconds:15)
        XCTAssertEqual(q.jobs[0].status,.completed,q.jobs[0].detail)
    }
    func testActualWebFailureKeepsFullDiagnostics() async throws {
        guard ToolPaths.find("",name:"yt-dlp") != nil else{throw XCTSkip("yt-dlp missing")}
        let (q,root)=try makeQueue();defer{try? FileManager.default.removeItem(at:root)}
        try q.add("http://127.0.0.1:18764/missing.mp4",kind:.webpage)
        let id=q.jobs[0].id
        try await wait {q.jobs[0].status == .failed}
        let log=try String(contentsOf:q.store.workDirectory(id).appendingPathComponent("yt-dlp.log"),encoding:.utf8)
        XCTAssertTrue(log.contains("ERROR:"),log)
        XCTAssertEqual(q.jobs[0].detail,log)
        XCTAssertTrue(DownloadDiagnostics.summary(log).hasPrefix("ERROR:"))
        XCTAssertTrue(q.history.isEmpty)
    }
    func testWebFilenamePreservesTitleWithoutInjectedIDAndDoesNotOverwrite() async throws {
        guard ToolPaths.find("",name:"yt-dlp") != nil else{throw XCTSkip("yt-dlp missing")}
        let (q,root)=try makeQueue();defer{try? FileManager.default.removeItem(at:root)}
        for count in 1...2 {
            try q.add("http://127.0.0.1:18764/named-page",kind:.webpage)
            try await wait({q.jobs.count==count && q.jobs.allSatisfy{[.completed,.failed].contains($0.status)}})
            XCTAssertTrue(q.jobs.allSatisfy{$0.status == .completed},q.jobs.map{$0.detail}.joined(separator:"\n"))
        }
        for job in q.jobs {
            XCTAssertTrue(job.title.hasPrefix("中文 视频 [2026] 标题"),job.title)
            XCTAssertEqual(job.title.filter{$0=="["}.count,1,"Keep the title's own brackets, add no extractor ID")
            XCTAssertEqual(job.title,URL(fileURLWithPath:try XCTUnwrap(job.outputPath)).lastPathComponent)
        }
        XCTAssertNotEqual(q.jobs[0].outputPath,q.jobs[1].outputPath)
        XCTAssertEqual(q.history.count,2)
    }
    func testActualYTDLPGenericWebpageDownload() async throws {
        guard ToolPaths.find("",name:"yt-dlp") != nil else { throw XCTSkip("yt-dlp not installed") }
        let (q,root)=try makeQueue(); defer {try? FileManager.default.removeItem(at:root)}
        try q.add("http://127.0.0.1:18764/page",kind:.webpage)
        try await wait({ q.jobs[0].status == .completed || q.jobs[0].status == .failed },seconds:30)
        XCTAssertEqual(q.jobs[0].status,.completed,q.jobs[0].detail)
        XCTAssertTrue(FileManager.default.fileExists(atPath:q.jobs[0].outputPath ?? "missing"))
        XCTAssertEqual(q.jobs[0].playback?.kind,.decoded)
    }
}

private final class TransferRecorder {
    private let lock=NSLock()
    private var paused=false
    private var count=0
    private var terminals=0
    var terminalCount:Int {lock.lock();defer{lock.unlock()};return terminals}
    var didPause:Bool {lock.lock();defer{lock.unlock()};return paused}
    var lateEvents:Int {lock.lock();defer{lock.unlock()};return count}
    func record(_ event:TransferEvent){lock.lock();defer{lock.unlock()};switch event{case .paused:paused=true;terminals+=1;case .finished:terminals+=1;if paused{count+=1};case .failed,.cancelled:terminals+=1;case .progress,.processing:if paused{count+=1}}}
}

final class TransferBoundaryTests:ReportingTestCase {
    func testInvalidResumeImmediatelyPausedProducesNoLaterTransfer() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        for index in 0..<15 {
            let work=root.appendingPathComponent(String(index))
            try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
            try Data("invalid".utf8).write(to:work.appendingPathComponent("resume.data"))
            let job=DownloadJob(url:URL(string:"http://127.0.0.1:18764/slow-race.mp4")!,kind:.direct,mode:.video,quality:"best",folder:root.path)
            let recorder=TransferRecorder()
            let acknowledged=DispatchSemaphore(value:0)
            let transfer=DirectTransfer(job:job,work:work){event in
                recorder.record(event)
                if case .paused = event {acknowledged.signal()}
            }
            transfer.start();transfer.pause()
            XCTAssertEqual(acknowledged.wait(timeout:.now()+2),.success)
            Thread.sleep(forTimeInterval:0.08)
            XCTAssertEqual(recorder.lateEvents,0,"No active transfer may survive pause acknowledgement")
            XCTAssertEqual(recorder.terminalCount,1,"Each adapter must settle only once, after resource cleanup")
        }
    }
}
