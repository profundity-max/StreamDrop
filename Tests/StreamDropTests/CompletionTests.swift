import XCTest
@testable import StreamDrop
final class CompletionTests:ReportingTestCase {
    func testMovedFileSurvivesStateSaveFailureAndReloadIsIdempotent() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=StateStore(root:root.appendingPathComponent("state"))
        var job=DownloadJob(url:URL(string:"https://example.com/video.mp4")!,kind:.direct,mode:.video,quality:"best",folder:root.appendingPathComponent("files").path)
        job.status = .downloading
        let source=store.workDirectory(job.id).appendingPathComponent("received")
        try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("original media".utf8).write(to:source)
        var state=AppState(jobs:[job])
        // A real filesystem failure: state.json cannot replace a directory.
        let blocked=store.root.appendingPathComponent("state.json")
        try store.save(state)
        try FileManager.default.removeItem(at:blocked)
        try FileManager.default.createDirectory(at:blocked,withIntermediateDirectories:false)
        XCTAssertThrowsError(try store.complete(job:job,artifact:DownloadArtifact(file:source,name:"video.mp4",playback:PlaybackObservation(kind:.notChecked,detail:"fixture")),state:&state))
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("files/video.mp4").path))
        XCTAssertNil(state.completionCleanup,"Failed save must not authorize cleanup")
        XCTAssertThrowsError(try store.complete(job:job,artifact:DownloadArtifact(file:source,name:"video.mp4",playback:PlaybackObservation(kind:.notChecked,detail:"fixture")),state:&state))
        XCTAssertTrue(FileManager.default.fileExists(atPath:store.root.appendingPathComponent("Completions/"+job.id.uuidString+".json").path))
        try FileManager.default.removeItem(at:blocked)
        let recovered=try store.load()
        XCTAssertEqual(recovered.jobs.first?.status,.completed)
        XCTAssertEqual(recovered.history.count,1)
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:XCTUnwrap(recovered.jobs.first?.outputPath))),Data("original media".utf8))
        XCTAssertEqual(try store.load().history.count,1)
        XCTAssertFalse(FileManager.default.fileExists(atPath:source.deletingLastPathComponent().path))
    }
    func testCleanupFailureRetainsReceiptAndRetriesOnReload() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=StateStore(root:root.appendingPathComponent("state"))
        let job=DownloadJob(url:URL(string:"https://example.com/file")!,kind:.direct,mode:.video,quality:"best",folder:root.appendingPathComponent("files").path)
        let work=store.workDirectory(job.id),source=work.appendingPathComponent("received")
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
        try Data("media".utf8).write(to:source)
        try Data("diagnostics".utf8).write(to:work.appendingPathComponent("log"))
        let locked=work.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at:locked,withIntermediateDirectories:false)
        try Data("retained".utf8).write(to:locked.appendingPathComponent("data"))
        try FileManager.default.setAttributes([.posixPermissions:0o500],ofItemAtPath:locked.path)
        defer{try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:locked.path)}
        var state=AppState(jobs:[job])
        XCTAssertThrowsError(try store.complete(job:job,artifact:DownloadArtifact(file:source,name:"file.bin",playback:PlaybackObservation(kind:.notChecked,detail:"fixture")),state:&state))
        XCTAssertEqual(state.jobs.first?.status,.completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath:store.root.appendingPathComponent("Completions/"+job.id.uuidString+".json").path))
        let stillBlocked=try store.loadWithRecovery()
        XCTAssertEqual(stillBlocked.state.history.count,1)
        XCTAssertFalse(stillBlocked.warnings.isEmpty)
        var cleared=stillBlocked.state
        cleared.jobs=[];cleared.history=[];cleared.completionCleanup=[]
        try store.save(cleared)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:locked.path)
        XCTAssertTrue(try store.load().history.isEmpty)
        XCTAssertTrue(try store.load().jobs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:work.path))
    }
    func testRecoveryDoesNotAdoptReplacedTarget() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=StateStore(root:root.appendingPathComponent("state"))
        let job=DownloadJob(url:URL(string:"https://example.com/file")!,kind:.direct,mode:.video,quality:"best",folder:root.appendingPathComponent("files").path)
        let source=store.workDirectory(job.id).appendingPathComponent("received")
        try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("media".utf8).write(to:source)
        let blocked=store.root.appendingPathComponent("state.json")
        var state=AppState(jobs:[job])
        try store.save(state)
        try FileManager.default.removeItem(at:blocked)
        try FileManager.default.createDirectory(at:blocked,withIntermediateDirectories:false)
        XCTAssertThrowsError(try store.complete(job:job,artifact:DownloadArtifact(file:source,name:"file.bin",playback:PlaybackObservation(kind:.notChecked,detail:"fixture")),state:&state))
        let target=root.appendingPathComponent("files/file.bin")
        // Keep the owned inode alive so a replacement cannot reuse its identity.
        try FileManager.default.moveItem(at:target,to:root.appendingPathComponent("owned-original"))
        try Data("foreign".utf8).write(to:target)
        try FileManager.default.removeItem(at:blocked)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf:target),Data("foreign".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath:store.root.appendingPathComponent("Completions/"+job.id.uuidString+".json").path))
    }
    func testExistingOutputRemainsUntouched() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=StateStore(root:root.appendingPathComponent("state"))
        let folder=root.appendingPathComponent("files")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try Data("existing".utf8).write(to:folder.appendingPathComponent("video.mp4"))
        let job=DownloadJob(url:URL(string:"https://example.com/video.mp4")!,kind:.direct,mode:.video,quality:"best",folder:folder.path)
        let source=store.workDirectory(job.id).appendingPathComponent("received")
        try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("new".utf8).write(to:source)
        var state=AppState(jobs:[job])
        try store.complete(job:job,artifact:DownloadArtifact(file:source,name:"video.mp4",playback:PlaybackObservation(kind:.notChecked,detail:"fixture")),state:&state)
        XCTAssertEqual(try Data(contentsOf:folder.appendingPathComponent("video.mp4")),Data("existing".utf8))
        XCTAssertEqual(state.jobs.first?.title,"video (2).mp4")
    }
}
