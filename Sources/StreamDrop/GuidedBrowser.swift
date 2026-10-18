import SwiftUI
import WebKit
import AppKit

@MainActor final class BrowserModel:NSObject,ObservableObject,WKNavigationDelegate {
    let webView:WKWebView
    @Published var address=""
    @Published var candidates:[String]=[]
    @Published var message="输入网页地址，在页面加载后点击「查找媒体」。"
    @Published var loading=false
    override init(){let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent();webView=WKWebView(frame:.zero,configuration:config);super.init();webView.navigationDelegate=self}
    func go(){do{let url=try LinkInput.parse(address);guard url.count==1 else{throw InputError.invalid("请填写一个网页地址。")};candidates=[];message="正在加载…";webView.load(URLRequest(url:url[0]))}catch{message=error.localizedDescription}}
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){let scheme=navigationAction.request.url?.scheme?.lowercased();decisionHandler(scheme=="https" || scheme=="http" || scheme=="about" ? .allow : .cancel)}
    func webView(_ webView:WKWebView,didStartProvisionalNavigation navigation:WKNavigation!){loading=true}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){loading=false;address=webView.url?.absoluteString ?? address;message="页面已加载，可查找公开媒体链接或直接解析当前网页。"}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){loading=false;message=error.localizedDescription}
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error){loading=false;message=error.localizedDescription}
    func scan(){
        let script="""
        (() => {
          const values = [...document.querySelectorAll('video,audio,source')].flatMap(e => [e.currentSrc, e.src]);
          for (const a of document.querySelectorAll('a[href]')) if (/\\.(mp4|mov|m4v|webm|m3u8|mpd|mp3|m4a)(\\?|$)/i.test(a.href)) values.push(a.href);
          return [...new Set(values.filter(v => v && /^https?:/i.test(v)))].slice(0,100);
        })()
        """
        webView.evaluateJavaScript(script){[weak self] value,error in Task{@MainActor in guard let self else{return};self.candidates=value as? [String] ?? [];self.message=error?.localizedDescription ?? (self.candidates.isEmpty ? "未发现公开媒体元素。可尝试「解析当前网页」；跨域框架和 blob 媒体可能不可见。" : "发现 \(self.candidates.count) 个媒体候选。请选择链接下载。")}}
    }
}
struct BrowserSurface:NSViewRepresentable {
    let model:BrowserModel
    func makeNSView(context:Context)->WKWebView{model.webView}
    func updateNSView(_ view:WKWebView,context:Context){}
}
struct GuidedBrowser:View {
    @ObservedObject var queue:DownloadQueue
    @StateObject private var model=BrowserModel()
    @State private var draft:LinkDraft?
    var body:some View {
        VStack(spacing:0){
            HStack{Button{model.webView.goBack()}label:{Image(systemName:"chevron.left")}.help("后退");TextField("https://…",text:$model.address).textFieldStyle(.roundedBorder).onSubmit{model.go()}.accessibilityLabel("网页地址");Button("前往"){model.go()}.keyboardShortcut(.return,modifiers:[]);Button("查找媒体"){model.scan()};Button("解析当前网页"){draft=LinkDraft(text:model.webView.url?.absoluteString ?? model.address)}.disabled(model.webView.url==nil)}.padding(12)
            if model.loading {ProgressView().progressViewStyle(.linear)}
            HSplitView{BrowserSurface(model:model).frame(minWidth:480);VStack(alignment:.leading,spacing:10){Text("媒体链接").font(.headline);Text(model.message).font(.caption).foregroundStyle(.secondary);Divider();ScrollView{LazyVStack(alignment:.leading,spacing:12){ForEach(model.candidates,id:\.self){link in VStack(alignment:.leading,spacing:6){Text(link).font(.system(size:11)).lineLimit(3).textSelection(.enabled);Button("添加下载"){draft=LinkDraft(text:link)}}.padding(10).background(canvas,in:RoundedRectangle(cornerRadius:8))}}};Spacer();Text("此浏览器使用临时网站数据。仅检测当前页面的公开媒体元素；不保证解析所有站点。 ").font(.caption2).foregroundStyle(.secondary)}.padding(14).frame(minWidth:240,idealWidth:280,maxWidth:360)}
        }.frame(minWidth:850,minHeight:550).tint(accent).sheet(item:$draft){draft in AddLinksView(queue:queue,initial:draft.text)}
    }
}
