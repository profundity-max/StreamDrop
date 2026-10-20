import Foundation
import Darwin

/// A receipt owns an interrupted completion until both durable state and cleanup
/// succeed. File identity, not a matching name or size, authorizes recovery.
private struct CompletionReceipt:Codable {
    var job:DownloadJob
    let source:URL
    let target:URL
    var identity:FileIdentity
    var stateCommitted:Bool? = nil
}
private struct FileIdentity:Codable,Equatable {
    let device:Int32
    let inode:UInt64
    let generation:UInt32
    let birthSeconds:Int64
    let birthNanoseconds:Int64
    static func read(_ file:URL)throws->Self {
        var info=stat()
        guard lstat(file.path,&info)==0 else{throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)}
        guard info.st_mode & S_IFMT == S_IFREG else{throw InputError.invalid("完成文件不是普通文件：\(file.path)")}
        return Self(device:info.st_dev,inode:info.st_ino,generation:info.st_gen,birthSeconds:Int64(info.st_birthtimespec.tv_sec),birthNanoseconds:Int64(info.st_birthtimespec.tv_nsec))
    }
}
private struct CleanupFailure:LocalizedError {
    let reason:String
    var errorDescription:String?{"下载已完成，部分清理待重试："+reason}
}
enum ExecutionReadiness {case start,recovered(warnings:[String])}

extension StateStore {
    private var receipts:URL {root.appendingPathComponent("Completions",isDirectory:true)}
    private func receiptPath(_ id:UUID)->URL{receipts.appendingPathComponent(id.uuidString+".json")}
    private func write(_ receipt:CompletionReceipt)throws{
        try FileManager.default.createDirectory(at:receipts,withIntermediateDirectories:true)
        try JSONEncoder().encode(receipt).write(to:receiptPath(receipt.job.id),options:.atomic)
    }
    func prepareExecution(for id:UUID,state:inout AppState)throws -> ExecutionReadiness {
        try requireWritable()
        guard FileManager.default.fileExists(atPath:receiptPath(id).path) else{return .start}
        let warnings=try recoverCompletions(state:&state,only:id)
        guard state.jobs.first(where:{$0.id==id})?.status == .completed else{
            throw InputError.invalid("完成恢复后的任务状态无法确认；没有启动新下载。")
        }
        return .recovered(warnings:warnings)
    }
    func complete(job:DownloadJob,artifact:DownloadArtifact,state:inout AppState)throws {
        try requireWritable()
        let file=artifact.file,name=artifact.name,playback=artifact.playback
        // Recover any earlier attempt before selecting a new name or moving bytes.
        if FileManager.default.fileExists(atPath:receiptPath(job.id).path){_=try recoverCompletions(state:&state,only:job.id);return}
        guard file.standardizedFileURL.path.hasPrefix(workDirectory(job.id).standardizedFileURL.path+"/") else{
            throw InputError.invalid("下载产物不属于此任务的工作目录。")
        }
        let folder=URL(fileURLWithPath:job.folder,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var observedJob=job;observedJob.playback=playback
        let receipt=CompletionReceipt(job:observedJob,source:file,target:try FileNames.available(name,in:folder),identity:try .read(file))
        try write(receipt)
        try settle(receipt,state:&state)
    }
    func recoverCompletions(state:inout AppState,only id:UUID?=nil)throws -> [String] {
        try requireWritable()
        var warnings:[String]=[]
        guard FileManager.default.fileExists(atPath:receipts.path) else{return []}
        let files=try FileManager.default.contentsOfDirectory(at:receipts,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json" && (id==nil || $0.lastPathComponent==id!.uuidString+".json")}.sorted{$0.path<$1.path}
        for file in files {
            let receipt=try JSONDecoder().decode(CompletionReceipt.self,from:Data(contentsOf:file))
            guard file.lastPathComponent==receipt.job.id.uuidString+".json",
                  receipt.source.standardizedFileURL.path.hasPrefix(workDirectory(receipt.job.id).standardizedFileURL.path+"/"),
                  receipt.target.deletingLastPathComponent().standardizedFileURL==URL(fileURLWithPath:receipt.job.folder,isDirectory:true).standardizedFileURL else{
                throw InputError.invalid("完成恢复记录不匹配，已保留：\(file.path)")
            }
            do {try settle(receipt,state:&state)}catch let error as CleanupFailure{warnings.append(error.localizedDescription)}
        }
        return warnings
    }
    private func settle(_ pending:CompletionReceipt,state:inout AppState)throws {
        if pending.stateCommitted==true || state.completionCleanup?.contains(pending.job.id)==true {try cleanup(pending,state:&state);return}
        var receipt=pending
        if FileManager.default.fileExists(atPath:receipt.source.path) {
            guard try FileIdentity.read(receipt.source)==receipt.identity else{throw InputError.invalid("原始产物身份已改变，未移动文件。")}
            // Move refuses an existing destination, including a new foreign collision.
            try FileManager.default.moveItem(at:receipt.source,to:receipt.target)
            // Cross-volume moves may change identity. Save the placed identity
            // before touching history. An interruption before this write remains
            // explicitly unresolved on recovery; no foreign file is adopted.
            receipt.identity=try .read(receipt.target)
            try write(receipt)
        } else {
            guard try FileIdentity.read(receipt.target)==receipt.identity else{
                throw InputError.invalid("无法确认已保存产物的身份；恢复记录和文件均已保留：\(receipt.target.path)")
            }
        }
        var committed=state
        var job=receipt.job
        job.status = .completed;job.progress=1;job.outputPath=receipt.target.path;job.title=receipt.target.lastPathComponent
        job.fileSize=(try receipt.target.resourceValues(forKeys:[.fileSizeKey]).fileSize).map(Int64.init)
        job.completedAt=committed.history.first(where:{$0.id==job.id})?.completedAt ?? job.completedAt ?? Date()
        job.detail=""
        if let index=committed.jobs.firstIndex(where:{$0.id==job.id}){committed.jobs[index]=job}else{committed.jobs.insert(job,at:0)}
        committed.history.removeAll{$0.id==job.id};committed.history.insert(job,at:0)
        if committed.completionCleanup==nil{committed.completionCleanup=[]}
        if !committed.completionCleanup!.contains(job.id){committed.completionCleanup!.append(job.id)}
        try save(committed)
        state=committed
        try cleanup(receipt,state:&state)
    }
    private func cleanup(_ receipt:CompletionReceipt,state:inout AppState)throws {
        // Cleanup failures retain their receipt so the next recovery can retry.
        do {
            // Persist the cleanup-only phase before removing the state marker.
            // A crash after that save must never resurrect deleted history.
            var committed=receipt;committed.stateCommitted=true
            try write(committed)
            let work=workDirectory(receipt.job.id)
            if FileManager.default.fileExists(atPath:work.path){try FileManager.default.removeItem(at:work)}
            var cleaned=state
            cleaned.completionCleanup?.removeAll{$0==receipt.job.id}
            try save(cleaned)
            state=cleaned
            try FileManager.default.removeItem(at:receiptPath(receipt.job.id))
        }catch{throw CleanupFailure(reason:error.localizedDescription)}
    }
}
