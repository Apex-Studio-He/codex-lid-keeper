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

### 简体中文

#### 新增

- 可从源码构建的 macOS CLI 与 Swift 核心库。
- 对五类 Codex 生命周期事件提供非阻塞 Hook。
- 私有原子事件队列，支持重放 ID、排序、畸形事件拒绝、未来时间保护、4,096
  条容量限制和每批 512 条处理。
- 支持并行任务、延迟释放和八小时硬过期的可续期租约。
- 原生 IOKit 电源检测与 root watchdog 的 30% 固定电量底线。
- root 所有的原状态记录，只修改 AC 配置的 `pmset -c disablesleep`。
- 精确参数 sudoers、用户 LaunchAgent 和 root 恢复 LaunchDaemon。
- 状态、暂停、恢复、清理、紧急恢复与卸载命令。
- 中英文 README、测试指南、贡献指南、安全策略、架构文档与 Issue 模板。
- release 零警告 CI、35 项 Swift 自测、5 项 Hook 测试和隔离生命周期测试。

#### 安全

- 不持久化提示词和工具载荷。
- 自动测试不会开启真实 sleep override。
- 无任务、拔电、低电量、心跳过期、暂停、紧急恢复和卸载时都会恢复本项目拥有的状态。
- 空闲时不会反复读取 IOKit 或写入状态文件。

#### 已知限制

- 仅源码实验 Alpha，没有签名 App 或 notarization。
- 依赖未公开的 macOS 行为。
- 合盖、网络和散热表现会随硬件变化。
- 没有菜单栏 UI、自动更新或兼容性保证。

[0.1.0-alpha]: https://github.com/Apex-Studio-He/codex-lid-keeper/releases/tag/v0.1.0-alpha
