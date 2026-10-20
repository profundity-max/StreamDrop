import XCTest
@testable import StreamDrop

final class FileNameTests:ReportingTestCase {
    func testLongTitlesPreserveExtensionAndFitActualDirectory() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        for title in [String(repeating:"a",count:190),String(repeating:"👩🏽‍💻",count:120),String(repeating:"中文",count:180)] {
            let first=try FileNames.available(title+".mp4",in:root)
            XCTAssertEqual(first.pathExtension,"mp4")
            try Data("first".utf8).write(to:first,options:.withoutOverwriting)
            let second=try FileNames.available(title+".mp4",in:root)
            XCTAssertEqual(second.pathExtension,"mp4")
            XCTAssertTrue(second.deletingPathExtension().lastPathComponent.hasSuffix(" (2)"))
            try Data("second".utf8).write(to:second,options:.withoutOverwriting)
            XCTAssertEqual(try Data(contentsOf:first),Data("first".utf8))
        }
    }
    func testOrdinaryTitleKeepsSpacesAndNaturalBrackets() throws {
        let root=FileManager.default.temporaryDirectory
        let title="中文 视频 [2026] .mp4"
        XCTAssertEqual(try FileNames.available(title,in:root).lastPathComponent,title)
    }
}
