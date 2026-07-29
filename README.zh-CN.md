# Codex Lid Keeper

[English](README.md) | [简体中文](README.zh-CN.md)

> **v0.1.0-alpha — 仅源码测试版**
>
> 请先阅读[测试指南](TESTING.md)和[安全策略](SECURITY.zh-CN.md)，并提前保存
> “紧急恢复”命令。本版本不会分发未经签名的可执行文件。

Codex Lid Keeper 是一个实验性的 macOS 辅助工具：当本地 Codex 正在工作时，
它让合盖后的 MacBook 继续运行；最后一个任务结束后，再恢复用户原来的合盖
睡眠设置。

它采用保守的安全策略：

- 必须连接交流电源。
- 即使正在接电，电量低于 30% 也会恢复睡眠。
- 每个任务都是可续期租约，并设置八小时硬过期时间。
- 如果用户级 daemon 超过两分钟没有更新心跳，root watchdog 会恢复原设置。
- Hook 只负责把最小生命周期事件原子写入队列，不等待 `sudo` 或电源协调。
- 持久化内容仅包含 session、turn、事件、时间和项目名称，不保存提示词、
  工具输入或模型输出。

> **重要警告**
>
> 本项目使用未公开的 `pmset disablesleep` 设置。Apple 可能在任何 macOS
> 更新中改变或移除该行为。绝不能把正在运行且已合盖的 MacBook 放进包、内胆包、
> 抽屉或其他通风不良的位置。

## 当前范围

仓库包含一个可运行的无界面 MVP：

- 非阻塞 Codex 生命周期 Hook 和崩溃安全事件队列
- 支持并行任务的租约状态机
- 基于 IOKit 的原生电源与电量检测
- root 所有的睡眠设置所有权记录
- 非交互、精确命令级别的 sudo 权限边界
- launchd 用户代理和 root 恢复 watchdog
- `status`、`pause`、`resume`、`clear` 与紧急恢复命令
- 安全合并和移除 Hook 的脚本
- 零依赖 Swift 自测和隔离的 dry-run 集成测试

当前不包含菜单栏界面、签名 App、notarization、DMG 或自动更新。不同 Mac 型号
和 macOS 版本仍必须分别执行真实合盖验收。

## 系统要求

- macOS 13 或更高版本的 MacBook
- 带 Swift 6 的 Apple Command Line Tools
- 支持生命周期 Hooks 的当前 Codex 版本
- 安装时可使用管理员账户

Codex 会要求用户检查并信任新增或修改过的 command Hook；未经信任的 Hook 不会运行。

## 在不修改电源设置的情况下构建和测试

以下命令不会执行特权 `pmset` 操作：

```bash
swift build
swift run codex-lid-keeper-self-test
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py
```

集成测试使用隔离的临时 home 和 dry-run 电源标记。

## 安装

先检查源码，再运行：

```bash
./scripts/install.sh
```

安装脚本会先构建并执行非特权自测，然后请求管理员权限。它会：

1. 将 root 所有的可执行文件安装到
   `/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper`；
2. 安装 sudoers 规则，只允许该 root 可执行文件执行 `power enable` 与
   `power restore`；
3. 在 `/Library/LaunchDaemons` 安装 root 恢复 watchdog；
4. 在 `~/Library/LaunchAgents` 安装用户级协调代理；
5. 备份并合并五个生命周期处理器到 `~/.codex/hooks.json`。

安装完成后，在 Codex 中打开 `/hooks`，检查并信任新增定义。

查看状态：

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper status
```

## 命令

```text
status [--json]      显示租约、待处理事件、电源状态和最新决策
pause                恢复本项目拥有的状态，并暂停后续激活
resume               重新启用自动化
clear                清除卡住的租约，不改变暂停/启用偏好
emergency-restore    暂停、清除租约并立即恢复原设置
config show          输出带安全边界的当前配置
```

运行状态与日志位于：

```text
~/Library/Application Support/CodexLidKeeper/
```

生成的 `config.json` 支持：

- `minimumBatteryPercent`：`30...100`，默认 `30`
- `leaseDuration`：`60...86400` 秒，默认 `28800`
- `releaseDelay`：`0...300` 秒，默认 `20`
- `eventPollInterval`：`0.25...5` 秒，默认 `1`
- `powerHeartbeatInterval`：`5...30` 秒，默认 `10`

当前 MVP 不能关闭“必须接电”这一要求。root watchdog 始终执行 30% 电量底线；
配置只能收紧安全阈值，不能放宽。无效配置会以安全方式失败。旧版
`pollInterval` 会在迁移时被解释为电源心跳间隔。

## 工作原理

```text
Codex 生命周期 Hook
        │ 只解析必要字段
        ▼
