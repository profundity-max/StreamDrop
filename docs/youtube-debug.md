# YouTube 下载 403 调试记录（StreamDrop 1.0.1）

日期：2026-10-18。原任务：`E7A8809A-7A7C-44CB-BAA9-B794BC58A560`，视频 `UD8_5fhFayY`。

## 观察与定位

用户截图露出的是旧版本警告。应用保留的实际末尾错误为 `ERROR: unable to download video data: HTTP Error 403: Forbidden`。原任务调用的是 Homebrew yt-dlp 2026.07.04，已有 Deno 与 EJS，因此没有凭警告推断缺少 JS 运行时，也没有改系统代理或读取浏览器 Cookie。

对同一视频进行了实际对照：

- 原版参数、完整下载：旧引擎选 android_vr、399+140，复现 HTTP 403。
- `--test` 小数据探测：前 10 KiB 成功，但完整下载仍失败。因此不把探测成功当成下载成功。
- 同一旧引擎只改 `--http-chunk-size 1M`：下载约 3.9 MiB 后仍 403，没有将该尝试集成进应用。
- 旧引擎强制 web 客户端：没有可用媒体格式，没有将该尝试集成进应用。
- 官方 yt-dlp 2026.08.19：选 visionos / 616+140，完整下载并合并成功。FFprobe：VP9 1920×1080、AAC、515.691973 秒、79,787,468 bytes。

官方 [2026.08.19 发布记录](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19)包含 YouTube 客户端维护与从默认列表移除 android_vr 的变更；[对应 PR](https://github.com/yt-dlp/yt-dlp/pull/17461)与本次旧客户端 403 的现象一致。以上结论针对本次链接与当前网络，不承诺所有 YouTube 403 都由同一原因产生。

## 本机修复

从官方 GitHub release 下载 `yt-dlp_macos`，与同版本官方 `SHA2-256SUMS` 核对：

`0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202`

保存到 `~/Library/Application Support/StreamDrop/Tools/yt-dlp/2026.08.19/yt-dlp`，附来源、版本、摘要元数据；已有目标仅在摘要相同的情况下复用。通过 App 设置保存为明确工具路径。没有修改或升级 Homebrew/system yt-dlp，没有安装或升级 Node、Deno、FFmpeg，没有改变代理、浏览器登录或安全配置。该专用引擎不包含在可安装 .app 中；本机设置在安装新版后继续保留。

## 代码修复

- `DownloadDiagnostics` 拥有原始诊断与摘要的区别：实际 `ERROR:` 优先于过旧警告；没有错误行时保留原始有效原因。
- WebTransfer 在进程结束时写入完整的有界诊断到该任务工作目录下 `yt-dlp.log`，不记录环境变量；写日志失败仍保留内联错误。
- 下载卡片显示错误摘要，增加详情按钮，完整内容可查看、复制；日志存在时可在 Finder 中显示。旧失败任务即使没有新日志也能查看原状态中保存的原因。
- 版本更新为 1.0.1 / build 2。安装包与系统原有依赖相互独立，本机选定的新版引擎路径保存在用户设置。

## 验证

- 新增三个回归测试：过旧警告不得遮住 403、普通/多错误的呈现、真实网页失败保留完整日志。
- 完整 `scripts/test.py`：18 tests，0 failures；测试执行 21.956 秒，包含构建 26.76 秒。
- universal arm64 + x86_64 release 构建成功，app 签名与 DMG 完整性检查成功。
- GUI 已验证旧失败任务显示真实 403，详情保留版本警告与实际错误；已为原任务点击重试并开始实际下载。
- 原失败任务在实际 App 中重试后完成，保存到 `/Users/ethan/Downloads/AI_Karpathy_-_5000_AI [UD8_5fhFayY].mp4`。FFprobe 读取全部数据包：VP9 1920×1080（15,466 packets）、AAC（22,209 packets）、515.691973 秒、79,787,468 bytes。画面与音轨均存在，未以元数据提取或小片段探测替代完整下载。
- 完成卡片原先沿用最后一条音轨的网络计数，错误显示 8.3 MB。完成文件大小现在由输出文件拥有者在保存成功后测量，存入独立可选 `fileSize`，不覆盖原传输计数；旧记录缺字段时保持未知。已通过 HLS/音频转换实际回归；本次完成任务在备份状态后补入实测文件大小，其他字段与记录保持原值。

复现日志、摘要校验文件、媒体检查和截图保存在 `.test-output/youtube-debug/`。这些是本地诊断产物，不提交 REA 仓库。

最终交付检查：StreamDrop 1.0.1 已重新打开，原任务为「下载完成」，卡片显示 79.8 MB；最终 universal app 签名检查及最终 DMG CRC32 校验通过。
