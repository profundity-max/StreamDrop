import XCTest
@testable import StreamDrop
final class DiagnosticTests:ReportingTestCase {
    func testActualErrorTakesPriorityOverOldEngineWarning() {
        let log="\nWARNING: Your yt-dlp version (2026.07.04) is older than 90 days!\nIt is strongly recommended to always use the latest version.\nERROR: unable to download video data: HTTP Error 403: Forbidden"
        XCTAssertEqual(DownloadDiagnostics.summary(log),"ERROR: unable to download video data: HTTP Error 403: Forbidden")
    }
    func testGenericErrorsAndChineseMessagesArePreserved() {
        XCTAssertEqual(DownloadDiagnostics.summary("无法启动 yt-dlp：文件不存在"),"无法启动 yt-dlp：文件不存在")
        XCTAssertEqual(DownloadDiagnostics.summary("WARNING: first\nERROR: old error\nERROR: final error"),"ERROR: final error")
        XCTAssertEqual(DownloadDiagnostics.summary("\n  \n"),"下载失败，请查看错误详情。")
    }
}
