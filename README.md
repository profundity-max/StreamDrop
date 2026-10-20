# StreamDrop

**把链接变成本地文件。** StreamDrop 是一款原生 macOS 下载工具，用简洁的队列管理文件、网页视频和音频下载。

粘贴或拖入链接，选择格式和画质，即可开始下载。暂停、继续、重试、查看历史和在 Finder 中定位文件，都可以在 App 内完成。

[下载安装包](https://github.com/profundity-max/StreamDrop/releases/latest) · [查看版本记录](https://github.com/profundity-max/StreamDrop/releases) · [浏览当前代码](https://github.com/profundity-max/StreamDrop/tree/codex/download-architecture)

## 主要功能

- **文件与网页视频下载**：文件直链使用系统下载能力；网页视频、HLS 和 DASH 由本机 yt-dlp 解析。
- **音频提取与合并**：选择保存视频或提取 M4A 音频，通过 FFmpeg 合并分离的音视频。
- **下载队列**：多链接添加、并发控制、暂停、继续、取消和重试。断点续传取决于来源服务器。
- **保留视频标题**：保留中文、空格和原有方括号，不额外追加视频 ID。同名文件自动编号，长标题保留扩展名后缩短。
- **系统播放兼容性**：优先选择兼容格式，必要时转换为 H.264/AAC，并检查系统是否能解码实际画面。
- **本地历史记录**：搜索、重新下载和在 Finder 中显示。清空记录不会删除下载文件。
- **工具检查与诊断**：实际检查 yt-dlp、FFmpeg 的版本和运行状态，复制带有 App、系统及工具信息的诊断。
- **网页媒体查找**：通过内置临时 WebKit 浏览器查找媒体元素，或把当前网页交给下载工具解析。

## 安装

适用于 **macOS 13 及更新版本**。安装包同时包含 Apple Silicon 和 Intel 架构。

1. 在 [Releases](https://github.com/profundity-max/StreamDrop/releases/latest) 下载最新 DMG。
2. 打开映像，将 **StreamDrop** 拖入 **Applications（应用程序）**。
3. 从应用程序目录打开 App。

也可以下载 ZIP，解压后将 App 移入应用程序目录。当前安装包使用 ad-hoc 签名，尚未进行 Developer ID 公证，macOS 可能限制打开。

### 外部工具

| 使用方式 | 所需工具 |
| --- | --- |
| 文件直链 | 无需额外工具 |
| 网页视频、HLS / DASH | yt-dlp |
| M4A 提取、音视频合并、兼容性转换 | FFmpeg；网页解析仍需 yt-dlp |

在 **设置 → 外部工具** 中选择本机已有的可执行文件，再点击「检查工具版本与运行状态」。留空时检测 `/opt/homebrew/bin`、`/usr/local/bin` 和 `/usr/bin`。App 不会自动安装或升级工具，也无需配置 Node.js 或 Python 项目环境。

## 快速开始

1. 按 **⌘L** 添加链接，或将链接拖入主窗口。多条链接可用空格或换行分隔。
2. 选择自动识别、网页视频或文件直链，并选择视频 / 音频和画质。
3. 下载完成后，从卡片打开文件或在 Finder 中显示。

| 快捷键 | 操作 |
| --- | --- |
| ⌘L | 打开链接 |
| ⌘⇧V | 从粘贴板添加 |
| ⌘Y | 打开历史记录 |
| ⌘, | 打开设置 |

默认开启「优先 MP4 与系统播放兼容性」。转换会增加处理时间；关闭后保留来源编码。文件直链始终保留原始字节。画面检查代表实际采样的解码结果，不保证整片视频或音轨质量。

## 数据与恢复

队列、历史、设置和原始链接保存在本机的 `~/Library/Application Support/StreamDrop/`。其中 `state.json` 保存记录，`Transfers/` 保存部分下载，`Completions/` 保存待恢复或清理的完成提交。

正常退出会暂停任务并等待下载、转换和工具检查收尾。重启后，未完成任务以暂停状态保留，需手动继续。完成提交中断时，App 会先确认文件归属再恢复记录；状态损坏或版本不兼容时保留原始数据并报告错误。系统强制结束或断电不提供同等恢复保证。

App 不上传下载历史或诊断；下载会连接用户添加的网站及其媒体 CDN。链接中的参数也会保存在本地，分享诊断前可先检查内容。内置浏览器使用临时网站数据，不导入其他浏览器的 Cookie。

## 当前范围

网页支持范围取决于 yt-dlp 版本和来源网站。需要登录、受保护或加密的媒体不保证支持；内置浏览器可能无法发现跨域 iframe 或 blob 媒体。目前没有浏览器扩展、字幕批量管理、代理设置界面或自动更新功能。

## 开发与验证

安装包与源码通过 Release 标签对应。开发代码位于 `codex/download-architecture` 分支；默认分支的介绍会同步更新，构建时请使用开发分支或对应发布标签。

```sh
git clone --branch codex/download-architecture https://github.com/profundity-max/StreamDrop.git
cd StreamDrop
./scripts/build.sh
```

使用 Xcode 自带的 Swift 工具链构建。界面采用 SwiftUI / AppKit，直链使用 URLSession，网页浏览使用 WebKit，播放检查使用 AVFoundation。产物位于 `output/`，包含 App、DMG 和 ZIP。

```sh
python3 scripts/test.py --require-tools
python3 scripts/test-release-records.py
python3 scripts/test-test-gate.py
python3 scripts/check-release.py --built
```

完整测试需要本机已有 yt-dlp 和 FFmpeg，使用本地合成媒体验证下载、转换、暂停恢复、进程收尾和状态保存。严格模式拒绝缺少工具、跳过、失败或不完整的报告。GitHub Actions 还会验证 universal 构建、签名和 DMG。

## 版本记录

每次发布记录版本判断、变更说明、验证范围和 Git 标签，并提供累计 Excel 台账。安装包、Excel、发布元数据和 SHA-256 校验文件均可在 [Releases](https://github.com/profundity-max/StreamDrop/releases) 获取。

- [变更说明](https://github.com/profundity-max/StreamDrop/blob/codex/download-architecture/CHANGELOG.md)
- [下载版本台账](https://github.com/profundity-max/StreamDrop/releases/latest/download/StreamDrop-version-history.xlsx)
- [发布流程](https://github.com/profundity-max/StreamDrop/blob/codex/download-architecture/docs/RELEASING.md)
