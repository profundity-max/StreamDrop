# 验证记录

日期：2026-10-18。环境：Apple Silicon macOS，Xcode 自带 Swift 6.3.3，Swift 5 language mode，deployment target macOS 13。

## 已执行

- `python3 scripts/test.py`：**15 项 XCTest 测试通过，0 失败**。测试执行 21.48 秒；包含 SwiftPM 构建/启动的脚本运行 72.20 秒。不是原版性能对比，未测 CPU 时间或进程家族峰值内存。
- 真实 loopback HTTP 服务校验下载的完整 4 MiB 字节；同名下载不覆盖；HTTP 404、错误 HTML 不计入成功历史。
- URL 输入保留 query；不支持的 scheme/混合错误输入拒绝；文件名安全；损坏状态文件保留。
- 最大并发限制、手动开始、直链暂停/继续、取消/重试、完成后历史与重载。
- 已安装 yt-dlp 的真实 generic 网页解析、网页任务暂停/续传；实际本地 HLS 视频下载及 FFmpeg M4A 音频提取。
- 新建进程组中忽略 INT/TERM 的真实 shell + sleep 子进程，停止后升级到 KILL，验证 leader 清理、输出 EOF 与子进程退出（约 4.1 秒）。不把模拟返回当成真实工具覆盖。
- 损坏续传记录回退原 URL；resume envelope 的 URL/摘要绑定；15 轮坏记录立即暂停，确认 acknowledgement 后无进度/完成事件。
- GUI：构建的 .app 可启动；添加 URL → 实际文件下载 → 完成卡片 → 历史记录；重启可读取之前记录；历史搜索正确过滤。
- GUI：引导浏览器载入合成视频网页，扫描得到 sample.mp4，候选正确填入添加弹窗，打开后下载完成。FFprobe 验证 GUI 下载文件包含 H.264 320×180 与 AAC 音轨。
- GUI：设置侧栏正常；工具页检测到 `/opt/homebrew/bin/yt-dlp` 和 `/opt/homebrew/bin/ffmpeg`。主窗口、添加弹窗、历史、设置和引导浏览器截图存于 `reference/`。对照原版调整浅灰画布、底部白色圆角工具栏、紫色按钮与标题位置。
- `scripts/build.sh`：release universal **arm64 + x86_64** 构建成功，生成 `.app`、`.dmg` 和 `.zip`；使用原创图标，无原版资源进入 app。
- `codesign --verify --deep --strict` 成功。`hdiutil verify` 显示 DMG CRC32 校验有效；只读挂载后包内签名也通过，包内可执行文件与 output/.app 的 SHA-256 相同，Applications 安装快捷方式存在，检查后已卸载映像。
- 测试生成的两个 GUI 下载文件与对应记录移至 `.test-output/`，状态备份保留；应用交付时队列清空。不修改其他用户文件。

## 发现并修复的问题

1. SwiftUI bool sheet 在同一更新中读取旧 initial URL。统一为 `LinkDraft` item 驱动 presentation，GUI 复测候选文本与下载闭环通过。
2. yt-dlp 主进程停止不能保证 FFmpeg 子进程清理，两个输出读取者也可能丢最后的路径。改成拥有的 POSIX 进程组；leader 保持未回收以保留身份，组收尾后回收；单一读取者排空后才结算。
3. 旧断点反复复用、恢复回退与暂停竞态。改为单次消费、共同锁保护的任务替换与停止意图，无法恢复时只回退一次。
4. 坏 opaque 数据直接交给 Foundation 可能抛 ObjC 异常，异步 XCTest 观察器还会报告任务分配异常。增加自有完整性 envelope，非法记录不进入系统解码器；同步 delegate 边界回归与完整套件通过。
5. 独立只读复审指出以上生命周期问题，修复后复审未发现新的关键问题。复审是源码结论，执行证据以上述实际测试为准。

## 未覆盖与差异

