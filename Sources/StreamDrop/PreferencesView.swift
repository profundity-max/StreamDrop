import SwiftUI
import AppKit

struct PreferencesView:View {
    @ObservedObject var queue:DownloadQueue
    @State private var section="通用"
    private let sections:[(String,String,Color)]=[("通用","gearshape.fill",.blue),("下载目录","externaldrive.fill",.orange),("后期处理","slider.horizontal.3",.red),("外部工具","wrench.and.screwdriver.fill",.purple),("隐私与数据","hand.raised.fill",.teal),("关于","info.circle.fill",.gray)]
    var body:some View {
        HStack(spacing:0) {
            VStack(spacing:6){ForEach(sections,id:\.0){item in Button{section=item.0}label:{HStack(spacing:10){Image(systemName:item.1).font(.system(size:18)).foregroundStyle(.white).frame(width:32,height:32).background(item.2,in:RoundedRectangle(cornerRadius:7));Text(item.0).font(.system(size:13,weight:.semibold));Spacer()}.padding(10).frame(maxWidth:.infinity).background(section==item.0 ? accent : .clear,in:RoundedRectangle(cornerRadius:9)).foregroundStyle(section==item.0 ? Color.white : Color.primary)}.buttonStyle(.plain)};Spacer()}.padding(12).frame(width:195).background(canvas)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text(section).font(.title2.bold())
                    if section=="通用" {general}
                    else if section=="下载目录" {folders}
                    else if section=="后期处理" {postprocessing}
                    else if section=="外部工具" {tools}
                    else if section=="隐私与数据" {privacy}
                    else {about}
                    Spacer(minLength:0)
                }.padding(26).frame(maxWidth:.infinity,alignment:.leading)
            }.background(Color(nsColor:.controlBackgroundColor))
        }.frame(width:820,height:520).tint(accent)
    }
    var general:some View {VStack(alignment:.leading,spacing:14){
        Text("队列行为").font(.headline)
        Toggle("自动开始下载",isOn:$queue.preferences.autoStart)
        Stepper("最大同时下载任务数：\(queue.preferences.concurrency)",value:$queue.preferences.concurrency,in:1...6)
        Text("关闭自动开始后，新任务以暂停状态加入队列。重新打开 App 时，上次未完成的任务也会暂停。 ").font(.caption).foregroundStyle(.secondary)
        Divider().padding(.vertical,8)
        Text("有多种画质可选择时").font(.headline)
        Picker("默认画质",selection:$queue.preferences.quality){QualityOptions()}.frame(maxWidth:360)
        Toggle("优先 MP4 与系统播放兼容性",isOn:$queue.preferences.preferMP4)
        Text("同画质优先 H.264/AAC；系统无法解码视频时使用 FFmpeg 转换，可能增加处理时间。画质选择作用于网页视频。若最高画质不可用，解析工具会尝试网站提供的兼容格式。文件直链保持原文件。 ").font(.caption).foregroundStyle(.secondary)
    }}
    var folders:some View {VStack(alignment:.leading,spacing:14){
        Label("下载完成后保存到",systemImage:"folder").font(.headline)
        Text(queue.preferences.folder).font(.system(.body,design:.monospaced)).textSelection(.enabled).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(canvas,in:RoundedRectangle(cornerRadius:8))
        HStack{Button("选择目录…"){let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.canCreateDirectories=true;panel.directoryURL=URL(fileURLWithPath:queue.preferences.folder);if panel.runModal() == .OK,let url=panel.url {queue.preferences.folder=url.path}};Button("在 Finder 中打开"){NSWorkspace.shared.open(URL(fileURLWithPath:queue.preferences.folder))}}
        Text("修改目录仅影响新任务。文件重名时自动添加编号；不覆盖已有文件。移除队列或历史记录不会删除下载文件。 ").font(.caption).foregroundStyle(.secondary)
    }}
    var postprocessing:some View {VStack(alignment:.leading,spacing:14){
        Label("视频与音频",systemImage:"waveform").font(.headline)
        Text("添加链接时可选择「原始视频 / 文件」或「提取音频 · M4A」。音频提取和分离音视频合并需要 FFmpeg。网页解析使用 yt-dlp。 ")
        Divider()
        Label("格式与兼容性",systemImage:"play.rectangle").font(.headline)
        Text("直链始终保存原始文件。网页视频优先保留可用格式；是否可下载、是否提供音轨以及画质上限取决于来源网站。")
        Text("本版本没有 Permute 集成、字幕批量管理或原版站点专有解析器。 ").font(.caption).foregroundStyle(.secondary)
    }}
    var tools:some View {VStack(alignment:.leading,spacing:16){
        Text("网页视频解析").font(.headline)
        toolField("yt-dlp",path:$queue.preferences.ytDLP)
        Text("视频合并与音频转换").font(.headline)
        toolField("ffmpeg",path:$queue.preferences.ffmpeg)
        Text("留空时检测 /opt/homebrew/bin、/usr/local/bin 和 /usr/bin。本应用只使用你已安装的工具，不会自动安装或更新软件。工具输出错误会显示在下载卡片中。 ").font(.caption).foregroundStyle(.secondary)
    }}
    func toolField(_ name:String,path:Binding<String>)->some View {VStack(alignment:.leading,spacing:8){HStack{TextField("自动检测 \(name)",text:path).textFieldStyle(.roundedBorder);Button("选择…"){let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.canChooseFiles=true;panel.showsHiddenFiles=true;if panel.runModal() == .OK,let url=panel.url{path.wrappedValue=url.path}}};if let resolved=ToolPaths.find(path.wrappedValue,name:name){Label(resolved,systemImage:"checkmark.circle.fill").foregroundStyle(.green).font(.caption).textSelection(.enabled)}else{Label("未找到 \(name)",systemImage:"exclamationmark.circle").foregroundStyle(.orange).font(.caption)}}}
    var privacy:some View {VStack(alignment:.leading,spacing:14){
        Label("保存在本机",systemImage:"internaldrive").font(.headline)
        Text("队列、历史记录、原始链接和设置保存在以下目录。部分下载文件与续传数据位于 Transfers 子目录。链接参数会按原样保留，请留意分享记录时可能包含的个人信息。 ")
        Text(queue.store.root.path).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
        Button("显示数据目录"){NSWorkspace.shared.open(queue.store.root)}
        Divider()
        Text("不访问 Downie 的用户数据，不上传分析或下载记录。下载会连接你添加的网站；yt-dlp 可能连接媒体 CDN。引导提取浏览器使用临时网站数据，不导入其他浏览器 Cookie。 ").font(.caption).foregroundStyle(.secondary)
    }}
    var about:some View {VStack(alignment:.leading,spacing:14){Image(systemName:"square.and.arrow.down.fill").font(.system(size:48)).foregroundStyle(accent);Text("StreamDrop 1.0.3").font(.title2.bold());Text("基于可观察界面与行为，使用原创 Swift 代码实现的独立 macOS 下载工具。与 Downie 及其开发者没有关联。 ");Text("界面：SwiftUI / AppKit\n直链：URLSession\n公共网页：本机 yt-dlp\n合并与音频：本机 FFmpeg\n素材：SF Symbols 与原创图标").font(.caption).foregroundStyle(.secondary)}}
}
