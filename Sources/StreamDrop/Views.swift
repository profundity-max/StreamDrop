import SwiftUI
import AppKit
import UniformTypeIdentifiers

let accent=Color(red:0.66,green:0.45,blue:0.88)
let canvas=Color(nsColor:NSColor(name:nil,dynamicProvider:{ appearance in
    appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(calibratedWhite:0.13,alpha:1) : NSColor(calibratedRed:0.913,green:0.918,blue:0.927,alpha:1)
}))
struct LinkDraft:Identifiable {let id=UUID();let text:String}
func byteString(_ value:Int64)->String {ByteCountFormatter.string(fromByteCount:max(0,value),countStyle:.file)}
@MainActor func reveal(_ job:DownloadJob) {if let path=job.outputPath {NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:path)])}}
@MainActor func openFile(_ job:DownloadJob) {if let path=job.outputPath {NSWorkspace.shared.open(URL(fileURLWithPath:path))}}

struct RoundTool:View {
    let symbol:String;let title:String;var action:()->Void
    var body:some View {
        Button(action:action){Image(systemName:symbol).font(.system(size:18,weight:.regular)).frame(width:26,height:28)}
            .buttonStyle(.plain).foregroundStyle(accent).help(title).accessibilityLabel(title)
    }
}
struct MainView:View {
    @ObservedObject var queue:DownloadQueue
    @Environment(\.openWindow) var openWindow
    @State private var draft:LinkDraft?
    @State private var searching=false
    @State private var search=""
    @State private var targeted=false
    @State private var showHelp=false
    var filtered:[DownloadJob] {queue.jobs.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.url.absoluteString.localizedCaseInsensitiveContains(search)}}
    var summary:String {
        if queue.jobs.isEmpty {return "没有下载"}
        let active=queue.jobs.filter{$0.status.active}.count
        return active>0 ? "\(active) 个正在下载 · 共 \(queue.jobs.count) 项" : "\(queue.jobs.count) 个下载 · \(queue.jobs.filter{$0.status == .completed}.count) 个已完成"
    }
    var body:some View {
        VStack(spacing:0) {
            HStack {Text("StreamDrop").font(.system(size:14,weight:.semibold)).foregroundStyle(.secondary);Spacer()
                if !queue.jobs.isEmpty {Button {queue.pauseAll()} label:{Image(systemName:"pause.fill")}.buttonStyle(.plain).help("暂停全部");Button {queue.resumeAll()} label:{Image(systemName:"play.fill")}.buttonStyle(.plain).help("开始全部")}
            }.padding(.leading,80).padding(.trailing,20).frame(height:36)
            if searching {HStack{Image(systemName:"magnifyingglass");TextField("搜索下载",text:$search).textFieldStyle(.plain);Button{search="";searching=false}label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain)}.padding(9).background(.background,in:RoundedRectangle(cornerRadius:9)).padding(.horizontal,16).padding(.bottom,8)}
            ZStack {
                if queue.jobs.isEmpty {
                    VStack(spacing:16) {
                        Image(systemName:"square.and.arrow.down.fill").font(.system(size:100,weight:.regular)).foregroundStyle(Color.gray.opacity(0.7))
                        Text(targeted ? "松开以添加链接" : "拖入链接，开始下载").font(.system(size:14)).foregroundStyle(.secondary)
                        Text("或按 ⌘L 打开链接 · ⌘⇧V 从粘贴板添加").font(.system(size:11)).foregroundStyle(.tertiary)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle()).onTapGesture(count:2){draft=LinkDraft(text:"")}
                } else if filtered.isEmpty {Text("没有匹配的下载").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)}
                else {ScrollView{LazyVStack(spacing:10){ForEach(filtered){job in DownloadRow(queue:queue,job:job)}}.padding(.horizontal,16).padding(.vertical,12)}}
            }.overlay{if targeted {RoundedRectangle(cornerRadius:14).stroke(accent,style:StrokeStyle(lineWidth:2,dash:[8])).padding(10)}}
            HStack(spacing:8) {
                RoundTool(symbol:"plus",title:"打开链接"){draft=LinkDraft(text:"")}
                RoundTool(symbol:"safari",title:"打开用户引导提取"){openWindow(id:"browser")}
                Spacer()
                Text(summary).font(.system(size:11)).lineLimit(1)
                Spacer()
                RoundTool(symbol:"magnifyingglass",title:"搜索下载"){searching.toggle();if !searching {search=""}}
                RoundTool(symbol:"xmark.circle",title:"清空已完成的下载"){queue.clearCompleted()}
                RoundTool(symbol:"clock",title:"显示历史记录"){openWindow(id:"history")}
                RoundTool(symbol:"gearshape",title:"设置"){openWindow(id:"settings")}
                RoundTool(symbol:"questionmark.circle",title:"使用说明"){showHelp=true}
            }.padding(.horizontal,10).padding(.vertical,2).background(Color(nsColor:.controlBackgroundColor).opacity(0.75),in:Capsule()).padding(.horizontal,10).padding(.bottom,10)
        }.background(canvas).ignoresSafeArea(.container,edges:.top).tint(accent).frame(minWidth:640,minHeight:360)
         .sheet(item:$draft){draft in AddLinksView(queue:queue,initial:draft.text)}
         .onReceive(NotificationCenter.default.publisher(for:.addLinks)){_ in draft=LinkDraft(text:"")}
         .onReceive(NotificationCenter.default.publisher(for:.pasteLinks)){_ in paste()}
         .onDrop(of:[UTType.url.identifier,UTType.text.identifier],isTargeted:$targeted){providers in
             guard !providers.isEmpty else{return false}
             for provider in providers {
                 let type=provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.text.identifier
                 provider.loadItem(forTypeIdentifier:type,options:nil){item,_ in
                     let value:String?
                     if let url=item as? URL {value=url.absoluteString}
                     else if let data=item as? Data {value=String(data:data,encoding:.utf8)}
                     else {value=item as? String}
                     if let value {Task{@MainActor in draft=LinkDraft(text:value)}}
                 }
             };return true
         }
         .alert("StreamDrop",isPresented:Binding(get:{queue.error != nil},set:{if !$0{queue.error=nil}})){Button("好"){queue.error=nil}}message:{Text(queue.error ?? "")}
         .alert("使用说明",isPresented:$showHelp){Button("好",role:.cancel){}}message:{Text("粘贴、拖入或用 ⌘L 添加 HTTP(S) 链接。直链无需额外工具；网页视频使用设置中检测到的 yt-dlp。\n\n下载卡片支持暂停、继续、取消和重试。已完成的文件可在 Finder 中显示。历史记录及设置仅保存在本机。")}
    }
    private func paste(){draft=LinkDraft(text:NSPasteboard.general.string(forType:.string) ?? "")}
}

