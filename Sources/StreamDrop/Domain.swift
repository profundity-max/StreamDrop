import Foundation
import CryptoKit

enum JobStatus: String, Codable {
    case queued, resolving, downloading, pausing, paused, completed, failed, cancelled
    var active: Bool { [.resolving, .downloading, .pausing].contains(self) }
    var label: String {
        switch self {
        case .queued: return "等待下载"
        case .resolving: return "正在解析…"
        case .downloading: return "正在下载"
        case .pausing: return "正在暂停…"
        case .paused: return "已暂停"
        case .completed: return "下载完成"
        case .failed: return "下载失败"
        case .cancelled: return "已取消"
        }
    }
}
enum SourceKind: String, Codable, CaseIterable { case automatic, direct, webpage
    var title: String { switch self { case .automatic: return "自动识别"; case .direct: return "文件直链"; case .webpage: return "网页视频 / HLS" } }
}
enum MediaMode: String, Codable, CaseIterable { case video, audio
    var title: String { self == .video ? "原始视频 / 文件" : "提取音频 · M4A" }
}
struct DownloadJob: Codable, Identifiable {
    var id = UUID()
    var url: URL
    var kind: SourceKind
    var mode: MediaMode
    var quality: String
    var folder: String
    var title: String
    var status = JobStatus.queued
    var progress: Double = 0
    var received: Int64 = 0
    var expected: Int64 = 0
    var detail: String = ""
    var outputPath: String?
    var fileSize: Int64?
    var created = Date()
    var completedAt: Date?
    init(url: URL, kind: SourceKind, mode: MediaMode, quality: String, folder: String) {
        self.url = url; self.kind = kind; self.mode = mode; self.quality = quality; self.folder = folder
        self.title = url.lastPathComponent.isEmpty ? (url.host ?? "下载") : url.lastPathComponent
    }
    var useDirect: Bool {
        if mode == .audio { return false }
        if kind == .direct { return true }
        if kind == .webpage { return false }
        return ["mp4","mov","m4v","mp3","m4a","wav","flac","ogg","webm","mkv","zip","pdf","dmg","bin","jpg","png"].contains(url.pathExtension.lowercased())
    }
}
struct Preferences: Codable {
    var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
    var autoStart = true
    var concurrency = 3
    var quality = "best"
    var preferMP4 = true
    var ytDLP = ""
    var ffmpeg = ""
}
struct AppState: Codable {
    var version = 1
    var jobs: [DownloadJob] = []
    var history: [DownloadJob] = []
    var preferences = Preferences()
}
enum InputError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return text } }
}
enum LinkInput {
    static func parse(_ text: String) throws -> [URL] {
        let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !parts.isEmpty else { throw InputError.invalid("请填写至少一个 HTTP 或 HTTPS 链接。") }
        var seen = Set<String>()
        return try parts.compactMap { part in
            guard let url = URL(string: part), let scheme = url.scheme?.lowercased(), ["http","https"].contains(scheme), let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                throw InputError.invalid("无效链接：\(part)\n请输入完整的 HTTP(S) 地址，不要在链接中填写登录凭据。")
            }
            return seen.insert(url.absoluteString).inserted ? url : nil
        }
    }
}
enum FileNames {
    static func safe(_ name: String) -> String {
        let leaf = (name as NSString).lastPathComponent
        let bad = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: ":/\\"))
        let clean = leaf.components(separatedBy: bad).joined(separator:"_").trimmingCharacters(in:.whitespacesAndNewlines)
        return clean.isEmpty || clean == "." || clean == ".." ? "download" : String(clean.prefix(180))
    }
    static func available(_ name: String, in directory: URL) -> URL {
        let clean = safe(name)
        let ext = (clean as NSString).pathExtension
        let base = (clean as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(clean)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(number))" + (ext.isEmpty ? "" : ".\(ext)")); number += 1
        }
        return candidate
    }
}
struct StateStore {
    let root: URL
    init(root: URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("StreamDrop")) { self.root = root }
    func load() throws -> AppState {
        let file = root.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath:file.path) else { return AppState() }
        var state = try JSONDecoder().decode(AppState.self,from:Data(contentsOf:file))
        guard state.version == 1 else { throw InputError.invalid("不支持的数据版本；原状态文件保留在 \(file.path)") }
        for index in state.jobs.indices where state.jobs[index].status.active {
            state.jobs[index].status = .paused
            state.jobs[index].detail = "上次运行已中断；点击继续下载。"
        }
        return state
    }
    func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(state).write(to:root.appendingPathComponent("state.json"),options:.atomic)
    }
    func workDirectory(_ id: UUID) -> URL { root.appendingPathComponent("Transfers").appendingPathComponent(id.uuidString) }
}

/// Resume bytes are opaque OS output. An app-owned envelope binds their integrity
/// and original URL before passing them back to URLSession's private decoder.
struct ResumeRecord:Codable {
    let version:Int
    let url:String
    let data:Data
    let sha256:String
    init(data:Data,url:URL){version=1;self.url=url.absoluteString;self.data=data;sha256=Self.digest(data)}
    func encoded() throws -> Data {try JSONEncoder().encode(self)}
    static func validated(_ bytes:Data,for url:URL)->Data? {
        guard let record=try? JSONDecoder().decode(Self.self,from:bytes),record.version==1,record.url==url.absoluteString,!record.data.isEmpty,record.sha256==digest(record.data) else{return nil}
        return record.data
    }
    private static func digest(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
}
