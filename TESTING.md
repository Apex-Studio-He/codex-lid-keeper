# Alpha Testing Guide / Alpha 测试指南

[English](#english) | [简体中文](#简体中文)

This guide is for `v0.1.0-alpha`. The release is source-only and experimental.
It modifies a privileged, undocumented macOS power setting after installation.

---

## English

### Safety rules

- Test on a desk or another hard, open, well-ventilated surface.
- Keep the MacBook connected to an appropriate power adapter.
- Never test inside a bag, sleeve, drawer, bed, sofa, or enclosed shelf.
- Do not leave the first test unattended.
- Save the emergency restore command before installing.
- Stop if the Mac becomes unusually warm, power behavior is unclear, or the
  ownership record cannot be decoded.

Emergency restore:

```bash
./scripts/emergency-restore.sh
```

Installed-path fallback:

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper emergency-restore
```

### What this Alpha is trying to learn

We need real-hardware evidence for:

1. whether local Codex work advances with the lid closed;
2. whether networking remains usable on different MacBook models;
3. whether the previous AC `disablesleep` state is restored reliably;
4. whether launchd and Hook behavior differs across macOS releases;
5. whether thermal behavior stays acceptable on an open desk.

This release does **not** ask testers to validate operation in a bag or other
enclosed environment. That use is explicitly unsupported.

### Prerequisites

- MacBook with macOS 13 or newer
- Apple Command Line Tools with Swift 6
- a current Codex build with lifecycle Hooks
- administrator access for installation
- a test task whose progress can be observed locally

Record these before reporting:

```bash
sw_vers
uname -m
swift --version
codex --version
```

Do not post your full Hook file, prompts, transcripts, or unsanitized paths.

### Phase A — non-privileged preflight

Run all checks before installation:

```bash
./scripts/build.sh
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py --binary .build/release/codex-lid-keeper
```

Expected results for this release:

- `35/35 self-tests passed`
- `Ran 5 tests ... OK`
- `non-blocking dry-run Hook lifecycle passed`

These tests use fakes or an isolated dry-run home and do not enable the live
sleep override.

Capture the current power policy for comparison:

```bash
pmset -g custom
```

If `disablesleep 1` was already present under the AC profile, note that fact.
The project is designed to preserve it rather than force it to `0`.

### Phase B — review and install

Review at least:

- `scripts/install.sh`
- `scripts/uninstall.sh`
- `scripts/hooks_config.py`
- `Resources/com.zundu.codex-lid-keeper.agent.plist`
- `Resources/com.zundu.codex-lid-keeper.recovery.plist`
- `SECURITY.md`

Then install:

```bash
./scripts/install.sh
```

The installer builds from source, runs self-tests, and then installs:

- a root-owned helper in `/Library/PrivilegedHelperTools`;
- an exact-command sudoers rule;
- a root recovery LaunchDaemon;
- a per-user reconciliation LaunchAgent;
- five merged Codex lifecycle Hooks.

Open `/hooks` in Codex after installation. Review and trust the new Hook
definitions. Codex skips untrusted command Hooks.

### Phase C — open-lid functional matrix

Use:

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper status
```

#### T1. Single task lifecycle

1. Start one Codex task.
2. Confirm `Active tasks: 1`.
3. Confirm `Sleep override owned: yes`.
4. Let the task finish.
5. Wait at least 20 seconds.
6. Confirm zero active tasks and `Sleep override owned: no`.

#### T2. Parallel turns

1. Start two overlapping Codex tasks.
2. Confirm two active leases.
3. Finish one task and confirm ownership remains active.
4. Finish the second task and confirm ownership is restored only afterward.

#### T3. Pause, resume, and clear

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper pause
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper resume
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper clear
```

Verify that `pause` restores owned power, `resume` allows later activation, and
`clear` removes stuck leases without silently changing the pause preference.

#### T4. AC removal

While a lease is active, disconnect external power. Within the maintenance
window, ownership should be restored and status should report battery power.
Reconnect power before continuing. Do not perform the closed-lid test on
battery.

#### T5. Emergency recovery

With an active test lease, run:

```bash
./scripts/emergency-restore.sh
```

Confirm automation is paused, leases are cleared, and ownership is no longer
reported.

### Phase D — controlled closed-lid test

Only continue after Phase C passes.

1. Place the MacBook on an open desk with unobstructed ventilation.
2. Connect an appropriate power adapter.
3. Start a Codex task that writes timestamps or other observable progress for
   at least five minutes.
4. Confirm status reports an active lease and owned override.
5. Close the lid for two to five minutes.
6. Reopen it and verify the task progressed during the closed interval.
7. Check temperature and networking behavior.
8. Let the final task finish and wait at least 20 seconds.
9. Confirm ownership is no longer reported.
10. Close the lid again and verify normal sleep returns.

Repeat after major macOS updates. A pass on one model does not prove support for
all models.

### Useful diagnostic output

Sanitize paths and identifiers before posting:

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper status --json
pmset -g custom
launchctl print "gui/$(id -u)/com.zundu.codex-lid-keeper.agent"
sudo launchctl print system/com.zundu.codex-lid-keeper.recovery
```

Logs are stored in:

```text
~/Library/Application Support/CodexLidKeeper/keeper.log
```

The application does not intentionally store prompts or tool payloads, but
review every attachment before uploading it.

### Bug report checklist

Include:

- Mac model or model identifier
- macOS version and architecture
- Codex version
- whether AC power was connected
- battery percentage
- test case (`T1`–`T5` or closed-lid)
- expected and observed behavior
- sanitized status output
- whether emergency restore worked
- whether live power settings were changed

Use the repository bug-report template. Report security-sensitive issues
privately through GitHub Security Advisories.

### Uninstall

```bash
./scripts/uninstall.sh
```

The script restores owned power before removing system integration. It retains
the user data directory and prints its location.

---

## 简体中文

### 安全规则

- 只在桌面等坚硬、开放且通风良好的表面测试。
- 使用规格合适的电源适配器，并保持接电。
- 禁止在包、内胆包、抽屉、床、沙发或封闭置物架中测试。
- 第一次测试不能无人看管。
- 安装前先保存紧急恢复命令。
- 如果机身异常发热、电源行为不明确或所有权记录无法解析，立即停止测试。

紧急恢复：

```bash
./scripts/emergency-restore.sh
```

安装路径备用命令：

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper emergency-restore
```

### Alpha 测试需要回答什么

我们需要收集以下真实硬件信息：

1. 合盖时本地 Codex 任务是否继续推进；
2. 不同 MacBook 型号合盖后的网络是否可用；
3. 原来的 AC `disablesleep` 状态能否可靠恢复；
4. 不同 macOS 版本的 launchd 与 Hook 行为是否不同；
5. 放在开放桌面时散热是否可接受。

本版本明确不支持在包或其他封闭环境中运行。

### 前置条件

- macOS 13 或更高版本的 MacBook
- 带 Swift 6 的 Apple Command Line Tools
- 支持生命周期 Hooks 的当前 Codex
- 安装时可使用管理员权限
- 一个能从本地观察进度的测试任务

报告问题前记录：

```bash
sw_vers
uname -m
swift --version
codex --version
```

不要公开完整 Hook 文件、提示词、对话内容或未经清理的个人路径。

### 阶段 A — 非特权预检

安装前执行：

```bash
./scripts/build.sh
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py --binary .build/release/codex-lid-keeper
```

本版本预期看到：

- `35/35 self-tests passed`
- `Ran 5 tests ... OK`
- `non-blocking dry-run Hook lifecycle passed`

这些测试只使用 fake 或隔离的 dry-run home，不会开启真实睡眠 override。

记录安装前的电源配置：

```bash
pmset -g custom
```

如果 AC 配置中原本已有 `disablesleep 1`，请在报告中注明。本项目应保留原值，
而不是强制写回 `0`。

### 阶段 B — 检查并安装

至少检查：

- `scripts/install.sh`
- `scripts/uninstall.sh`
- `scripts/hooks_config.py`
- 两个 `Resources/*.plist`
- `SECURITY.zh-CN.md`

然后运行：

```bash
./scripts/install.sh
```

安装后在 Codex 中打开 `/hooks`，检查并信任新增 Hook。未经信任的 command Hook
会被 Codex 跳过。

### 阶段 C — 开盖功能矩阵

查看状态：

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper status
```

#### T1. 单任务生命周期

启动一个任务，确认活跃任务数为 1 且拥有 sleep override；任务结束后等待至少
20 秒，确认任务数为零且 override 已恢复。

#### T2. 并行任务

启动两个重叠任务。第一个结束时 override 必须保持；第二个也结束后才能恢复。

#### T3. 暂停、恢复和清理

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper pause
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper resume
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper clear
```

确认 `pause` 会恢复电源，`resume` 允许之后重新激活，`clear` 清除卡住租约但不
偷偷改变暂停偏好。

#### T4. 拔掉交流电

活跃租约存在时拔掉外接电源。维护周期内应恢复 override，并显示正在使用电池。
继续测试前重新接电；禁止在电池模式下执行合盖测试。

#### T5. 紧急恢复

存在测试租约时执行：

```bash
./scripts/emergency-restore.sh
```

确认自动化已暂停、租约已清除且不再拥有 override。

### 阶段 D — 受控合盖测试

只有阶段 C 全部通过后才能继续：

1. 把 MacBook 放在无遮挡的开放桌面。
2. 连接规格合适的电源。
3. 启动一个至少运行五分钟、会写时间戳或产生其他可观察进度的任务。
4. 确认状态显示活跃租约和已拥有 override。
5. 合盖两到五分钟。
6. 开盖，确认任务在合盖期间继续推进。
7. 检查温度和网络表现。
8. 等最后一个任务结束后再等待至少 20 秒。
9. 确认 override 已恢复。
10. 再次合盖，确认正常睡眠恢复。

重大 macOS 更新后应重新测试。单一机型通过不代表所有机型兼容。

### 诊断信息与问题报告

上传前清理路径和标识符：

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper status --json
pmset -g custom
launchctl print "gui/$(id -u)/com.zundu.codex-lid-keeper.agent"
sudo launchctl print system/com.zundu.codex-lid-keeper.recovery
```

日志位于：

```text
~/Library/Application Support/CodexLidKeeper/keeper.log
```

报告中请包含 Mac 型号、macOS/Codex 版本、是否接电、电量、测试编号、预期与
实际行为、清理后的状态输出、紧急恢复是否成功，以及真实电源设置是否变化。

安全问题请使用 GitHub Security Advisory 私下报告。

### 卸载

```bash
./scripts/uninstall.sh
```

脚本会先恢复本项目拥有的电源状态，再移除系统集成。用户数据目录会保留并输出路径。
