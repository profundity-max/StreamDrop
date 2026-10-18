import Foundation

/// One execution owns user intent and delivers one terminal result. Adapters
/// settle only after their resources are drained; callers never interpret
/// adapter-specific callbacks. MainActor serializes commands and delivery.
@MainActor final class TransferRun {
    private enum Stop {case pause,cancel}
    private var stop:Stop?
    private var settled=false
    private var adapter:Transfer!
    private let emit:(TransferEvent)->Void
    init(job:DownloadJob,preferences:Preferences,work:URL,emit:@escaping(TransferEvent)->Void) {
        self.emit=emit
        let callback:(TransferEvent)->Void={ [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        adapter=job.useDirect ? DirectTransfer(job:job,work:work,emit:callback) : WebTransfer(job:job,preferences:preferences,work:work,emit:callback)
    }
    func start(){adapter.start()}
    func pause(){guard !settled,stop==nil else{return};stop = .pause;adapter.pause()}
    func cancel(){guard !settled else{return};stop = .cancel;adapter.cancel()}
    private func receive(_ event:TransferEvent){
        guard !settled else{return}
        if case .progress=event {if stop==nil{emit(event)};return}
        settled=true
        switch stop {
        case .cancel:emit(.cancelled)
        case .pause:
            if case .paused=event {emit(event)}else{emit(.paused(nil))}
        case nil:emit(event)
        }
    }
}
