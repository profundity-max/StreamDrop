import Foundation

enum MediaTool:String,CaseIterable {case ytDLP="yt-dlp",ffmpeg}
struct ToolObservation {
    let tool:MediaTool
    let path:String?
    let version:String?
    let detail:String
    var usable:Bool{version != nil}
    var diagnostic:String{"\(tool.rawValue): \(version ?? detail)\n路径：\(path ?? "未找到")"}
}
@MainActor final class ToolHealth {
    static let shared=ToolHealth()
    private var checks:[UUID:VersionCheck]=[:]
    private var closing=false
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    func check(_ tool:MediaTool,configured:String,timeout:Double=30) async -> ToolObservation {
        guard !closing else{return ToolObservation(tool:tool,path:nil,version:nil,detail:"应用正在退出")}
        guard let path=ToolPaths.find(configured,name:tool.rawValue) else{return ToolObservation(tool:tool,path:nil,version:nil,detail:"未找到可执行文件")}
        let check=VersionCheck(tool:tool,path:path,timeout:timeout)
        let id=UUID();checks[id]=check
        let result=await withTaskCancellationHandler(operation:{await check.run()},onCancel:{check.stop(cancelled:true)})
        checks[id]=nil
        if checks.isEmpty{let pending=waiters;waiters=[];for waiter in pending{waiter.resume()}}
        return result
    }
    func shutdown() async {
        closing=true
        for check in checks.values{check.stop(cancelled:true)}
        if !checks.isEmpty{await withCheckedContinuation{waiters.append($0)}}
    }
}

/// Owns a bounded version probe and waits for process/output cleanup even on timeout.
private final class VersionCheck {
    private let tool:MediaTool,path:String,timeout:Double
    private let lock=NSLock()
    private var process:OwnedProcess?
    private var bytes=Data()
    private var stopped:String?
    private var finished=false
    init(tool:MediaTool,path:String,timeout:Double){self.tool=tool;self.path=path;self.timeout=timeout}
    func run() async -> ToolObservation {
        await withCheckedContinuation{continuation in
            lock.lock()
            if let stopped{lock.unlock();continuation.resume(returning:observation(nil,stopped));return}
            let child=OwnedProcess(onData:{[weak self] data in
                guard let self else{return}
                self.lock.lock();defer{self.lock.unlock()}
                self.bytes.append(data.prefix(max(0,8192-self.bytes.count)))
            },onExit:{[self] code in
                lock.lock();finished=true;process=nil
                let output=String(decoding:bytes,as:UTF8.self),reason=stopped
                lock.unlock()
                let first=output.split(whereSeparator:\.isNewline).first.map(String.init) ?? ""
                let valid=tool == .ffmpeg ? first.hasPrefix("ffmpeg version ") : first.range(of:#"^\d{4}\.\d{2}\.\d{2}(?:[.\w+-]*)?$"#,options:.regularExpression) != nil
                let result:ToolObservation
                if let reason{result=observation(nil,reason)}
                else if code != 0{result=observation(nil,"版本检查退出失败（\(code)）："+String(output.prefix(500)))}
                else if !valid{result=observation(nil,"未返回可识别的 \(tool.rawValue) 版本")}
                else{result=observation(String(first.prefix(300)),"检查通过")}
                continuation.resume(returning:result)
            })
            process=child
            do{try child.start(executable:path,arguments:[tool == .ffmpeg ? "-version" : "--version"],environment:ToolPaths.environment());lock.unlock()}
            catch{finished=true;process=nil;lock.unlock();continuation.resume(returning:observation(nil,"无法运行："+error.localizedDescription));return}
            DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+timeout){[weak self] in self?.stop(cancelled:false)}
        }
    }
    func stop(cancelled:Bool){
        lock.lock();guard !finished,stopped==nil else{lock.unlock();return}
        stopped=cancelled ? "检查已取消" : "版本检查超时"
        let child=process;lock.unlock();child?.stop()
    }
    private func observation(_ version:String?,_ detail:String)->ToolObservation{ToolObservation(tool:tool,path:path,version:version,detail:detail)}
}
