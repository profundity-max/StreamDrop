import Foundation

/// The complete bounded diagnostic and the one-line presentation have one owner.
/// Warnings (including update notices) must never hide a later actual error.
enum DownloadDiagnostics {
    static func report(job:DownloadJob,diagnostic:String,tools:[ToolObservation])->String {
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发版本"
        let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "未知"
        return "StreamDrop \(version) (\(build))\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n来源：\(job.url.absoluteString)\n方式：\(job.kind.rawValue) / \(job.mode.rawValue) / \(job.quality)\n当前工具检查（不代表失败发生时的版本）：\n"+tools.map(\.diagnostic).joined(separator:"\n")+"\n\n"+diagnostic
    }
    static func summary(_ diagnostic:String)->String {
        let lines=diagnostic.split(whereSeparator:\.isNewline).map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
        return lines.last(where:{$0.hasPrefix("ERROR:")}) ?? lines.last ?? "下载失败，请查看错误详情。"
    }
    static func save(_ diagnostic:String,in directory:URL) throws {
        try Data(diagnostic.utf8).write(to:directory.appendingPathComponent("yt-dlp.log"),options:.atomic)
    }
}
