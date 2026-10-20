import Foundation

/// Owns preparation policy, its converter process and the final observation.
/// A stop never acknowledges while probing or converter cleanup is pending.
final class MediaPreparation {
    private let job:DownloadJob
    private let preferences:Preferences
    private let work:URL
    private let emit:(TransferEvent)->Void
    private let lock=NSLock()
    private var stopped=false
    private var process:OwnedProcess?
    private var buffer=Data()
    private var diagnostic=""
    init(job:DownloadJob,preferences:Preferences,work:URL,emit:@escaping(TransferEvent)->Void){
        self.job=job;self.preferences=preferences;self.work=work;self.emit=emit
    }
    func start(_ file:URL){Task{
        let result=await prepare(file)
        emit(isStopped ? .paused(nil) : result)
    }}
    func stop(){lock.lock();stopped=true;let child=process;lock.unlock();child?.stop()}
    private var isStopped:Bool {lock.lock();defer{lock.unlock()};return stopped}
    private func artifact(_ file:URL,_ kind:PlaybackObservation.Kind,_ detail:String,name:String?=nil)->TransferEvent{
        .finished(DownloadArtifact(file:file,name:name ?? file.lastPathComponent,playback:PlaybackObservation(kind:kind,detail:detail)))
    }
    private func prepare(_ file:URL) async -> TransferEvent {
        guard !isStopped else{return .paused(nil)}
        guard job.mode == .video,preferences.preferMP4 else{return artifact(file,.notChecked,"音频提取或兼容性检查已关闭。")}
        guard ["mp4","m4v","mov","webm","mkv"].contains(file.pathExtension.lowercased()) else{return artifact(file,.notChecked,"此文件类型不参与视频兼容性检查。")}
        let observation=await NativeVideoProbe.inspect(file)
        guard !isStopped else{return .paused(nil)}
        switch observation {
        case .decodable:return artifact(file,.decoded,"系统已解码到实际视频画面；未检查整片或音轨。")
        case let .unknown(reason):return artifact(file,.unknown,reason)
        case let .unsupported(reason,duration):return await convert(file,reason:reason,duration:duration)
        }
    }
    private func convert(_ file:URL,reason:String,duration:Double?) async -> TransferEvent {
        guard let ffmpeg=ToolPaths.find(preferences.ffmpeg,name:"ffmpeg") else{return .failed("ERROR: 系统无法解码该视频，需配置 FFmpeg 转为兼容编码。\n"+reason)}
        let target=work.appendingPathComponent("system-compatible.mp4")
        guard target.standardizedFileURL != file.standardizedFileURL else{return .failed("兼容产物路径与原始文件相同，原文件已保留。")}
        do {if FileManager.default.fileExists(atPath:target.path){try FileManager.default.removeItem(at:target)}}
        catch{return .failed("无法清理未完成的兼容副本："+error.localizedDescription)}
        diagnostic=(try? String(contentsOf:work.appendingPathComponent("yt-dlp.log"),encoding:.utf8)) ?? ""
        append("系统无法解码原始视频；转换 H.264："+reason)
        emit(.processing(0,"正在转换为系统兼容的 H.264…"))
        let status:Int32=await withCheckedContinuation{continuation in
            let child=OwnedProcess(onData:{[weak self] data in self?.consume(data,duration:duration)},onExit:{[weak self] code in
                if let self {
                    self.consume(Data([10]),duration:duration)
                    do{try DownloadDiagnostics.save(self.diagnostic,in:self.work)}catch{self.append("日志未保存："+error.localizedDescription)}
                }
                continuation.resume(returning:code)
            })
            lock.lock()
            guard !stopped else{lock.unlock();continuation.resume(returning:-1);return}
            process=child
            do{
                try child.start(executable:ffmpeg,arguments:["-hide_banner","-nostdin","-n","-i",file.path,"-map","0:v:0","-map","0:a?","-c:v","libx264","-preset","fast","-crf","18","-threads","4","-pix_fmt","yuv420p","-c:a","aac","-b:a","192k","-movflags","+faststart","-progress","pipe:1","-nostats",target.path],environment:ToolPaths.environment())
                lock.unlock()
            }catch{lock.unlock();append(error.localizedDescription);continuation.resume(returning:-1)}
        }
        guard !isStopped else{return .paused(nil)}
        guard status==0,FileManager.default.fileExists(atPath:target.path) else{return .failed("ERROR: 视频兼容转换失败。原始下载保留在工作目录。\n"+diagnostic)}
        let check=await NativeVideoProbe.inspect(target)
        guard !isStopped else{return .paused(nil)}
        guard case .decodable=check else{return .failed("ERROR: 转换后仍无法验证系统视频解码。\n"+diagnostic)}
        return artifact(target,.converted,"H.264 转换后已解码到实际画面；未检查整片或音轨。原始解码原因："+reason,name:(file.lastPathComponent as NSString).deletingPathExtension+".mp4")
    }
    private func append(_ line:String){diagnostic=String((diagnostic+"\n"+line).suffix(5000))}
    private func consume(_ data:Data,duration:Double?){
        buffer.append(data)
        if buffer.count>131072{buffer=Data(buffer.suffix(32768))}
        while let end=buffer.firstIndex(of:10){
            let line=String(decoding:buffer[..<end],as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            buffer.removeSubrange(...end)
            if line.hasPrefix("out_time_us=") {
                let seconds=(Double(line.dropFirst(12)) ?? 0)/1_000_000
                emit(.processing((duration ?? 0)>0 ? min(1,seconds/duration!) : 0,"正在转换为系统兼容的 H.264…"))
            }else if !line.isEmpty{append(line)}
        }
    }
}
