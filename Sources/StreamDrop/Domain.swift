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
    var playback:PlaybackObservation?
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
    var completionCleanup:[UUID]?
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
final class StateStore {
    private var validated=false
    private var blockedReason:String?
    var canWrite:Bool {validated && blockedReason==nil}
    let root: URL
    private let stateWriter:(Data,URL)throws->Void
    let receiptRemover:(URL)throws->Void
    init(root: URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("StreamDrop"),
         stateWriter:@escaping(Data,URL)throws->Void = {try $0.write(to:$1,options:.atomic)},
         receiptRemover:@escaping(URL)throws->Void = {try FileManager.default.removeItem(at:$0)}) {
        self.root=root;self.stateWriter=stateWriter;self.receiptRemover=receiptRemover
    }
    func load() throws -> AppState {try loadWithRecovery().state}
    private func readState() throws -> AppState {
        let file=root.appendingPathComponent("state.json")
        let state=FileManager.default.fileExists(atPath:file.path) ? try JSONDecoder().decode(AppState.self,from:Data(contentsOf:file)) : AppState()
        guard state.version==1 else{throw InputError.invalid("不支持的数据版本；原状态文件保留在 \(file.path)")}
        return state
    }
    func requireWritable() throws {
        if let reason=blockedReason{throw InputError.invalid("状态存储不可写，原始记录已保留："+reason)}
        guard !validated else{return}
        do {_=try readState();validated=true}
        catch {blockedReason=error.localizedDescription;throw error}
    }
    func loadWithRecovery() throws -> (state:AppState,warnings:[String]) {
        do {
            var state=try readState()
            validated=true;blockedReason=nil
            let warnings=try recoverCompletions(state:&state)
            for index in state.jobs.indices where state.jobs[index].status.active {
                state.jobs[index].status = .paused
                state.jobs[index].detail="上次运行已中断；点击继续下载。"
            }
            return (state,warnings)
        }catch{validated=false;blockedReason=error.localizedDescription;throw error}
    }
    func save(_ state: AppState) throws {
        try requireWritable()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try stateWriter(encoder.encode(state),root.appendingPathComponent("state.json"))
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
