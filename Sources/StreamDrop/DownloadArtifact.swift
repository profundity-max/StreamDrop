import Foundation

struct PlaybackObservation:Codable,Equatable {
    enum Kind:String,Codable {case decoded,converted,unknown,notChecked}
    let kind:Kind
    let detail:String
    var label:String {
        switch kind {
        case .decoded:return "已解码画面"
        case .converted:return "已转换并解码画面"
        case .unknown:return "画面兼容性未知"
        case .notChecked:return "未检查画面兼容性"
        }
    }
}
struct DownloadArtifact {
    let file:URL
    let name:String
    let playback:PlaybackObservation
}
