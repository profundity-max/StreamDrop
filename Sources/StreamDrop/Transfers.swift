import Foundation

enum TransferEvent {
    case progress(Double, Int64, Int64, String)
    case finished(DownloadArtifact)
    case processing(Double,String)
    case failed(String)
    case paused(Data?)
    case cancelled
}
protocol Transfer: AnyObject { func start(); func pause(); func cancel() }

final class DirectTransfer: NSObject, Transfer, URLSessionDownloadDelegate {
    let job: DownloadJob
    let work: URL
    let emit: (TransferEvent) -> Void
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var resuming=false
    private var stopping=false
    private var wantsPause=false
    private var waitingResume=false
    private var resumeData:Data?
    private var invalidated=false
    private var settled=false
    private var outcome:TransferEvent?
    private let taskLock=NSLock()
    init(job: DownloadJob, work: URL, emit:@escaping (TransferEvent)->Void) {
        self.job=job; self.work=work; self.emit=emit
        super.init()
        let config=URLSessionConfiguration.default
        config.timeoutIntervalForRequest=45; config.timeoutIntervalForResource=86400
        session=URLSession(configuration:config,delegate:self,delegateQueue:nil)
    }
    func start() {
        taskLock.lock();defer{taskLock.unlock()}
        let resume=work.appendingPathComponent("resume.data")
        let saved=try? Data(contentsOf:resume)
        if saved != nil {try? FileManager.default.removeItem(at:resume)}
        if let saved,let data=ResumeRecord.validated(saved,for:job.url) {
            resuming=true
            task=session.downloadTask(withResumeData:data)
        }
        else {
            var request=URLRequest(url:job.url)
            request.setValue("StreamDrop/1.0",forHTTPHeaderField:"User-Agent")
            task=session.downloadTask(with:request)
        }
        task?.resume()
    }
    func pause() {
        taskLock.lock()
        guard !settled,!wantsPause else{taskLock.unlock();return}
        stopping=true;wantsPause=true;waitingResume=true
        let current=task;taskLock.unlock()
        if let current {current.cancel(byProducingResumeData:{[self] data in
            taskLock.lock();resumeData=data;waitingResume=false;taskLock.unlock();settleIfReady()
        })} else {taskLock.lock();waitingResume=false;taskLock.unlock();settleIfReady()}
    }
    func cancel(){taskLock.lock();stopping=true;let current=task;taskLock.unlock();current?.cancel()}
    private func record(_ event:TransferEvent){taskLock.lock();outcome=event;taskLock.unlock()}
    private func settleIfReady(){
        taskLock.lock()
        guard invalidated,!waitingResume,!settled else{taskLock.unlock();return}
        settled=true
        let result:TransferEvent=wantsPause ? .paused(resumeData) : (outcome ?? .failed("下载已停止。"))
        taskLock.unlock();emit(result)
    }
    func urlSession(_ session:URLSession,didBecomeInvalidWithError error:Error?){
        taskLock.lock();invalidated=true;taskLock.unlock();settleIfReady()
    }
    func urlSession(_ session:URLSession, downloadTask:URLSessionDownloadTask, didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        let progress=totalBytesExpectedToWrite>0 ? Double(totalBytesWritten)/Double(totalBytesExpectedToWrite) : 0
        emit(.progress(progress,totalBytesWritten,totalBytesExpectedToWrite,""))
    }
    func urlSession(_ session:URLSession, downloadTask:URLSessionDownloadTask, didFinishDownloadingTo location:URL) {
        taskLock.lock();let stopped=stopping;taskLock.unlock()
        guard !stopped else{return}
        guard let response=downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            record(.failed("HTTP \((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)：服务器拒绝或无法找到文件。")); return
        }
        if response.mimeType?.lowercased().contains("text/html") == true {
            record(.failed("服务器返回了网页。请改用「网页视频」方式解析该链接。")); return
        }
        do {
            let file=work.appendingPathComponent("received")
            if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
            try FileManager.default.moveItem(at:location,to:file)
            record(.finished(DownloadArtifact(file:file,name:response.suggestedFilename ?? job.title,playback:PlaybackObservation(kind:.notChecked,detail:"文件直链保留原始字节，不检查视频兼容性。"))))
        } catch { record(.failed(error.localizedDescription)) }
    }
    func urlSession(_ session:URLSession, task:URLSessionTask, didCompleteWithError error:Error?) {
        taskLock.lock()
        guard task === self.task else{taskLock.unlock();return}
        if let error,resuming,!stopping,(error as NSError).code != NSURLErrorCancelled {
            // Task replacement and stopping share one ownership boundary. A pause
            // cannot acknowledge the old task while this starts a hidden fallback.
            resuming=false
            self.task=session.downloadTask(with:URLRequest(url:job.url))
            self.task?.resume()
            taskLock.unlock()
            return
        }
        let stopped=stopping
        taskLock.unlock()
        if let error {record(.failed(error.localizedDescription))}
        else if stopped {record(.failed("下载已停止。"))}
        session.finishTasksAndInvalidate()
    }

}

