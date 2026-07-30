# Changelog / 变更记录

All notable project changes are recorded here.

本文件记录项目的重要变化。

## [0.2.2-app-alpha] - 2026-07-30

### English

#### Fixed

- A rollout `task_complete` marker now removes a matching Hook lease when the
  `Stop` Hook was missed, timed out, or had not yet been trusted. The guard no
  longer stays active for the remainder of the hard lease in that case.
- Completion cleanup is scoped to the exact `session_id + turn_id`. A
  completion from an older turn cannot remove newer work in the same Codex
  session.
- Live app status applies the same completion evidence immediately, without
  waiting for the next daemon state write.

#### Verification

- Native regression coverage increased to 48 self-tests.
- Added exact regressions for a missed `Stop` Hook, old-turn/new-turn
  isolation, and immediate UI status correction.

### 中文

#### 修复

- 即使 `Stop` Hook 因超时、尚未信任或其他原因漏送，只要 rollout 已写下
  `task_complete`，对应的 Hook 租约就会自动清掉，不会再多守护几个小时。
- 清理范围严格限定为同一个 `session_id + turn_id`。旧 turn 的结束信号不会
  误删同一 Codex 会话里后来开始的新任务。
- App 读取实时状态时也会立刻应用这条结束信号，不必等后台进程下一次写回状态。

#### 验证

- Swift 自测增加到 48 项。
- 新增“漏掉 Stop 后恢复”“旧 turn 不伤新 turn”和“界面立即纠正状态”三项
  精确回归。

## [0.2.1-app-alpha] - 2026-07-30

### English

#### Fixed

- New Codex turns now appear from rollout `task_started` markers instead of
  waiting for a later turn-state progress log. In the reported three-task
  case, the previous source lagged by about 75 seconds and temporarily showed
  `2`.
- Rollout `task_complete` is authoritative for the matching session, so a
  delayed log record cannot keep a finished task counted.
- Runtime, Hook, and fallback observations remain deduplicated by Codex
  session.

#### Privacy and verification

- Rollout scanning is read-only, limited to the final 4 MiB of recent files,
  and decodes only the lifecycle envelope, event type, and `turn_id`.
- Titles, prompts, responses, and tool payloads are not modeled or persisted.
- Native regression coverage increased to 45 self-tests, including the exact
  “three active tasks, log source sees two” case and completion suppression.

### 中文

#### 修复

- 新任务会直接跟随 rollout 的 `task_started` 出现，不再等下一条 turn 进度
  日志。用户反馈的三任务场景里，旧数据源晚了约 75 秒，所以界面曾短暂显示
  `2`。
- 同一任务一旦出现 `task_complete`，就会立即从计数里移除；即使旧日志还停留
  在“运行中”，也不会继续多算。
- rollout、Hook 和兼容日志仍按 Codex session 去重。

#### 隐私与验证

- rollout 只读检查仅限近期文件末尾 4 MiB，解码结构只有生命周期外层、
  事件类型和 `turn_id`。
- 任务标题、提示词、回复和工具内容不会建立字段，也不会写入状态或日志。
- Swift 自测增加到 45 项，新增“三个任务、日志只看见两个”和结束后压住滞后
  日志两项精确回归。

## [0.2.0-app-alpha] - 2026-07-30

### English

#### Added

- Native SwiftUI macOS app with a main dashboard, menu-bar panel, and Settings.
- Four-stage closed-lid readiness rail for Codex activity, power policy,
  charge safety, and recovery health.
- Explicit AC-only or AC-and-battery guard policies.
- Configurable 30–100% charge floor with an independent 30% root-watchdog
  minimum.
- Reversible built-in display dimming, including Apple Silicon support.
- Live task, AC, and battery reporting with no fabricated placeholder values.
- Read-only runtime detection for tasks already running before Hook
  installation, with session-level deduplication across both sources.
- Source-built `.app` packaging, `/Applications` installation, launch-at-login,
  notifications, and integration diagnostics.
- Strict concurrent event-spool capacity and new mode/restoration regressions.

#### Changed

- Root ownership now records mode plus prior AC and battery profiles
  independently.
- The sudo boundary now exposes three exact commands: AC enable, battery
  enable, and restore.
- The installer builds, installs, and launches the graphical app.
- Native regression coverage increased to 44 self-tests.

#### Still experimental

- The app is ad-hoc signed, not Developer ID signed or notarized.
- Closed-lid networking and thermal behavior still require per-model testing.
- `pmset disablesleep` and the Apple Silicon brightness fallback rely on
  undocumented macOS behavior.

### 中文

这一版把原来的命令行守护做成了能日常使用的 macOS 图形 App，同时补齐了用户
提出的接电 / 电池模式选择。

#### 新增

