import Foundation
import AVFoundation
import CoreVideo

enum NativeVideoProbe {
    enum Observation {
        case decodable
        case unsupported(reason:String,duration:Double?)
        case unknown(reason:String)
    }
    /// A declared video track is insufficient: require an actual decoded pixel buffer.
    static func inspect(_ file:URL) async -> Observation {
        do {
            let asset=AVURLAsset(url:file)
            let tracks=try await asset.loadTracks(withMediaType:.video)
            guard let track=tracks.first else{return .unknown(reason:"未建立原生视频轨道信息")}
            let duration=(try? await asset.load(.duration))?.seconds
            let reader=try AVAssetReader(asset:asset)
            let output=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
            guard reader.canAdd(output) else{return .unknown(reason:"系统未接受视频解码输出")}
            reader.add(output)
            defer{reader.cancelReading()}
            guard reader.startReading(),let sample=output.copyNextSampleBuffer(),CMSampleBufferGetImageBuffer(sample) != nil else {
                return .unsupported(reason:reader.error?.localizedDescription ?? "系统无法解码视频画面",duration:duration?.isFinite == true ? duration : nil)
            }
            return .decodable
        }catch{return .unknown(reason:error.localizedDescription)}
    }
}
