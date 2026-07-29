# 安全策略

[English](SECURITY.md) | [简体中文](SECURITY.zh-CN.md)

## 安全模型

Codex Lid Keeper 会以 root 权限修改一个未公开的 macOS 电源设置。主要安全目标：

1. 不提供通用的特权命令执行器；
2. 不允许普通用户替换获得 sudo 授权的可执行文件；
3. 只恢复本项目明确拥有的设置；
4. 在生命周期事件丢失或组件故障后以安全方式恢复；
5. 不保留 Codex 提示词或项目内容。

安装后的可执行文件位于 root 所有的
`/Library/PrivilegedHelperTools`。sudoers 只允许：

```text
com.zundu.codex-lid-keeper power enable
com.zundu.codex-lid-keeper power restore
```

Hook 输入不能提供命令字符串、路径、设置名称或设置值。

root 进程修改 AC 配置前，会写入一个 root 所有的记录，保存 AC
`disablesleep` 原值。程序不会修改电池配置。如果该记录无法解析，恢复会报错并
停止，而不是猜测原值。

独立的 root LaunchDaemon 会在用户代理心跳过期后恢复本项目拥有的状态，并再次
检查交流电和低电量条件。

## 数据处理

Hook 从标准输入读取 JSON，最大 1 MiB。Hook 只把最小事件原子入队，不调用
`sudo`、不查询电源，也不等待 daemon。只解析：

- `session_id`
- `turn_id`
- `cwd`（持久化前缩减为最后一个路径部分）
- `hook_event_name`

提示词、对话、模型回复、工具输入和工具输出不会被解析或存储。

每个队列事件最大 64 KiB，以 `0600` 权限创建，并由 daemon 再次验证。原子
rename 前后会同步文件与目录。超过 daemon 时钟五分钟的事件会被拒绝，避免时钟
修正产生超长租约。处理通过事件 ID 保证幂等。

队列最多保存 4,096 个待处理事件。如果队列已满或不可用，Hook 会 fail-open，
避免阻塞 Codex；已经存在的电源所有权仍受 root watchdog 约束。状态和日志仅用户
可读写；日志达到 1 MiB 后轮转，只保留上一代。

## 安装审查

安装脚本会修改敏感系统位置。请检查：

- `scripts/install.sh`
- `scripts/uninstall.sh`
- `Resources/com.zundu.codex-lid-keeper.recovery.plist`
- 生成的 `/etc/sudoers.d/codex-lid-keeper`

安装器会先用 `visudo` 验证 sudoers 片段。Codex 还会单独要求用户检查并信任
Hook。

## 报告漏洞

不要在公开 Issue 中包含密钥、Hook 完整载荷、提示词、对话或个人路径。请使用
[GitHub Security Advisory](https://github.com/Apex-Studio-He/codex-lid-keeper/security/advisories/new)
私下报告，并提供：

- 受影响的 commit 与 macOS 版本；
- 尽可能使用 dry-run 的复现步骤；
- 预期与实际的权限边界；
- 是否修改了真实电源设置。

## 支持范围

在签名版本出现前，仅维护默认分支。本项目仍处于实验阶段，不应无人值守部署。