struct DownloadRow:View {
    @ObservedObject var queue:DownloadQueue
    var job:DownloadJob
    @State private var showingDiagnostics=false
    private var displayDetail:String {job.status == .failed ? DownloadDiagnostics.summary(job.detail) : job.detail}
    var color:Color {job.status == .failed ? .red : job.status == .completed ? .green : accent}
    var body:some View {
        HStack(spacing:14) {
            ZStack{RoundedRectangle(cornerRadius:10).fill(color.opacity(0.1));Image(systemName:job.mode == .audio ? "waveform" : job.status == .completed ? "checkmark.circle" : "play.rectangle").font(.system(size:28,weight:.light)).foregroundStyle(color)}.frame(width:74,height:66)
            VStack(alignment:.leading,spacing:5) {
                HStack {Text(job.title).font(.system(size:13,weight:.semibold)).lineLimit(1);Spacer();Text(job.status.label).font(.system(size:10)).foregroundStyle(color)}
                Text(job.url.host ?? job.url.absoluteString).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                if job.status.active || job.status == .paused {ProgressView(value:job.progress).tint(accent).scaleEffect(y:0.75)}
                HStack {
                    if job.status == .completed {
                        if let size=job.fileSize {Text(byteString(size))}
                    } else if job.received>0 {Text(byteString(job.received)+(job.expected>0 ? " / "+byteString(job.expected):""))}
                    if job.status == .completed {Text(job.playback?.label ?? "无画面验证记录").help(job.playback?.detail ?? "旧记录没有保存兼容性观察。") }
                    if !job.detail.isEmpty {Text(displayDetail).lineLimit(2).help(job.detail)}
                }.font(.system(size:10)).foregroundStyle(job.status == .failed ? Color.red : Color.secondary)
            }
            HStack(spacing:10) {
                if job.status == .failed {Button{showingDiagnostics=true}label:{Image(systemName:"info.circle")}.help("查看错误详情").accessibilityLabel("查看错误详情")}
                if job.status == .completed {
                    Button{openFile(job)}label:{Image(systemName:"play.circle")}.help("打开文件")
                    Button{reveal(job)}label:{Image(systemName:"folder")}.help("在 Finder 中显示")
                } else if job.status.active || job.status == .queued {
                    Button{queue.pause(job.id)}label:{Image(systemName:"pause.circle")}.help("暂停").disabled(job.status == .pausing)
                    Button{queue.cancel(job.id)}label:{Image(systemName:"xmark.circle")}.help("取消").disabled(job.status == .pausing)
                } else {Button{queue.resume(job.id)}label:{Image(systemName:job.status == .paused ? "play.circle" : "arrow.clockwise.circle")}.help(job.status == .paused ? "继续下载" : "重试")}
            }.font(.system(size:18)).buttonStyle(.plain).foregroundStyle(accent)
        }.padding(12).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(.gray.opacity(0.08)))
         .sheet(isPresented:$showingDiagnostics){DownloadErrorView(job:job,work:queue.store.workDirectory(job.id),preferences:queue.preferences)}
         .accessibilityElement(children:.contain).accessibilityLabel("\(job.title)，\(job.status.label)")
         .contextMenu {
             Button("复制原始链接"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(job.url.absoluteString,forType:.string)}
             if job.outputPath != nil {Button("在 Finder 中显示"){reveal(job)}}
             if !job.status.active {Button("从列表移除（保留文件）"){queue.remove(job.id)}}
         }
    }
}