私有原子事件队列 ── Hook 返回 {}
        │
        │ 用户代理每批最多消费 512 个事件
        ▼
幂等租约归约器 ──> 原子用户状态
        │
        │ 接电 + 电量安全 + 存在活跃租约
        ▼
root 电源辅助程序 ──> pmset -c disablesleep 1

无租约 / 拔电 / 低电量 / 心跳过期
        │
        ▼
恢复之前记录的 AC 配置
```

每个事件以私有 `0600` 文件原子提交；Hook 返回前会同步文件和所在目录。
daemon 每秒检查队列，按时间顺序处理事件，并记住事件 ID，避免崩溃重放产生
重复效果。队列最多保存 4,096 个文件；畸形、超大或超前五分钟以上的事件会被
拒绝。`status` 会显示待处理数量。

辅助程序在修改 AC 配置前写入
`/var/db/com.zundu.codex-lid-keeper.power.json`。该 root 所有的记录保存 AC
配置中 `disablesleep` 原本是否开启。电池配置不会被修改，恢复时也不会盲目
假设原值为 `0`。

daemon 启动时协调一次；应用事件后立即协调；仅在存在租约或本项目拥有电源状态时
每十秒维护一次。完全空闲后，每秒队列检查不会查询 IOKit，也不会重写
`state.json`。单独的 root LaunchDaemon 每分钟检查一次，并在以下情况下恢复：

- 心跳超过两分钟；
- 未接交流电，或无法判断电源状态；
- 电量低于默认安全阈值。

## 手动合盖验收

自动测试故意不会修改真实睡眠设置。请在桌面、通风无遮挡的环境中测试：

1. 连接原装或规格合适的电源适配器。
2. 启动一个会持续数分钟并产生可观察本地变化的 Codex 任务。
3. 确认 `status` 显示活跃任务和 `Sleep override owned: yes`。
4. 合盖两到五分钟。
5. 开盖并确认任务与本地时间戳在合盖期间继续推进。
6. 等待最后一个任务结束，再等待至少 20 秒，确认任务数为零且不再拥有 override。
7. 再次合盖，确认系统恢复正常睡眠。

重大 macOS 更新后应重新执行验收。更完整的测试矩阵见
[TESTING.md](TESTING.md)。

## 紧急恢复

通常执行：

```bash
./scripts/emergency-restore.sh
```

或：

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper emergency-restore
```

紧急命令不依赖有效的 `config.json`。如果所有权记录损坏，程序会拒绝猜测原值；
请检查该记录与 `pmset -g custom` 后再手动修改。

## 卸载

```bash
./scripts/uninstall.sh
```

卸载会先恢复本项目拥有的电源状态，再移除辅助程序、sudoers、launchd 任务和
Hook。用户日志与配置会被保留，并在终端中显示路径。

## 安全与隐私

详见[中文安全策略](SECURITY.zh-CN.md)和 [SECURITY.md](SECURITY.md)：

- sudo 授权的可执行文件及其父目录由 root 所有；
- sudoers 只允许两组精确参数；
- root 所有权记录不能由普通用户写入；
- Hook 对 Codex 工作采用 fail-open，电源 watchdog 采用 fail-safe；
- 不持久化提示词、对话、工具输入或工具输出。

活动日志达到 1 MiB 后轮转，只保留上一代日志。

## 状态与限制

本项目是实验软件，不属于 Apple 或 OpenAI：

- `pmset disablesleep` 未公开。
- 合盖后的网络和散热表现会随硬件变化。
- 正式分发应改用签名的 Service Management 特权 Helper。
- 在目标 Mac 完成手动验收前，不对兼容性作保证。

## 测试与贡献资料

- [双语测试指南](TESTING.md)
- [架构说明](docs/ARCHITECTURE.md)
- [参与贡献](CONTRIBUTING.md)
- [变更记录](CHANGELOG.md)
- [中文安全策略](SECURITY.zh-CN.md)

## 致谢

设计调研参考了：

- [Lu233/CodexAwake](https://github.com/Lu233/CodexAwake)
- [Moarram/wake](https://github.com/Moarram/wake)
- [Ami3466/claude-awake](https://github.com/Ami3466/claude-awake)

本仓库未复制或打包这些项目的源码。

## 许可证

MIT，见 [LICENSE](LICENSE)。
