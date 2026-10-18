# Downie 4 → StreamDrop：证据与重建范围

目标：独立实现可运行的 macOS 下载应用，保留可观察的布局与主要操作，使用原创代码、SF Symbols 和系统字体。不是原版，也不复制其二进制、商标或素材。日期：2026-10-18。

## 已确认

| 层面 | 事实 | 来源 |
|---|---|---|
| 身份 | 4.13.3 / 5273，最低 macOS 13，原生 universal Mach-O | initial-evidence.json：inspect_plist `ev_c4f1a632dcc8898e41a1c956d2383265a6490e2fcc11e21c3f336ccef2e2a2f4` |
| 技术栈 | Cocoa/AppKit、WebKit、AVFoundation、Swift 运行库，DownieCore/DownmuteCore/XUCore 等自有框架 | initial-evidence.json：inspect_macho `ev_0eeb632509971fa7ed664add17f83ae202e891764efc3243afe087a190d3b81d` |
| 主窗口 | 856×360 points，浅灰背景、中央投放标志，底部加号/提取/搜索/清理/历史/帮助工具栏 | reference/original-main.png，CUA 运行时观察 |
| 添加 | 文件菜单打开链接；多条 URL 用空格或换行分隔；支持文本导入、剪贴板和拖放 | original-add.png；REA AX `ev_de9fa3722ee3d77cb8f5fb20c547b9edf096d4a438c9362d87af9723ae9b4b6e` |
| 历史 | 独立窗口，搜索、行为菜单、空状态 | original-history.png，CUA 观察 |
| 设置 | 分类侧栏；自动开始、并发数、画质、MP4 偏好、下载目录、后处理、字幕等 | original-settings.png，CUA 观察；未改变原版设置 |
| 存储模型 | Core Data 模型 XUCompletedDownload；title/date/firstFileURL/originalWebSiteURL/String/refererURL/previewImageData/width/height | rea-evidence.json：keyed archive `ev_66be5fe91756c753f3e0750e3126fd98b4f6d1829a162fd93acd32d32c575114`、`ev_99fca01f2ab36433fc3fcfc505efa333dd11f3e60daac140a6935393bbfd1b0e` |
| 资源 | 内含 ffmpeg、Safari 扩展、JS bridge；扩展 JS 向 native message 传 URL/cookies/postprocessing | 只读 DMG 文件检查（前一轮） |

## 推断与未知

Core Data 用于历史记录的推断有模型支持，但未读取用户数据库，不能声称实际 store 路径、SQLite 模式或同步策略。`.downiepart` 是声明的部分下载类型，内部格式未知。原版站点解析、重试、断点续传、质量合并与 Cookie 注入实现未反编译；不声称 yt-dlp 与其等价。未观察原版下载过程或每一设置页。REA 屏幕截图被系统权限拒绝；截图改由已可用的 CUA 捕获，REA 无障碍捕获成功。NIB 图解码达到文档数上限，部分主程序 NIB 未覆盖；未以文件名推断实际行为。

## 页面与流程（实现设计）

1. 下载主窗口：拖入或粘贴 URL → 打开链接 sheet → 选择自动/直链/网页、视频/音频及画质 → 队列 → 真实进度/失败 → 暂停、继续、取消、重试 → 打开文件或 Finder 显示。
2. 历史窗口：完成后保留记录；搜索、再次下载、打开/显示文件、移除记录（不删除文件）。
3. 设置窗口：通用并发/自动开始/画质；保存目录；外部工具路径及可用性；本地数据说明。
4. 用户引导提取：独立 WKWebView 输入网页地址，收集媒体元素与链接候选，选择后加入队列。只做无登录公共页面候选探测；与原版网络拦截、私有解析器不同。

## 方案选择

采用 SwiftUI + 少量 AppKit（窗口、菜单、文件面板）+ URLSession + WebKit。接近原版原生栈，系统控件支持深浅色、键盘和辅助功能；无需 Electron。纯 AppKit 的细节控制更强但首版开发量大；Electron 会引入额外运行时与较大包体，不选。

HTTP(S) 文件直链无需额外工具。公共网页和 HLS/DASH 交由已安装且可配置的 yt-dlp；合并/音频转换使用已安装 FFmpeg。不会复制原版 FFmpeg，不安装/升级任何软件。实际站点成功率取决于站点和本机工具，受保护媒体不在支持范围。

独立数据位置：~/Library/Application Support/StreamDrop/state.json，原子写入、版本号、损坏文件保留并报告；队列/历史/设置；部分文件及 resumeData 放在独立 UUID 工作目录。恢复后正在运行任务变为暂停，不自动重放网络请求。完成文件放用户选择目录，绝不覆盖同名文件。错误与取消不得产生成功历史。

## 验收

构建独立 .app 并 ad-hoc 签名；本机可复制到 Applications 运行。可安装表示完整 app bundle，未做 Developer ID 公证或跨机器 Gatekeeper 分发。真实 loopback HTTP 测试：下载字节校验、失败、并发、暂停继续/取消重试、持久化与文件重名。测试网页解析与 HLS 在本地 fixture 完成；公共站点不作泛化成功承诺。原版与重建截图比较主窗口/添加/历史/设置。没有原版素材进入最终 app。
