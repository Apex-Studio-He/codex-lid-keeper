# Codex Lid Keeper

[English](README.md) | 简体中文

> **v0.1.0-alpha｜公开测试版，只提供源码**
>
> 第一次使用请先看[测试指南](TESTING.md)和[安全说明](SECURITY.zh-CN.md)，
> 并把紧急恢复命令记下来。本项目暂时不提供未经签名的二进制安装包。

让 MacBook 合盖后继续跑本地 Codex 任务。任务结束，它会把系统原来的睡眠设置
恢复回来。

## 先说风险

这个项目用到了 macOS 没有公开文档的 `pmset disablesleep`。系统升级后，
这项设置可能失效，也可能出现行为变化。

**一定不要把合盖运行中的 MacBook 塞进背包、内胆包、抽屉或其他不通风的地方。**
第一次实机测试请放在开阔桌面上，全程接电，并留意温度。

## 它解决什么问题

有些本地 Codex 任务要跑很久：编译、测试、批量处理文件，或者等本地服务完成。
人离开时合上屏幕，MacBook 通常会睡眠，任务也就停了。

Codex Lid Keeper 不会一直禁止睡眠。它只在下面几个条件同时满足时接管：

- Codex 还有任务在跑；
- MacBook 正在接电；
- 电量不低于安全线；
- 后台守护进程工作正常。

最后一个任务结束、拔掉电源、电量过低或心跳中断时，它都会退出接管，并恢复之前
记录的设置。

## 安全设计

- **Hook 不碰 sudo。** Hook 只把最少量的任务事件写进本地队列，然后立即返回。
- **多个任务分开记。** 同时跑几个 Codex 任务时，一个任务结束不会影响其他任务。
- **不擅自写回 0。** 修改前先记录 AC 模式下原本的 `disablesleep` 值，恢复时
  原样写回。
- **只改接电配置。** 电池模式的配置不会被修改。
- **有独立兜底。** root watchdog 发现心跳超时、断电或低电量时，会主动恢复。
- **租约会过期。** 即使结束事件丢了，也不会永久保持唤醒。
- **提权范围很窄。** sudoers 只放行 `power enable` 和 `power restore` 两条固定
  命令。
- **不保存聊天内容。** 提示词、模型回复、工具输入和工具输出都不会落盘。

更多细节见[架构说明](docs/ARCHITECTURE.md)。

## 目前做到了什么

- 非阻塞的 Codex 生命周期 Hook
- 支持并发任务的租约状态机
- 原子事件队列和崩溃重放保护
- 基于 IOKit 的接电与电量检测
- 由 root 保存的原设置记录
- 用户 LaunchAgent 与 root 恢复 LaunchDaemon
- `status`、`pause`、`resume`、`clear`、紧急恢复和卸载命令
- 35 项 Swift 自测、5 项 Hook 配置测试和隔离的 dry-run 集成测试

还没有菜单栏界面、签名 App、notarization、DMG 和自动更新。不同 Mac 型号、不同
macOS 版本的合盖表现，仍然需要实机验证。

## 使用条件

- macOS 13 或更高版本的 MacBook
- 安装了 Apple Command Line Tools，Swift 版本为 6
- 当前版本的 Codex，并且支持生命周期 Hook
- 安装时可以输入管理员密码

安装完成后，Codex 会要求你检查并信任新增的 command Hook。没有手动信任之前，
这些 Hook 不会运行。

## 先跑测试

下面这些命令不会改动真实的 `pmset`：

```bash
./scripts/build.sh
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py --binary .build/release/codex-lid-keeper
```

这个版本预期看到：

```text
35/35 self-tests passed
Ran 5 tests ... OK
non-blocking dry-run Hook lifecycle passed
```

集成测试使用临时目录和假的电源标记，不会开启真实的 sleep override。

## 安装

先读一遍安装脚本，再执行：

```bash
./scripts/install.sh
```

安装脚本会先重新构建并跑完自测，然后才申请管理员权限。它会安装：

1. `/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper`
2. 只允许两条固定命令的 sudoers 规则
3. root 恢复用的 LaunchDaemon
4. 当前用户的 LaunchAgent
5. 五个 Codex 生命周期 Hook

现有的 `~/.codex/hooks.json` 会先备份，再合并，不会整份覆盖。

安装结束后，在 Codex 里打开 `/hooks`，确认并信任新增的五个 Hook。

## 日常使用

