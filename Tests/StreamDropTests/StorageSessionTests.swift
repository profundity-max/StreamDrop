import XCTest
@testable import StreamDrop

@MainActor final class StorageSessionTests:ReportingTestCase {
    func testUnreadableAndFutureStateRejectEveryWritePath() throws {
        var future=AppState();future.version=99
        for data in [Data("broken state evidence".utf8),try JSONEncoder().encode(future)] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer{try? FileManager.default.removeItem(at:root)}
            let store=StateStore(root:root.appendingPathComponent("state"))
            try FileManager.default.createDirectory(at:store.root,withIntermediateDirectories:true)
            let stateFile=store.root.appendingPathComponent("state.json")
            try data.write(to:stateFile)
            let queue=DownloadQueue(store:store)
            XCTAssertNotNil(queue.error)
            XCTAssertThrowsError(try queue.add("http://127.0.0.1:9/never-start.mp4",kind:.direct))
            XCTAssertThrowsError(try store.save(AppState()))
            let job=DownloadJob(url:URL(string:"https://example.com/video")!,kind:.direct,mode:.video,quality:"best",folder:root.appendingPathComponent("files").path)
            let source=store.workDirectory(job.id).appendingPathComponent("received")
            try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data("media".utf8).write(to:source)
            var state=AppState(jobs:[job])
            XCTAssertThrowsError(try store.recoverCompletions(state:&state))
            XCTAssertThrowsError(try store.prepareExecution(for:job.id,state:&state))
            XCTAssertThrowsError(try store.complete(job:job,artifact:DownloadArtifact(file:source,name:"video.mp4",playback:PlaybackObservation(kind:.notChecked,detail:"fixture")),state:&state))
            XCTAssertEqual(try Data(contentsOf:stateFile),data)
            XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
            XCTAssertTrue(queue.jobs.isEmpty)
        }
    }
    func testRetrySettlesPendingCompletionBeforeStartingNewTransfer() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=StateStore(root:root.appendingPathComponent("state"))
        var job=DownloadJob(url:URL(string:"http://127.0.0.1:9/no-server.mp4")!,kind:.direct,mode:.video,quality:"best",folder:root.appendingPathComponent("files").path)
        job.status = .paused
        var state=AppState(jobs:[job])
        try store.save(state)
        let queue=DownloadQueue(store:store)
        let source=store.workDirectory(job.id).appendingPathComponent("received")
        try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("already downloaded".utf8).write(to:source)
        let stateFile=store.root.appendingPathComponent("state.json")
        let saved=try Data(contentsOf:stateFile)
        try FileManager.default.removeItem(at:stateFile)
        try FileManager.default.createDirectory(at:stateFile,withIntermediateDirectories:false)
        XCTAssertThrowsError(try store.complete(job:job,artifact:DownloadArtifact(file:source,name:"video.mp4",playback:PlaybackObservation(kind:.notChecked,detail:"fixture")),state:&state))
        try FileManager.default.removeItem(at:stateFile)
        try saved.write(to:stateFile)
        queue.resume(job.id)
        let deadline=Date().addingTimeInterval(3)
        while queue.jobs[0].status.active || queue.jobs[0].status == .queued,Date()<deadline{try await Task.sleep(nanoseconds:20_000_000)}
        XCTAssertEqual(queue.jobs[0].status,.completed,queue.jobs[0].detail)
        XCTAssertEqual(queue.history.count,1)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("files/video.mp4")),Data("already downloaded".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath:source.path))
    }
}
