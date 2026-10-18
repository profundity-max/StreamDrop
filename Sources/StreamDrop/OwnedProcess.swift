import Foundation
import Darwin

/// Owns one newly spawned process group. The leader remains unreaped until group
/// cleanup, so its PID/group identity cannot be reused during cancellation.
final class OwnedProcess {
    private let lock=NSLock()
    private var leader:pid_t?
    private var status:Int32=0
    private var onData:(Data)->Void
    private var onExit:(Int32)->Void
    init(onData:@escaping(Data)->Void,onExit:@escaping(Int32)->Void){self.onData=onData;self.onExit=onExit}
    var isRunning:Bool {lock.lock();defer{lock.unlock()};return leader != nil}
    func start(executable:String,arguments:[String],environment:[String:String]) throws {
        var descriptors:[Int32]=[0,0]
        guard Darwin.pipe(&descriptors)==0 else{throw POSIXError(.EMFILE)}
        let readFD=descriptors[0],writeFD=descriptors[1]
        _=fcntl(readFD,F_SETFD,FD_CLOEXEC);_=fcntl(writeFD,F_SETFD,FD_CLOEXEC)
        var actions:posix_spawn_file_actions_t?
        var attributes:posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions);posix_spawnattr_init(&attributes)
        defer{posix_spawn_file_actions_destroy(&actions);posix_spawnattr_destroy(&attributes)}
        posix_spawn_file_actions_adddup2(&actions,writeFD,STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions,writeFD,STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions,readFD)
        posix_spawn_file_actions_addclose(&actions,writeFD)
        posix_spawnattr_setflags(&attributes,Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes,0)
        let argv=([executable]+arguments).map{strdup($0)}+[nil]
        let envp=environment.map{strdup("\($0.key)=\($0.value)")}+[nil]
        defer{for p in argv {if let p{free(p)}};for p in envp {if let p{free(p)}}}
        var pid:pid_t=0
        let code=argv.withUnsafeBufferPointer{args in envp.withUnsafeBufferPointer{env in
            posix_spawn(&pid,executable,&actions,&attributes,args.baseAddress!,env.baseAddress!)
        }}
        Darwin.close(writeFD)
        guard code==0 else{Darwin.close(readFD);throw POSIXError(POSIXErrorCode(rawValue:code) ?? .EIO)}
        lock.lock();leader=pid;lock.unlock()
        let group=DispatchGroup()
        group.enter()
        DispatchQueue.global(qos:.utility).async{[self] in
            let handle=FileHandle(fileDescriptor:readFD,closeOnDealloc:true)
            while true {let data=handle.availableData;if data.isEmpty{break};onData(data)}
            try? handle.close();group.leave()
        }
        group.enter()
        DispatchQueue.global(qos:.utility).async{[self] in
            var info=siginfo_t()
            var result:Int32
            repeat {result=waitid(P_PID,id_t(pid),&info,WEXITED|WNOWAIT)} while result == -1 && errno == EINTR
            lock.lock()
            // Do not reap until signals to the owned group are finished.
            if leader==pid {
                _=Darwin.kill(-pid,SIGKILL)
                var exitStatus:Int32=0
                var reaped:pid_t
                repeat {reaped=waitpid(pid,&exitStatus,0)} while reaped == -1 && errno == EINTR
                status=reaped==pid ? exitStatus : -1
                leader=nil
            }
            lock.unlock();group.leave()
        }
        group.notify(queue:.global(qos:.utility)){[self] in onExit(status)}
    }
    func stop(){
        lock.lock();let pid=leader;if let pid{_=Darwin.kill(-pid,SIGINT)};lock.unlock()
        guard let pid else{return}
        for (delay,signal) in [(2.0,SIGTERM),(4.0,SIGKILL)] {
            DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+delay){[self] in
                lock.lock();defer{lock.unlock()};guard leader==pid else{return};_=Darwin.kill(-pid,signal)
            }
        }
    }
}
