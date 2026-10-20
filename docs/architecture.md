# 下载执行、完成提交与播放观察

## 1.1.2 存储、文件名与发布记录收敛

2026-10-20，按存储 → 最终文件名 → 发布记录顺序优化。

StateStore 以引用会话拥有状态读取验证及写入许可，save、complete、
recoverCompletions 与 prepareExecution 共用该许可；Queue 不再持有另一套
storageBlocked。启动 Transfer Run 前先恢复该任务的 Completion Commit，
避免重新下载覆盖待恢复的工作产物。清理先持久化可选 stateCommitted
阶段，再清理工作目录并保存移除标记的状态，最后删除 receipt；旧凭据
缺该字段仍按原有 completionCleanup 标记恢复。只有状态确认后才进入清理。

FileNames module 拥有最终文件名 interface：按目录的 NAME_MAX 与保守的
255 UTF-8 字节预算，先保留扩展名和冲突编号，再按完整 Character 缩短
标题。该预算不声称是 APFS 的准确 Unicode 计数规则。移除旧 safe 中对
整个文件名的 180 字符截断；下载引擎内部临时路径继续由各 Transfer 拥有。

发布事实由 history.json 拥有，latest.notes 提供兼容与限制说明。Excel
builder 只负责布局，独立 Python checker 直接读取 OOXML 验证内容，并以
显式异常拒绝漂移；不再依赖可被优化模式跳过的 assert。

验证：31 项 XCTest 通过，26.57 秒，含构建 31.18 秒；3 项 Python 测试
通过，各运行普通及 -O 两种解释器模式。旧文件名代码的实际落盘测试
出现扩展名丢失与复合 emoji 名称过长，修正后通过。独立只读复审无阻塞。
未注入清理末次保存或最终 receipt 删除失败，未测断电或跨卷中断。
未做等价性能基准，token、CPU 时间和进程家族峰值内存均未测量。

## 1.0.3 原始重构记录

StreamDrop 1.0.3，2026-10-18。三项重构按顺序完成。

## 下载执行

TransferRun 在 MainActor 串行处理用户停止意图和 adapter 事件，每次执行只向队列交付一个终态。队列保留调度、展示、持久记录，不再按 useDirect 解释失败是否已结束。

DirectTransfer 直到 URLSession 失效且恢复数据回调齐备才结算；下载位置回调只暂存结果，不提前报告成功。WebTransfer 拥有下载进程并交接产物准备，OwnedProcess 保留现有进程组身份与输出排空规则。

真实直链立即暂停测试新增终态计数：原实现 15 次均报告多于一个终态；重构后通过。原有真实 HTTP、HLS、网页解析、暂停/重试与取消转换回归继续保留。

## 完成提交

StateStore 的完成提交负责选择不覆盖目标、保存恢复 receipt、移动产物、确认文件身份、保存完成状态和历史、清理工作目录与 receipt。状态中可选 completionCleanup 清单与完成记录同次保存，保存成功才授权清理；保存失败不会污染调用方的确认事实。

恢复检查设备、inode、generation 和 birthtime；不凭文件名或大小认领文件。仅待清理的提交不重新插入记录，用户已清空的队列或历史不会复活。持续清理失败以 warning 单独报告，不丢弃正常任务、历史及偏好。

新增真实磁盘回归覆盖连续状态保存失败后重载、恢复幂等、目标重名不覆盖、目标替换不认领、清理失败持续重载、用户移除记录后清理重试。新 interface 首次测试在缺少 implementation 时编译失败，随后实现并通过；不把这种编译失败称作旧版磁盘故障运行复现。

跨卷移动若恰在移动后、刷新持久文件身份前中断，恢复将保留记录并报告身份未知，需人工核对；本轮未做跨卷或断电故障注入。原子 JSON 写入不等于断电事务。

## 产物准备与观察

MediaPreparation 拥有原生探测、必要转换、后验探测及转换进程收尾；WebTransfer 不再解释原生观察或 FFmpeg 转换输出。DownloadArtifact 随文件携带 PlaybackObservation，完成 receipt、队列和历史保留该事实。转换进度使用 processing 事件，保留原下载网络计数。

观察分为 decoded、converted、unknown、notChecked。unknown 保留原因，直链保持字节原样并记录 notChecked。旧记录缺字段保持无验证记录。队列和历史均可查看标签及详细说明；不把首帧采样当作全片/音轨验证。

## 已执行验证

- 第 1 项完整 21 项测试通过，23.84 秒，含构建 27.95 秒。
- 第 2 项完整 25 项通过，23.94 秒，含构建 27.38 秒；之后针对保存失败不授权清理的修正，4 项完成提交测试通过。
- 第 3 项及组合完整 26 项通过，24.05 秒，含构建 27.85 秒。真实本地 VP9 转换与画面解码、unknown 原因保存重载、原生可解码文件及直链未检查标记均通过。
- 三阶段独立只读审查；第 2 项审查发现的持久身份、持续清理失败、用户删除记录和未落盘清理标记问题均已修正，复审确认。

测试执行时间包含新增用例，不能作为等价性能基准；未测 CPU 时间、进程家族峰值内存或 token 使用。未重下公共视频网站；不声称跨站点、Intel 实机或 macOS 13 实机覆盖。Swift 5 language mode 下原有控制主线程时序的测试使用 Thread.sleep，会产生未来 Swift 6 language mode 的编译警告，尚未迁移 Swift 6。
