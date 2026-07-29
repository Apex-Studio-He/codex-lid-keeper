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

sudoers 只放行下面两种调用：

```text
com.zundu.codex-lid-keeper power enable
com.zundu.codex-lid-keeper power restore
```

Hook 传进来的内容不能决定命令、参数、设置名称或设置值。获得授权的可执行文件和
它的父目录都归 root 所有，普通用户不能偷偷换掉它。

## 为什么不会直接写死为 0

第一次修改前，root Helper 会读取 `pmset -g custom` 里的 AC 配置，并记下
`disablesleep` 原本是否开启。这个记录保存在：

```text
/var/db/com.zundu.codex-lid-keeper.power.json
```

恢复时写回记录中的原值，而不是一律执行 `disablesleep 0`。如果记录损坏，程序
会停止并报错，不会靠猜。

本项目只修改 AC 配置，不动电池配置。

## 后台进程挂了怎么办

用户级 LaunchAgent 负责正常调度；另外还有一个独立的 root LaunchDaemon 做兜底。
出现以下情况时，watchdog 会恢复由本项目接管的设置：

- 心跳超过两分钟没有更新；
- MacBook 已经拔掉外接电源；
- 系统无法确认当前电源状态；
- 电量低于安全线。

任务本身也有最长八小时的硬过期时间，避免某个结束事件丢失后一直保持唤醒。

## Hook 会保存什么

Hook 从标准输入读取 JSON，大小上限是 1 MiB。它只读取：

- `session_id`
- `turn_id`
- `cwd`
- `hook_event_name`

`cwd` 写入前只保留最后一级目录名。提示词、对话正文、模型回复、工具输入和工具
输出都不会解析，更不会保存。

Hook 不会调用 `sudo`，也不会查询电源。它只把一条小事件原子写入本地队列，然后
返回，让 Codex 继续工作。

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

## 安装前建议检查

至少看一遍：

- `scripts/install.sh`
- `scripts/uninstall.sh`
- `scripts/hooks_config.py`
- `Resources/com.zundu.codex-lid-keeper.agent.plist`
- `Resources/com.zundu.codex-lid-keeper.recovery.plist`
- `Sources/CodexLidKeeperCore/PrivilegedPowerManager.swift`

安装脚本会先用 `visudo` 检查 sudoers 文件，验证通过才会放进系统目录。安装后，
Codex 还会要求你手动检查并信任新增 Hook。

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

这是公开 Alpha。没有签名 App 和正式安装包之前，只维护默认分支，不建议拿它做
无人值守部署。
