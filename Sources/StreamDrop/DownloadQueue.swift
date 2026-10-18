import Foundation
import Combine

@MainActor final class DownloadQueue: ObservableObject {
    @Published private(set) var jobs:[DownloadJob]=[]
    @Published private(set) var history:[DownloadJob]=[]
    @Published var preferences=Preferences() {didSet{persist();schedule()}}
    @Published var error:String?
    let store:StateStore
    private var transfers:[UUID:TransferRun]=[:]
    private var tokens:[UUID:UUID]=[:]
    private var completionCleanup:[UUID]?
    private var loading=true
    private var storageBlocked=false
    private var progressSave=Date.distantPast
    init(store:StateStore=StateStore()) {
        self.store=store
        do {let loaded=try store.loadWithRecovery();let state=loaded.state;jobs=state.jobs;history=state.history;preferences=state.preferences;completionCleanup=state.completionCleanup;if !loaded.warnings.isEmpty{error=loaded.warnings.joined(separator:"\n")}}
        catch {self.error="无法读取状态文件。为保留原数据，本次不保存更改。\n\(error.localizedDescription)";storageBlocked=true}
        loading=false
    }
    func add(_ text:String,kind:SourceKind = .automatic,mode:MediaMode = .video,quality:String?=nil) throws {
        let urls=try LinkInput.parse(text)
        var additions=urls.map{ DownloadJob(url:$0,kind:kind,mode:mode,quality:quality ?? preferences.quality,folder:preferences.folder) }
        if !preferences.autoStart {for i in additions.indices {additions[i].status = .paused}}
        jobs.insert(contentsOf:additions,at:0);persist();schedule()
    }
    func persist() {
        guard !loading,!storageBlocked else{return}
        do {try store.save(AppState(completionCleanup:completionCleanup,jobs:jobs,history:history,preferences:preferences))}
        catch {self.error="无法保存下载状态：\(error.localizedDescription)"}
    }
    private func schedule() {
        guard !loading else{return}
        let capacity=max(1,min(6,preferences.concurrency))
        while transfers.count<capacity,let job=jobs.first(where:{$0.status == .queued}) {start(job)}
    }
    private func start(_ job:DownloadJob) {
        let work=store.workDirectory(job.id)
        do {try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)}
        catch {update(job.id){$0.status = .failed;$0.detail=error.localizedDescription};return}
        let token=UUID();tokens[job.id]=token
        update(job.id){$0.status=job.useDirect ? .downloading : .resolving;$0.detail=""}
        let callback:(TransferEvent)->Void={ [weak self] event in self?.receive(event,id:job.id,token:token) }
        let transfer=TransferRun(job:job,preferences:preferences,work:work,emit:callback)
        transfers[job.id]=transfer;persist();transfer.start()
    }
    private func receive(_ event:TransferEvent,id:UUID,token:UUID) {
        guard tokens[id]==token,let job=jobs.first(where:{$0.id==id}) else{return}
        switch event {
        case let .progress(progress,received,expected,detail):
            update(id){$0.status = .downloading;$0.progress=max(0,min(1,progress));$0.received=received;$0.expected=expected;$0.detail=detail}
            if Date().timeIntervalSince(progressSave)>2 {persist();progressSave=Date()}
            return
        case let .paused(data):
            let resume=store.workDirectory(id).appendingPathComponent("resume.data")
            if let data {do{try ResumeRecord(data:data,url:job.url).encoded().write(to:resume,options:.atomic)}catch{self.error="断点数据未保存，下次将重新下载：\(error.localizedDescription)"}}
            update(id){$0.status = .paused;$0.detail="已暂停"}
        case .cancelled:
            update(id){$0.status = .cancelled;$0.detail="已取消，可重试。"}
        case let .failed(message):
            update(id){$0.status = .failed;$0.detail=message}
        case let .finished(file,name):
            var state=AppState(completionCleanup:completionCleanup,jobs:jobs,history:history,preferences:preferences)
            do {try store.complete(job:job,file:file,name:name,state:&state)}
            catch {
                self.error="完成保存或清理尚未结束，恢复记录已保留：\(error.localizedDescription)"
                if state.jobs.first(where:{$0.id==id})?.status != .completed {
                    if let index=state.jobs.firstIndex(where:{$0.id==id}){state.jobs[index].status = .failed;state.jobs[index].detail=self.error ?? ""}
                }
            }
            jobs=state.jobs;history=state.history;completionCleanup=state.completionCleanup
        }
        tokens[id]=nil;transfers[id]=nil;persist();schedule()
    }
    private func update(_ id:UUID,_ mutation:(inout DownloadJob)->Void) {
        guard let index=jobs.firstIndex(where:{$0.id==id}) else{return};mutation(&jobs[index])
    }
    func pause(_ id:UUID) {
        guard let job=jobs.first(where:{$0.id==id}) else{return}
        if job.status == .queued {update(id){$0.status = .paused};persist();return}
        guard job.status.active,job.status != .pausing,let transfer=transfers[id] else{return}
        update(id){$0.status = .pausing};persist();transfer.pause()
    }
    func cancel(_ id:UUID) {
        guard let job=jobs.first(where:{$0.id==id}) else{return}
        if let transfer=transfers[id] {
            update(id){$0.status = .pausing};persist();transfer.cancel()
        } else if job.status != .completed {update(id){$0.status = .cancelled;$0.detail="已取消，可重试。"};persist()}
    }
    func resume(_ id:UUID) {
        guard let job=jobs.first(where:{$0.id==id}),[.paused,.failed,.cancelled].contains(job.status),transfers[id]==nil else{return}
        update(id){$0.status = .queued;$0.detail=""};persist();schedule()
    }
    func pauseAll() {for job in jobs where job.status.active || job.status == .queued {pause(job.id)}}
    func resumeAll() {for i in jobs.indices where [.paused,.failed,.cancelled].contains(jobs[i].status) {jobs[i].status = .queued};persist();schedule()}
    func clearCompleted() {jobs.removeAll{$0.status == .completed};persist()}
    func remove(_ id:UUID) {guard transfers[id]==nil else{return};jobs.removeAll{$0.id==id};persist()}
    func removeHistory(_ id:UUID) {history.removeAll{$0.id==id};persist()}
    func clearHistory() {history=[];persist()}
    func shutdown() {pauseAll();persist()}
}
