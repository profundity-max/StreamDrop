import Foundation

/// The complete bounded diagnostic and the one-line presentation have one owner.
/// Warnings (including update notices) must never hide a later actual error.
enum DownloadDiagnostics {
    static func summary(_ diagnostic:String)->String {
        let lines=diagnostic.split(whereSeparator:\.isNewline).map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
        return lines.last(where:{$0.hasPrefix("ERROR:")}) ?? lines.last ?? "下载失败，请查看错误详情。"
    }
    static func save(_ diagnostic:String,in directory:URL) throws {
        try Data(diagnostic.utf8).write(to:directory.appendingPathComponent("yt-dlp.log"),options:.atomic)
    }
}