struct AddLinksView:View {
    @ObservedObject var queue:DownloadQueue
    @Environment(\.dismiss) var dismiss
    @State private var links:String
    @State private var kind=SourceKind.automatic
    @State private var mode=MediaMode.video
    @State private var quality:String
    @State private var error=""
    init(queue:DownloadQueue,initial:String="") {self.queue=queue;_links=State(initialValue:initial);_quality=State(initialValue:queue.preferences.quality)}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("填写链接地址，多条链接以空格或回车分隔").font(.system(size:13,weight:.medium))
            HStack(alignment:.top){Text("链接地址：").fontWeight(.semibold).padding(.top,6);TextEditor(text:$links).font(.system(size:13)).frame(height:108).padding(4).background(.background).overlay(RoundedRectangle(cornerRadius:5).stroke(.gray.opacity(0.25))).accessibilityLabel("链接地址")}
            HStack {Picker("来源",selection:$kind){ForEach(SourceKind.allCases,id:\.self){Text($0.title).tag($0)}};Picker("处理",selection:$mode){ForEach(MediaMode.allCases,id:\.self){Text($0.title).tag($0)}}}.font(.system(size:11))
            HStack{Text("画质").foregroundStyle(.secondary);Picker("画质",selection:$quality){QualityOptions()}.labelsHidden().frame(width:160);Spacer();Text("保存至 \((queue.preferences.folder as NSString).lastPathComponent)").foregroundStyle(.secondary)}.font(.system(size:11))
            if !error.isEmpty {Text(error).font(.system(size:11)).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
            HStack {
                Button("从文件导入…"){importFile()}
                Button("粘贴"){links=NSPasteboard.general.string(forType:.string) ?? ""}
                Spacer()
                Button("取消"){dismiss()}.keyboardShortcut(.cancelAction)
                Button("打开"){do{try queue.add(links,kind:kind,mode:mode,quality:quality);dismiss()}catch{self.error=error.localizedDescription}}.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width:530).tint(accent)
    }
    private func importFile(){let panel=NSOpenPanel();panel.allowedContentTypes=[.plainText];panel.allowsMultipleSelection=false;if panel.runModal() == .OK,let url=panel.url {do{links=try String(contentsOf:url,encoding:.utf8)}catch{self.error=error.localizedDescription}}}
}
struct QualityOptions:View {var body:some View {Text("自动选择最佳画质").tag("best");Text("最高 2160p").tag("2160");Text("最高 1080p").tag("1080");Text("最高 720p").tag("720");Text("最高 480p").tag("480")}}

