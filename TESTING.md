# Alpha Testing Guide / Alpha 测试指南

[English](#english) | [中文](#中文测试说明)

This guide is for `v0.2.2-app-alpha`. The release builds a native app from
source and remains experimental. It modifies a privileged, undocumented macOS
power setting after installation.

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
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" emergency-restore
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
./scripts/build_app.sh
```

Expected results for this release:

- `48/48 self-tests passed`
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
- `Codex Lid Keeper.app` in `/Applications`;
- five merged Codex lifecycle Hooks.

Open `/hooks` in Codex after installation. Review and trust the new Hook
definitions. Codex skips untrusted command Hooks.

### Phase C — open-lid functional matrix

Use:

```bash
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" status
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
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" pause
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" resume
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" clear
```

Verify that `pause` restores owned power, `resume` allows later activation, and
`clear` removes stuck leases without silently changing the pause preference.

#### T4. Power-policy switching

1. Select **AC only**, start a task, then disconnect external power. Within the
   maintenance window, ownership should be restored and the app should report
   battery power.
2. Reconnect power, select **AC or battery**, and confirm the active task can
   remain guarded after AC is disconnected while charge is above the selected
   floor.
3. Set the floor above the current charge and confirm ownership is restored.
4. Reconnect power and return to **AC only** before the first closed-lid test.

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
3. Keep the app in **AC only** mode for the first hardware test.
4. Start a Codex task that writes timestamps or other observable progress for
   at least five minutes.
5. Confirm the app reports an active lease, live battery percentage, and an
   owned override.
6. Choose **Dim and prepare to close**, confirm the display dims, then close
   the lid for two to five minutes.
7. Reopen it and verify the task progressed during the closed interval.
8. Check temperature and networking behavior.
9. Let the final task finish and wait at least 20 seconds.
10. Confirm ownership is no longer reported and brightness was restored.
11. Close the lid again and verify normal sleep returns.

Repeat after major macOS updates. A pass on one model does not prove support for
all models.

### Useful diagnostic output

Sanitize paths and identifiers before posting:

```bash
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" status --json
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

## 中文测试说明

### 先把底线说清楚

- MacBook 要放在坚硬、平整、四周通风的桌面上。
- 全程接一个规格合适的电源适配器。
- 不要在背包、内胆包、抽屉、床、沙发或封闭柜子里试。
- 第一次测试请人在旁边看着。
- 安装前先把紧急恢复命令复制到手边。
- 发现机身明显发热、电源状态说不清，或者所有权记录报错，立刻停止。

紧急恢复命令：

```bash
./scripts/emergency-restore.sh
```

如果已经安装，也可以执行：

```bash
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" emergency-restore
```

### 我们想从 Alpha 测试里确认什么

自动测试已经覆盖了状态机和恢复逻辑，但下面这些事情必须靠真实机器才能知道：

1. 合盖以后，本地 Codex 任务是不是真的还在往前跑；
2. 不同 MacBook 的网络连接能不能保持；
3. 任务结束后，原来的 AC 睡眠设置能不能完整恢复；
4. 不同 macOS 版本上的 Hook 和 launchd 是否有差异；
5. 在开放桌面上运行时，温度是否正常。

“塞进包里继续跑”不在测试范围内，也不会得到支持。

### 测试前准备

你需要：

- macOS 13 或更高版本的 MacBook
- Swift 6 和 Apple Command Line Tools
- 支持生命周期 Hook 的 Codex
- 安装时可以输入管理员密码
- 一个能看出进度的测试任务，例如持续写时间戳、编译或跑测试

先记下环境信息，后面反馈问题时会用到：

```bash
sw_vers
uname -m
swift --version
codex --version
```

不要把完整 Hook 文件、提示词、聊天内容或没有打码的个人路径发到公开 Issue。

### 第一步：安装前先跑自测

```bash
./scripts/build.sh
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py --binary .build/release/codex-lid-keeper
./scripts/build_app.sh
```

这个版本正常情况下会看到：

- `48/48 self-tests passed`
- `Ran 5 tests ... OK`
- `non-blocking dry-run Hook lifecycle passed`

这些命令只会使用 fake 和临时目录，不会去改真实的 `pmset`。

再把安装前的电源配置记下来：

```bash
pmset -g custom
```

如果 AC 那一段本来就有 `disablesleep 1`，反馈时请注明。程序应该保留这个原值，
而不是卸载时强行改成 `0`。

### 第二步：看过代码再安装

建议至少看一遍：

- `scripts/install.sh`
- `scripts/uninstall.sh`
- `scripts/hooks_config.py`
- `Resources/` 里的两个 plist
- [安全说明](SECURITY.zh-CN.md)

确认没有问题后再运行：

```bash
./scripts/install.sh
```

脚本会把图形化 App 安装到 `/Applications`，同时安装固定功能 Helper、用户
LaunchAgent、root watchdog 和五个 Codex 生命周期 Hook。

安装完成后，在 Codex 里输入 `/hooks`。你会看到五个新增 Hook，需要逐个确认并
信任；不信任的话，Codex 不会执行它们。

### 第三步：先别合盖

先用下面的命令观察状态：

```bash
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" status
```

#### T1：单个任务

1. 启动一个 Codex 任务。
2. 确认 `Active tasks: 1`。
3. 确认 `Sleep override owned: yes`。
4. 等任务结束，再等至少 20 秒。
5. 确认任务数回到 0，`Sleep override owned` 变成 `no`。

#### T2：同时跑两个任务

1. 让两个 Codex 任务有一段重叠时间。
2. 确认状态里能看到两个任务。
3. 先结束其中一个，睡眠接管应该继续保持。
4. 第二个也结束后，才应该恢复系统原来的设置。

#### T3：暂停、恢复和清理

```bash
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" pause
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" resume
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" clear
```

- `pause` 应该立即退出当前接管；
- `resume` 之后，新任务应该可以再次触发；
- `clear` 只清理卡住的任务记录，不应该擅自切换暂停状态。

#### T4：切换供电策略

1. 先选“仅接电”，保持一个任务在运行，然后拔掉外接电源。十秒左右，程序应该
   退出睡眠接管，界面显示正在使用电池。
2. 重新接电，改成“接电或电池”，再次拔电。在电量高于安全线时，守护应该继续。
3. 把最低电量调到高于当前电量，确认程序会退出接管。
4. 测完重新接电，并把策略切回“仅接电”，再做第一次合盖测试。

#### T5：紧急恢复

保持一个测试任务在运行，然后执行：

```bash
./scripts/emergency-restore.sh
```

确认三件事：自动运行已暂停、任务记录已清空、睡眠设置已经恢复。

### 第四步：再做合盖测试

前面的 T1—T5 全部正常，才能继续：

1. 把 MacBook 放在通风无遮挡的桌面上。
2. 接好电源。
3. 第一次测试保持“仅接电”模式。
4. 启动一个至少持续五分钟、能看出进度的 Codex 任务。
5. 确认 App 显示真实任务数、电量和“正在守护”。
6. 点击“调暗并准备合盖”，确认屏幕变暗后合盖两到五分钟。
7. 开盖，检查任务是否在这段时间继续推进。
8. 检查网络是否正常，机身有没有异常发热。
9. 等最后一个任务结束，再等至少 20 秒。
10. 确认睡眠接管已经退出，屏幕亮度也恢复了。
11. 再次合盖，确认 MacBook 恢复正常睡眠。

macOS 大版本升级后建议重新测一次。一台机器通过，不代表所有机型都没问题。

### 反馈问题时带上这些信息

下面几条命令通常够用。贴到 Issue 前，先把路径和 ID 打码：

```bash
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" status --json
pmset -g custom
launchctl print "gui/$(id -u)/com.zundu.codex-lid-keeper.agent"
sudo launchctl print system/com.zundu.codex-lid-keeper.recovery
```

日志在：

```text
~/Library/Application Support/CodexLidKeeper/keeper.log
```

Issue 里请写清楚：

- Mac 型号、macOS 版本、芯片架构和 Codex 版本
- 当时是否接电、电量是多少
- 做到了 T1—T5 的哪一步，还是合盖测试
- 你原本期待什么，实际发生了什么
- 打码后的 `status --json`
- 紧急恢复有没有成功
- `pmset` 有没有出现意外变化

程序不会主动记录提示词和工具参数，但上传日志前仍要自己检查一遍。
安全漏洞请通过 GitHub Security Advisory 私下报告。

### 卸载

```bash
./scripts/uninstall.sh
```

卸载脚本会先恢复由本项目修改的电源设置，再移除 Helper、sudoers、launchd 项和
Hook。日志与配置会保留，脚本会把目录位置打印出来。
