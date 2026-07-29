# Changelog / 变更记录

All notable project changes are recorded here.

本文件记录项目的重要变化。

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