struct HistoryView:View {
    @ObservedObject var queue:DownloadQueue
    @State private var search=""
    @State private var confirm=false
    var items:[DownloadJob]{queue.history.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.url.absoluteString.localizedCaseInsensitiveContains(search)}}
    var body:some View {
        VStack(spacing:0){
            if items.isEmpty {VStack{Spacer();Text(queue.history.isEmpty ? "没有下载" : "没有匹配的记录").font(.system(size:22,weight:.bold)).foregroundStyle(.secondary);Spacer()}.frame(maxWidth:.infinity)}
            else {List(items){job in HStack(spacing:14){Image(systemName:"checkmark.circle.fill").foregroundStyle(.green);VStack(alignment:.leading,spacing:3){Text(job.title).fontWeight(.medium);Text(job.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1);Text(job.playback?.label ?? "无画面验证记录").font(.caption2).foregroundStyle(.secondary).help(job.playback?.detail ?? "旧记录没有保存兼容性观察。");Text(job.completedAt ?? job.created,style:.date).font(.caption2).foregroundStyle(.secondary)};Spacer();Button("显示"){reveal(job)};Button("再下载"){do{try queue.add(job.url.absoluteString,kind:job.kind,mode:job.mode,quality:job.quality)}catch{queue.error=error.localizedDescription}}}.contextMenu{Button("移除记录（保留文件）"){queue.removeHistory(job.id)}}}}
            HStack{Text("\(queue.history.count) 条记录 · 文件保留在原位置").font(.caption).foregroundStyle(.secondary);Spacer()}.padding(10)
        }.background(canvas).searchable(text:$search,prompt:"搜索").toolbar{Menu("行为"){Button("清空历史记录…"){confirm=true}.disabled(queue.history.isEmpty)}}.frame(minWidth:640,minHeight:350)
         .alert("清空历史记录？",isPresented:$confirm){Button("取消",role:.cancel){};Button("清空记录",role:.destructive){queue.clearHistory()}}message:{Text("仅删除本应用的记录，不删除已下载文件。")}
    }
}

struct DownloadErrorView:View {
    let job:DownloadJob
    let work:URL
    let preferences:Preferences
    @State private var report:String?
    @Environment(\.dismiss) var dismiss
    private var logURL:URL {work.appendingPathComponent("yt-dlp.log")}
    private var diagnostic:String {(try? String(contentsOf:logURL,encoding:.utf8)) ?? job.detail}
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            Label("下载失败",systemImage:"exclamationmark.triangle.fill").font(.headline).foregroundStyle(.red)
            Text(DownloadDiagnostics.summary(job.detail)).font(.system(size:13)).textSelection(.enabled)
            Text(job.url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            ScrollView {Text(diagnostic).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(10)}.frame(height:210).background(canvas,in:RoundedRectangle(cornerRadius:8))
            HStack{
                Button(report==nil ? "复制诊断（版本检查中）" : "复制诊断"){
                    let available=report ?? DownloadDiagnostics.report(job:job,diagnostic:diagnostic,tools:[])+"\n工具版本检查尚未结束。"
                    NSPasteboard.general.clearContents();NSPasteboard.general.setString(available,forType:.string)
                }
                Button("显示日志"){NSWorkspace.shared.activateFileViewerSelecting([logURL])}.disabled(!FileManager.default.fileExists(atPath:logURL.path))
                Spacer();Button("关闭"){dismiss()}.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width:600).tint(accent).task{
            async let yt=ToolHealth.shared.check(.ytDLP,configured:preferences.ytDLP)
            async let ff=ToolHealth.shared.check(.ffmpeg,configured:preferences.ffmpeg)
            report=await DownloadDiagnostics.report(job:job,diagnostic:diagnostic,tools:[yt,ff])
        }
    }
}