查看状态：

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper status
```

可用命令：

```text
status [--json]      查看任务、待处理事件、电源状态和最近一次判断
pause                暂停自动接管，并恢复当前由本项目修改的设置
resume               重新启用自动接管
clear                清掉卡住的任务记录，不改变暂停状态
emergency-restore    立即暂停、清空任务并恢复设置
config show          查看当前配置
```

运行数据和日志保存在：

```text
~/Library/Application Support/CodexLidKeeper/
```

## 配置

第一次运行会生成 `config.json`：

- `minimumBatteryPercent`：最低电量，范围 `30...100`，默认 `30`
- `leaseDuration`：任务最长保留时间，范围 `60...86400` 秒，默认 `28800`
- `releaseDelay`：任务结束后的缓冲时间，范围 `0...300` 秒，默认 `20`
- `eventPollInterval`：事件队列检查间隔，范围 `0.25...5` 秒，默认 `1`
- `powerHeartbeatInterval`：电源心跳间隔，范围 `5...30` 秒，默认 `10`

“必须接电”和“电量至少 30%”是安全底线，配置只能调得更保守，不能关闭。
旧配置里的 `pollInterval` 会自动当作电源心跳间隔读取。

## 它是怎么工作的

```text
Codex Hook
    │ 只取任务 ID、事件、时间和项目名
    ▼
本地私有事件队列 ── Hook 立即返回 {}
    │
    ▼
后台进程更新任务租约
    │
    ├─ 有任务 + 接电 + 电量安全 ──> 保持合盖运行
    │
    └─ 无任务 / 拔电 / 低电量 ───> 恢复原设置
```

每条事件都会先写进权限为 `0600` 的独立文件，再原子提交。后台进程按时间顺序
处理，并记住已经处理过的事件 ID，所以中途崩溃后重新读取也不会重复生效。

队列最多放 4,096 条事件；单条最大 64 KiB；时间比当前系统快五分钟以上的事件
会被丢弃。空闲时后台进程只检查队列，不会每秒查询电源或反复改写状态文件。

真正修改电源前，root 辅助程序会把 AC 模式下原来的值写进：

```text
/var/db/com.zundu.codex-lid-keeper.power.json
```

只有本项目留下了这份记录，程序才会认为这项设置归自己负责。

## 第一次实机测试

不要上来就合盖。请按[完整测试指南](TESTING.md)依次完成：

1. 不安装的 dry-run 测试
2. 安装后的开盖测试
3. 并发任务、暂停、拔电和紧急恢复测试
4. 最后才做桌面环境下的受控合盖测试

合盖测试时：

- 放在无遮挡、通风好的桌面；
- 全程接电；
- 先只合盖两到五分钟；
- 开盖后检查任务进度、网络和机身温度；
- 任务结束后确认正常睡眠已经恢复。

每次 macOS 大版本升级后，都建议重新测试。

## 出问题先恢复

仓库目录内执行：

```bash
./scripts/emergency-restore.sh
```

安装后也可以直接执行：

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper emergency-restore
```

这条命令不依赖 `config.json` 是否正常。如果 root 所有权记录已经损坏，程序不会
猜原值，而是停下来报错。此时请先检查记录和 `pmset -g custom`。

## 卸载

```bash
./scripts/uninstall.sh
```

卸载脚本会先恢复由本项目修改的电源设置，再移除 Helper、sudoers、launchd 项和
Hook。日志与配置不会自动删除，脚本会把保留目录打印出来。

## 隐私

程序只保留任务识别和恢复所需的信息。它不会保存提示词、对话正文、模型回复、
工具参数或工具输出。

日志最大 1 MiB，轮转时只保留上一份。提交 Issue 前仍请自行检查日志，并删掉项目
名称、路径或其他不想公开的信息。

## 已知限制

- 依赖未公开的 macOS 设置，Apple 随时可能改掉。
- 合盖后的联网和散热表现会因机型而异。
- 当前 Helper 是本机从源码构建的，没有签名和 notarization。
- 还没有图形界面、通知、自动更新或机型兼容列表。
- 这是公开 Alpha，不建议无人值守运行。

## 参与测试和开发

- [测试指南](TESTING.md)
- [架构说明](docs/ARCHITECTURE.md)
- [贡献指南](CONTRIBUTING.md)
- [版本记录](CHANGELOG.md)
- [安全说明](SECURITY.zh-CN.md)

## 致谢

设计阶段参考了：

- [Lu233/CodexAwake](https://github.com/Lu233/CodexAwake)
- [Moarram/wake](https://github.com/Moarram/wake)
- [Ami3466/claude-awake](https://github.com/Ami3466/claude-awake)

仓库没有复制这些项目的源码。

## 许可证

[MIT License](LICENSE)
