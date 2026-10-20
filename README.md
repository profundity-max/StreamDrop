# StreamDrop

独立实现的原生 macOS 下载 App。参考本地 Downie 4.13.3 的可观察布局与交互，使用原创 Swift 代码、原创应用图标及 Apple SF Symbols。与 Downie 无关联，未使用其代码、框架、FFmpeg 副本或图像资源。

## 运行与安装

打开 `output/StreamDrop.app`；或打开 `output/StreamDrop.dmg`，将 StreamDrop 拖至 Applications。macOS 13 或更新版本。应用本身无需 Node、Python 或浏览器运行时。

应用使用本机 ad-hoc 签名，未使用 Developer ID 公证；跨机器分发时 Gatekeeper 可能阻止打开。没有关闭系统安全保护的安装步骤。

## 主要操作

- ⌘L 打开链接；空格或换行分隔多条 HTTP(S) URL；可从 UTF-8 文本导入。
- ⌘⇧V 从粘贴板添加，也可拖入链接。
- 文件直链用系统 URLSession 下载，无外部依赖；自动模式按文件后缀识别，无法识别的直链可手动选「文件直链」。
- 网页视频/HLS/DASH 用本机 **yt-dlp**。音频 M4A、视频音轨合并需要本机 **FFmpeg**。设置 → 外部工具显示检测结果，可以手动选择可执行文件。不会自动安装依赖。
- 默认「优先 MP4 与系统播放兼容性」：同等分辨率优先 H.264/AAC。网页视频下载后尝试原生画面解码，已确定系统无法解码时用 FFmpeg 转为 H.264/AAC，并再次验证画面后完成。转换会增加时间和 CPU 使用；关闭该选项则保留来源编码。无法建立轨道信息的文件不视为已验证兼容。文件直链保持原始字节。
- 添加时选择视频/音频和最高画质；网页支持范围以当前 yt-dlp 为准。受保护/加密媒体及需要登录的来源不保证支持。
- 卡片右侧暂停、继续、取消和重试；HTTP 续传取决于服务器支持，不能续传时重新下载。网页任务保留 yt-dlp 的部分文件以供重试。
- 网页视频文件名保留标题中的中文、空格和原有方括号，不额外追加视频 ID；同名文件自动编号，已有文件保持原名。长标题会在保留扩展名及编号后缩短；非法字符替换为下划线。
- 完成记录保留画面观察：已解码画面、转换后已解码画面、未知、未检查。这里只验证实际画面采样，不保证整片或音轨质量；旧记录不推断验证结果。
- 完成后打开文件或在 Finder 中显示。清空列表或历史不删除下载文件。
- 底部时钟 / ⌘Y 打开历史记录；⌘, 设置保存位置、并发数和画质。
- 指南针打开临时 WebKit 浏览器：加载公开网页 → 查找媒体元素 → 选择候选 → 下载；可直接将当前网页交给 yt-dlp。跨域 iframe、blob URL 可能无法发现，不导入其他浏览器的 Cookie。

## 数据

`~/Library/Application Support/StreamDrop/state.json` 保存队列、历史及设置，使用原子写入。`Transfers/<UUID>` 保存部分下载和恢复数据。`Completions/<UUID>.json` 保留尚未结束的完成提交；文件归属和状态保存确认后才清理，清理失败可在下次启动重试。退出时尝试暂停，重启后中断任务以暂停状态恢复，需手动继续。同名文件添加编号，绝不覆盖。状态损坏时保留原文件，界面报告并禁止本次会话继续覆盖该状态。

不读取 Downie 用户数据，不记录环境变量，不上传分析记录。下载本身会连接用户填写的网站和相关 CDN。原始 URL（包括 query）会保存在本地记录。

## 构建与验证

```sh
./scripts/build.sh
python3 scripts/test.py
```

测试脚本使用已安装的 FFmpeg 合成颜色/音调视频，启动私有 loopback 服务（18764 / 18765），运行 `swift test` 并清理服务及临时媒体；不安装任何软件。测试日志保存在 `.test-output/tests.log`。运行完整集成测试前需要本机已有 FFmpeg；缺少 yt-dlp 时网页测试会跳过。

测试不需要 Downie DMG。构建仅使用 Xcode/Swift SDK 与系统工具。测试工具检测到缺少 yt-dlp 时跳过网页解析测试。更多证据与差异见 `docs/analysis.md`、验证结果见 `docs/verification.md`。

## 实现范围

包含可用的本地下载主流程、队列进度/调度、暂停/继续/取消/重试、历史搜索、独立存储、目录选择、网页解析和基础引导提取。未重建原版浏览器扩展、AppleScript/Shortcuts、Permute、字幕库、代理 UI、自定义集成、自动更新、购买/授权和专有站点解析器。部分文件恢复能力取决于来源服务；不声称与原版的下载引擎等价。

模块责任与本次验证范围见 `docs/architecture.md`；领域用语见 `CONTEXT.md`。

## 版本与发布记录

当前版本以 `VERSION` 为准，构建号以 `BUILD_NUMBER` 为准。每次更新判断大版本、小版本或补丁，并同步变更说明、累计 Excel 和 Git 标签。

- 变更说明：`CHANGELOG.md`
- 累计 Excel：`docs/releases/StreamDrop-version-history.xlsx`
- 发布数据：`docs/releases/history.json`
- 发布流程与一致性检查：`docs/RELEASING.md`

正式安装包与同版本 Excel 在 [GitHub Releases](https://github.com/profundity-max/StreamDrop/releases) 下载。
