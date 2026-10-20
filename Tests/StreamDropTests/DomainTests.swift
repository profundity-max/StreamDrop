import XCTest
@testable import StreamDrop
final class DomainTests: XCTestCase {
    func testURLInputKeepsQueryAndRejectsUnsupportedSchemes() throws {
        let urls = try LinkInput.parse("https://example.com/a?q=1&b=2\nhttp://localhost:123/video.mp4")
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].query, "q=1&b=2")
        XCTAssertThrowsError(try LinkInput.parse("file:///etc/passwd"))
        XCTAssertThrowsError(try LinkInput.parse("https://example.com valid-no-scheme"))
        XCTAssertThrowsError(try LinkInput.parse(""))
    }
    func testCompletedFileNeverOverwritesExistingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("original".utf8).write(to: root.appendingPathComponent("video.mp4"))
        let destination = try FileNames.available("../video.mp4", in: root)
        XCTAssertEqual(destination.lastPathComponent, "video (2).mp4")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("video.mp4")), "original")
    }
    func testStoragePreservesQueryAndRecoversInterruptedTaskAsPaused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(root: root)
        var state = AppState()
        var job = DownloadJob(url: URL(string:"https://example.com/a.mp4?key=public")!, kind: .direct, mode: .video, quality: "best", folder: root.path)
        job.status = .downloading
        state.jobs = [job]
        try store.save(state)
        let loaded = try store.load()
        XCTAssertEqual(loaded.jobs.first?.status, .paused)
        XCTAssertEqual(loaded.jobs.first?.url.query, "key=public")
    }
    func testResumeEnvelopeBindsURLAndDetectsCorruption() throws {
        let url=URL(string:"https://example.com/video.mp4")!
        let blob=Data("opaque-system-bytes".utf8)
        let record=try ResumeRecord(data:blob,url:url).encoded()
        XCTAssertEqual(ResumeRecord.validated(record,for:url),blob)
        XCTAssertNil(ResumeRecord.validated(record,for:URL(string:"https://example.com/another.mp4")!))
        XCTAssertNil(ResumeRecord.validated(Data("invalid".utf8),for:url))
        var dict=try JSONSerialization.jsonObject(with:record) as! [String:Any]
        dict["data"]=Data("changed".utf8).base64EncodedString()
        XCTAssertNil(ResumeRecord.validated(try JSONSerialization.data(withJSONObject:dict),for:url))
    }
    func testCorruptedStateFailsWithoutOverwritingEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("broken".utf8)
        try data.write(to: root.appendingPathComponent("state.json"))
        XCTAssertThrowsError(try StateStore(root:root).load())
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("state.json")),data)
    }
}