enum ToolPaths {
    static func environment()->[String:String]{
        var env=ProcessInfo.processInfo.environment
        env["PATH"]="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";env["PYTHONUNBUFFERED"]="1"
        return env
    }
    static func find(_ configured:String, name:String) -> String? {
        let paths=configured.isEmpty ? ["/opt/homebrew/bin/\(name)","/usr/local/bin/\(name)","/usr/bin/\(name)"] : [configured]
        return paths.first { FileManager.default.isExecutableFile(atPath:$0) }
    }
}
final class WebTransfer: Transfer {
    let job:DownloadJob
    let preferences:Preferences
    let work:URL
    let emit:(TransferEvent)->Void
    private var process:OwnedProcess?
    private var preparation:MediaPreparation?
    private var buffer=Data()
    private var tail=""
    private var output:URL?
    private var received:Int64=0
    private var expected:Int64=0
    private var stopped=false
    private let lock=NSLock()
    init(job:DownloadJob,preferences:Preferences,work:URL,emit:@escaping(TransferEvent)->Void){self.job=job;self.preferences=preferences;self.work=work;self.emit=emit}
    func start(){
        guard let tool=ToolPaths.find(preferences.ytDLP,name:"yt-dlp") else {
            emit(.failed("未找到 yt-dlp。请在设置 → 外部工具中选择已安装的可执行文件；文件直链可直接下载。"));return
        }
        var args=["--ignore-config","--no-playlist","--newline","--no-colors","--no-restrict-filenames","--continue","--no-overwrites","--progress","--progress-template","download:SDPROGRESS:%(progress._percent_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes_estimate)s|%(progress._speed_str)s","--print","after_move:SDOUTPUT:%(filepath)s","-o",work.appendingPathComponent("%(title).130s.%(ext)s").path]
        let ffmpeg=ToolPaths.find(preferences.ffmpeg,name:"ffmpeg")
        if let ffmpeg{args += ["--ffmpeg-location",ffmpeg]}
        if job.mode == .audio {
            guard ffmpeg != nil else{emit(.failed("提取音频需要 FFmpeg，请在设置中配置。"));return}
            args += ["-f","bestaudio/best","-x","--audio-format","m4a"]
        } else {
            let constraint=Int(job.quality).map{"[height<=\($0)]"} ?? ""
            if preferences.preferMP4 {args += ["--format-sort","res,vcodec:h264,acodec:aac"]}
            if ffmpeg != nil {
                let format=preferences.preferMP4 ? "bv*\(constraint)[ext=mp4]+ba[ext=m4a]/b\(constraint)[ext=mp4]/b\(constraint)/b" : "bv*\(constraint)+ba/b\(constraint)/b"
                args += ["-f",format]
            } else{args += ["-f","b\(constraint)/b"]}
        }
        args += ["--",job.url.absoluteString]
        let child=OwnedProcess(onData:{[weak self] data in self?.consume(data)},onExit:{[weak self] status in
            guard let self else{return}
            self.consume(Data([10]))
            self.saveLog()
            guard !self.finishStopIfNeeded() else{return}
            guard status==0,let file=self.output,FileManager.default.fileExists(atPath:file.path) else{
                self.emit(.failed(self.tail.isEmpty ? "解析工具异常退出（\(status)）" : self.tail));return
            }
            self.prepareOutput(file)
        })
        launch(child,executable:tool,arguments:args)
    }
    /// A stage launch and a stop share the same owner/lock. No late probe or child
    /// exit can start conversion after pause/cancel has been acknowledged.
    private func launch(_ child:OwnedProcess,executable:String,arguments:[String]){
        lock.lock()
        if stopped {lock.unlock();_=finishStopIfNeeded();return}
        process=child
        do{try child.start(executable:executable,arguments:arguments,environment:ToolPaths.environment());lock.unlock()}
        catch{lock.unlock();emit(.failed("无法启动处理工具：\(error.localizedDescription)"))}
    }
    private func finishStopIfNeeded()->Bool{
        lock.lock();let requested=stopped;lock.unlock()
        if requested {emit(.paused(nil));return true}
        return false
    }
    private func prepareOutput(_ file:URL){
        let next=MediaPreparation(job:job,preferences:preferences,work:work,emit:emit)
        lock.lock();preparation=next;if stopped{next.stop()};lock.unlock()
        next.start(file)
    }
    private func saveLog(){do{try DownloadDiagnostics.save(tail,in:work)}catch{tail += "\n日志未能写入文件：\(error.localizedDescription)"}}
    private func consume(_ data:Data){
        buffer.append(data)
        if buffer.count>131072{buffer=Data(buffer.suffix(32768))}
        while let end=buffer.firstIndex(of:10){
            let line=String(decoding:buffer[..<end],as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            buffer.removeSubrange(...end)
            if line.hasPrefix("SDPROGRESS:") {
                let fields=line.dropFirst(11).components(separatedBy:"|")
                if fields.count>=4 {
                    let percent=Double(fields[0].replacingOccurrences(of:"%",with:"").trimmingCharacters(in:.whitespaces)) ?? 0
                    received=Int64(fields[1]) ?? 0;expected=Int64(fields[2]) ?? 0
                    emit(.progress(percent/100,received,expected,fields[3]))
                }
            } else if line.hasPrefix("SDOUTPUT:") {
                let file=URL(fileURLWithPath:String(line.dropFirst(9))).standardizedFileURL
                if file.path.hasPrefix(work.standardizedFileURL.path+"/"){output=file}
            } else if !line.isEmpty {tail=String((tail+"\n"+line).suffix(5000))}
        }
    }
    private func stop(){lock.lock();stopped=true;let child=process;let next=preparation;lock.unlock();child?.stop();next?.stop()}
    func pause(){stop()}
    func cancel(){stop()}
}