- 公共视频网站、登录、Cookie、保护媒体、直播长时间稳定性尚未实测；真实已验证的网页/HLS 均为本地可控 fixture，不能推导所有站点兼容。
- 原版的专有解析器、浏览器插件、Permute、字幕库、代理设置、AppleScript/Shortcuts、自定义集成与同步未重建。历史使用独立 JSON，不声称兼容原版 Core Data 或 .downiepart。
- 原版下载卡片运行态没有截图证据；重建卡片为自主设计。原版 NIB 解码覆盖有限，未声称逐像素还原全部页面。
- x86_64 已编译并包含在 universal 包，未在 Intel Mac 实机运行。最低 macOS 13 来自编译目标，未在 macOS 13 实机验证。深色模式采用系统动态颜色，未完成截图回归。
- 外部 yt-dlp/FFmpeg 使用现有安装，不随 .app 分发，也不会自动安装。缺少工具时直链仍可工作，网页/转换显示具体提示。
- 使用 ad-hoc 签名，未做 Apple Developer ID 签名或公证；不声明可通过跨机器 Gatekeeper 分发验证。

## 1.0.1 调试补记

YouTube 403 已进行公共站点实测；旧引擎完整下载失败、新版完整下载并合并成功。新增诊断回归后 18 tests / 0 failures。详细原始观察、应用内验证与范围见 [youtube-debug.md](youtube-debug.md)。此前未测试公共站点的记录仅描述首版验证时点。

## 1.0.2 播放兼容性补记

用户首条视频包含 VP9 视频流与 AAC 音频，FFmpeg 可解码画面，但本机 AVAssetReader 报 -11833/-12906，无法输出画面；后续成功样本使用 AV1 且原生解码成功。不能仅凭 MP4 扩展名或视频轨道存在判定系统可播放。

新增原生画面验证、必要时 H.264 转换及转换后验证。实际首条视频兼容副本为 H.264 1920×1080 / AAC，515.691973 秒，56,364,977 字节，AVAssetReader 成功输出像素。保留原文件，仅调整该任务和历史的输出路径；状态更改前已备份。

`python3 scripts/test.py`：21 XCTest / 0 failures，测试 23.73 秒，含构建脚本耗时 25.82 秒。包含真实 VP9 网页下载→转换→原生画面解码、转换阶段取消不生成历史、终态失败排队后暂停及重新调度。VP9 用例修复前原生解码失败；暂停竞态用例修复前卡在 pausing，修复后通过。未测 CPU 时间及峰值进程家族内存；公共站点未重复下载。

当前通过项目 output/StreamDrop.app 运行，未复制到 /Applications 或 ~/Applications。DMG 是可供拖拽安装的交付物，不等于已经安装。详见 [codec-debug.md](codec-debug.md)。

1.0.2 最终构建成功，universal arm64/x86_64，App 严格签名校验与 DMG 校验通过。新版 GUI 重启后显示兼容副本 56.4 MB，点击卡片打开正确文件；QuickTime 跳至 30 秒实际显示内容画面，原生系统播放器界面复核通过。只读复审确认网页暂停竞态已消除。

## 1.0.3 三项架构重构

按生命周期 → 完成提交恢复 → 播放观察顺序实施并独立复审，详情见 [architecture.md](architecture.md)。最终组合 26 项测试全部通过（24.05 秒，含构建 27.85 秒）。已生成 arm64/x86_64 universal App、DMG 和 ZIP，App 严格签名检查及 DMG 校验通过。GUI 实际重启加载原有四条完成任务，队列与历史显示“无画面验证记录”，没有把旧记录自动认定为已验证；实际媒体文件未改。

新增磁盘测试是临时目录内的真实失败和恢复，不是公共站点复现。本轮未重下 YouTube/B站、未测跨卷中断、断电、Intel/macOS 13 实机或 CPU/内存性能。跨卷身份无法确认的中断会保留现场并报告未知。
