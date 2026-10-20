import XCTest
@testable import StreamDrop

final class CompletionFailureTests:ReportingTestCase {
    func testFinalStateSaveFailureRetainsReceiptAndRecovers() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        var writes=0
        let store=StateStore(root:root.appendingPathComponent("state"),stateWriter:{data,url in
            writes+=1
            if writes==2{throw POSIXError(.ENOSPC)}
            try data.write(to:url,options:.atomic)
        })
        var state=try attemptCompletion(store,root:root)
        XCTAssertEqual(writes,2)
        XCTAssertEqual(state.history.count,1)
        XCTAssertEqual(state.completionCleanup?.count,1)
        XCTAssertEqual(try receipts(store).count,1)
        state=try StateStore(root:store.root).load()
        XCTAssertEqual(state.history.count,1)
        XCTAssertTrue(state.completionCleanup?.isEmpty == true)
        XCTAssertTrue(try receipts(store).isEmpty)
    }
    func testReceiptDeleteFailureDoesNotRestoreUserDeletedHistory() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=StateStore(root:root.appendingPathComponent("state"),receiptRemover:{_ in throw POSIXError(.EACCES)})
        var state=try attemptCompletion(store,root:root)
        XCTAssertTrue(state.completionCleanup?.isEmpty == true)
        XCTAssertEqual(try receipts(store).count,1)
        state.jobs=[];state.history=[]
        try store.save(state)
        let reloaded=try StateStore(root:store.root).load()
        XCTAssertTrue(reloaded.jobs.isEmpty)
        XCTAssertTrue(reloaded.history.isEmpty)
        XCTAssertTrue(try receipts(store).isEmpty)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("files/video.mp4")),Data("media".utf8))
    }
    private func receipts(_ store:StateStore)throws->[URL]{try FileManager.default.contentsOfDirectory(at:store.root.appendingPathComponent("Completions"),includingPropertiesForKeys:nil)}
    private func attemptCompletion(_ store:StateStore,root:URL)throws->AppState {
        let job=DownloadJob(url:URL(string:"https://example.com/video")!,kind:.direct,mode:.video,quality:"best",folder:root.appendingPathComponent("files").path)
        let source=store.workDirectory(job.id).appendingPathComponent("received")
        try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("media".utf8).write(to:source)
        var state=AppState(jobs:[job])
        XCTAssertThrowsError(try store.complete(job:job,artifact:DownloadArtifact(file:source,name:"video.mp4",playback:PlaybackObservation(kind:.notChecked,detail:"fixture")),state:&state))
        return state
    }
}
