import SwiftUI
import AppKit

extension Notification.Name { static let addLinks=Notification.Name("StreamDrop.AddLinks"); static let pasteLinks=Notification.Name("StreamDrop.PasteLinks") }
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    weak var queue:DownloadQueue?
    private var terminationTimer:Timer?
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard let queue,queue.jobs.contains(where:{$0.status.active}) else{return .terminateNow}
        queue.shutdown()
        let deadline=Date().addingTimeInterval(8)
        terminationTimer=Timer.scheduledTimer(withTimeInterval:0.05,repeats:true){[weak self] timer in
            Task { @MainActor in
            if !queue.jobs.contains(where:{$0.status.active}) || Date()>deadline {
                queue.persist();timer.invalidate();self?.terminationTimer=nil;sender.reply(toApplicationShouldTerminate:true)
            }
            }
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
}
@main struct StreamDropApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var queue=DownloadQueue()
    var body:some Scene {
        Window("StreamDrop",id:"main") {
            MainView(queue:queue).onAppear{delegate.queue=queue}
        }.defaultSize(width:856,height:360).windowStyle(.hiddenTitleBar)
         .commands {DownloadCommands(queue:queue)}
        Window("历史记录",id:"history") {HistoryView(queue:queue)}.defaultSize(width:756,height:450)
        Window("设置",id:"settings") {PreferencesView(queue:queue)}.defaultSize(width:820,height:560).windowResizability(.contentSize)
        Window("用户引导提取",id:"browser") {GuidedBrowser(queue:queue)}.defaultSize(width:1000,height:700)
    }
}
struct DownloadCommands:Commands {
    @ObservedObject var queue:DownloadQueue
    @Environment(\.openWindow) var openWindow
    var body:some Commands {
        CommandGroup(replacing:.newItem) {
            Button("打开链接…"){NotificationCenter.default.post(name:.addLinks,object:nil);openWindow(id:"main")}.keyboardShortcut("l",modifiers:.command)
            Button("从粘贴板添加…"){NotificationCenter.default.post(name:.pasteLinks,object:nil);openWindow(id:"main")}.keyboardShortcut("v",modifiers:[.command,.shift])
            Button("显示下载窗口"){openWindow(id:"main")}.keyboardShortcut("0",modifiers:.command)
        }
        CommandGroup(replacing:.appSettings) {Button("设置…"){openWindow(id:"settings")}.keyboardShortcut(",",modifiers:.command)}
        CommandMenu("下载") {
            Button("开始 / 重试全部下载"){queue.resumeAll()}
            Button("暂停全部下载"){queue.pauseAll()}
            Divider()
            Button("清空已完成的下载"){queue.clearCompleted()}
            Button("历史记录"){openWindow(id:"history")}.keyboardShortcut("y",modifiers:.command)
            Button("用户引导提取…"){openWindow(id:"browser")}
        }
        CommandGroup(replacing:.help) {Button("StreamDrop 使用说明"){NSWorkspace.shared.open(Bundle.main.resourceURL!.appendingPathComponent("README.md"))}}
    }
}