- 原生 SwiftUI 主窗口、菜单栏面板和设置页；
- Codex、电源策略、电量、恢复守护四项合盖检查；
- “仅接电”和“接电或电池”两种守护模式；
- 30%—100% 可调安全线，以及 root watchdog 不可降低的 30% 底线；
- 保存、调暗和恢复内置屏幕亮度，支持当前 Apple Silicon Mac；
- 只读补记安装前已经在跑的任务，并与 Hook 按 session 去重；
- 实时任务数、供电状态和系统电量，两条任务信号都不可用时显示 `—`；
- App 打包、安装到 `/Applications`、登录启动、通知与权限诊断；
- 并发事件队列上限修复，以及供电模式和原配置恢复回归测试。

#### 调整

- root 所有权记录现在分别保存 AC、电池原值和当前模式；
- sudoers 改为只放行“接电开启”“电池开启”“恢复”三条固定命令；
- 安装脚本会构建、安装并启动图形 App；
- Swift 自测增加到 44 项。

#### 仍需注意

- 当前只有 ad-hoc 签名，还没有 Developer ID 签名和 notarization；
- 合盖后的网络和散热仍需按机型实测；
- `pmset disablesleep` 与 Apple Silicon 亮度兼容层都依赖未公开的 macOS 行为。

## [0.1.0-alpha] - 2026-07-29

### English

#### Added

- Source-build macOS CLI and Swift core library.
- Non-blocking Codex Hooks for `UserPromptSubmit`, `PreToolUse`,
  `PostToolUse`, `Stop`, and `SessionEnd`.
- Atomic private event spool with replay IDs, ordering, malformed-event
  rejection, future-clock protection, a 4,096-event cap, and 512-event batches.
- Concurrent renewable leases with delayed release and eight-hour hard expiry.
- Native IOKit AC/battery checks and a fixed 30% watchdog safety floor.
- Root-owned prior-state record and AC-only `pmset -c disablesleep` changes.
- Exact-argument sudoers integration, user LaunchAgent, and root recovery
  LaunchDaemon.
- Status, pause, resume, clear, emergency restore, and uninstall commands.
- English and Simplified Chinese documentation, testing guide, contribution
  guide, security policy, architecture notes, and issue templates.
- Release/warnings-as-errors CI, 35 native self-tests, 5 Hook configuration
  tests, and an isolated non-blocking lifecycle test.

#### Safety

- Prompt and tool payloads are not persisted.
- Automated tests never enable the live sleep override.
- Power ownership is restored on no tasks, AC loss, low battery, stale
  heartbeat, pause, emergency restore, and uninstall.
- Idle operation avoids repeated IOKit reads and state-file writes.

#### Known limitations

- Experimental source-only Alpha; no signed app or notarized package.
- Uses undocumented macOS behavior.
- Real closed-lid, networking, and thermal behavior varies by hardware.
- No menu-bar UI, automatic updates, or compatibility guarantee.

### 中文

这是第一个公开测试版，先把最重要的链路跑通：Codex 有任务时接管合盖睡眠，
任务结束或条件不安全时恢复原设置。

#### 这一版有了什么

- 可以直接从源码构建的 Swift 6 CLI 和 Core；
- 覆盖五类 Codex 生命周期事件的非阻塞 Hook；
- 私有原子事件队列，支持排序、去重、崩溃重放和异常事件拦截；
- 最多 4,096 条待处理事件，每次最多处理 512 条；
- 多任务租约、任务结束缓冲和八小时强制过期；
- 用 IOKit 读取接电状态和电量；
- 修改前记录 AC 原值，恢复时原样写回；
- 只开放两条固定 sudo 命令；
- 用户 LaunchAgent 和独立的 root watchdog；
- 状态查看、暂停、恢复、清理、紧急恢复和卸载命令；
- 中英文说明、测试手册、贡献指南、架构文档和 Issue 模板；
- 35 项 Swift 自测、5 项 Hook 配置测试和隔离的 dry-run 集成测试。

#### 安全方面

- 不保存提示词、聊天正文或工具参数；
- 自动测试不会碰真实 `pmset`；
- 任务结束、拔电、低电量、心跳超时、手动暂停和卸载都会触发恢复；
- 完全空闲时不反复读 IOKit，也不一直刷写状态文件。

#### 还缺什么

- 暂时只有源码，没有签名 App 和 notarized 安装包；
- 依赖 macOS 没有公开文档的行为；
- 合盖后的联网和散热需要按机型实测；
- 还没有菜单栏界面、自动更新和兼容机型列表。

[0.1.0-alpha]: https://github.com/Apex-Studio-He/codex-lid-keeper/releases/tag/v0.1.0-alpha
[0.2.0-app-alpha]: https://github.com/Apex-Studio-He/codex-lid-keeper/releases/tag/v0.2.0-app-alpha
[0.2.1-app-alpha]: https://github.com/Apex-Studio-He/codex-lid-keeper/releases/tag/v0.2.1-app-alpha
[0.2.2-app-alpha]: https://github.com/Apex-Studio-He/codex-lid-keeper/releases/tag/v0.2.2-app-alpha
