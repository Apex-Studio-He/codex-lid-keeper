# 安全说明

[English](SECURITY.md) | 简体中文

Codex Lid Keeper 会以 root 权限修改 macOS 的电源设置，而且用到的
`pmset disablesleep` 并没有公开文档。安装前请先读完这一页，也建议直接查看
安装脚本和相关 Swift 代码。

## 我们重点防什么

这个项目的安全设计围绕五件事：

1. 不做“万能 root 命令执行器”；
2. 不让普通用户替换已经获得 sudo 授权的程序；
3. 只恢复本项目亲自改过、并且留下所有权记录的设置；
4. Hook 丢失、后台进程崩溃或电源条件变化时，仍然能自动收尾；
5. 不把 Codex 的聊天内容或工具参数写进磁盘。

## root 权限有多大

安装后的程序放在 root 管理的目录：

```text
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper
```

sudoers 只放行下面三种调用：

```text
com.zundu.codex-lid-keeper power enable-ac
com.zundu.codex-lid-keeper power enable-battery
com.zundu.codex-lid-keeper power restore
```

Hook 传进来的内容不能决定命令、参数、设置名称或设置值。获得授权的可执行文件和
它的父目录都归 root 所有，普通用户不能偷偷换掉它。

## 为什么不会直接写死为 0

第一次修改前，root Helper 会读取 `pmset -g custom`，记下当前模式和将要修改的
AC / 电池配置。这个记录保存在：

```text
/var/db/com.zundu.codex-lid-keeper.power.json
```

“仅接电”模式只修改 AC 配置；“接电或电池”模式会分别记录并修改 AC 与电池
配置。恢复时逐项写回原值，而不是一律执行 `disablesleep 0`。如果记录损坏，
程序会停止并报错，不会靠猜。

## 后台进程挂了怎么办

用户级 LaunchAgent 负责正常调度；另外还有一个独立的 root LaunchDaemon 做兜底。
出现以下情况时，watchdog 会恢复由本项目接管的设置：

- 心跳超过两分钟没有更新；
- 当前供电不符合所有权记录里的模式；
- 系统无法确认当前电源状态；
- 电量低于不可降低的 30% 硬底线。

任务租约在最近一次有效活动后最长保留八小时；持续活动会续期，长期收不到新活动
或结束事件时也不会无限保持唤醒。

## Hook 会保存什么

Hook 从标准输入读取 JSON，大小上限是 1 MiB。它只读取：

- `session_id`
- `turn_id`
- `cwd`
- `hook_event_name`

`cwd` 写入前只保留最后一级目录名。程序不会为提示词、对话正文、模型回复、工具
输入或工具输出建立字段，也不会保存这些内容。

Hook 不会调用 `sudo`，也不会查询电源。它只把一条小事件原子写入本地队列，然后
返回，让 Codex 继续工作。

为了让新任务立即出现，也能补上 Hook 安装前已经开始的任务，用户后台进程会用
只读方式查看 Codex 的本地状态。它只从线程库取 `id`、`rollout_path`、`cwd`
和更新时间 / 归档标记，并且每个近期 rollout 最多检查末尾 4 MiB。普通行在
JSON 解码前就会被跳过；真正建立的数据结构只有：

- `event_msg` 外层类型；
- `task_started` 或 `task_complete`；
- `turn_id`。

另有一条兼容查询，只读取 `codex_core::session::turn` 对应的 turn 状态元数据。
两条路径都不会查询或建模任务标题、预览、首条消息、提示词、回复或工具内容，
rollout 正文也不会被复制到 Keeper 的状态或日志中。完整 `cwd` 在进入状态前只
保留最后一级目录名。如果这些本地格式以后变了，运行时检测会自动停用，任务跟踪
回退到 Hook。

## 本地文件怎么保护

- 每条队列事件最大 64 KiB，文件权限为 `0600`；
- 写入时会同步文件和目录，再完成原子 rename；
- daemon 会重新验证事件内容；
- 时间比本机快五分钟以上的事件会被拒绝；
- 已处理事件通过 ID 去重，崩溃后重读不会重复生效；
- 队列最多容纳 4,096 条事件，防止后台异常时无限长大；
- 状态和日志只允许当前用户访问；
- 日志到 1 MiB 后轮转，只留上一份。

如果队列已满或暂时写不了，Hook 会选择不阻塞 Codex。此时已经存在的电源接管仍受
root watchdog 保护。

Hook 配置的合并、校验和移除已经改成原生 Swift。它会保留别的工具已有的
handler，只删除命令完全匹配的 Codex Lid Keeper 项；写入前生成带时间戳的备份，
临时文件权限是 `0600`，同步完成后再原子替换。Release 安装不依赖下载来的
Python 运行时，也不会让 Hook 内容决定要执行的命令路径。

## 安装前建议检查

至少看一遍：

- `scripts/install_components.sh`
- `scripts/uninstall_components.sh`
- `Sources/CodexLidKeeperCore/HooksConfiguration.swift`
- `Sources/CodexLidKeeperCLI/main.swift`
- `Resources/com.zundu.codex-lid-keeper.agent.plist`
- `Resources/com.zundu.codex-lid-keeper.recovery.plist`
- `Sources/CodexLidKeeperCore/CodexRuntimeTaskDetector.swift`
- `Sources/CodexLidKeeperCore/PrivilegedPowerManager.swift`

请求管理员权限前，包内安装器会先检查 App 标识、plist、当前芯片架构和签名结构
是否自洽。由于使用的是 ad-hoc 签名，这项检查不能证明发布者身份。sudoers 也会
先通过 `visudo`，验证成功才会放进系统目录。安装后，Codex 还会要求你手动检查并
信任新增 Hook。

## 怎么报告安全问题

安全问题不要发公开 Issue，也不要附上提示词、完整 Hook 内容、密钥或个人路径。
请通过
[GitHub Security Advisory](https://github.com/Apex-Studio-He/codex-lid-keeper/security/advisories/new)
私下报告，并尽量提供：

- 出问题的 commit 和 macOS 版本；
- 能用 dry-run 复现的最小步骤；
- 你认为应该守住的权限边界；
- 是否真的改动了 `pmset`；
- 紧急恢复是否成功。

## 当前支持范围

这是公开 Alpha。当前维护默认分支和最新 App Alpha；App 只有 ad-hoc 签名，不能
据此确认发布者身份，也还没有 Developer ID 签名与 notarization。DMG 会发布
SHA-256，但没有 Apple 分发身份就无法获得正常 Gatekeeper 信任。不建议拿它做
无人值守部署。
