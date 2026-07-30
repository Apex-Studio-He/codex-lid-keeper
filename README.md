# Codex Lid Keeper

English | [简体中文](README.zh-CN.md)

> **v0.2.1 App Alpha — MacBook testers wanted**
>
> If you can run a controlled closed-lid test on an open, well-ventilated
> desk, start with the [testing guide](TESTING.md), then share your Mac model,
> macOS version, and results through the
> [tester issue forms](https://github.com/Apex-Studio-He/codex-lid-keeper/issues/new/choose).

Keep local Codex work running after a MacBook lid closes, then restore the
previous sleep policy and display brightness when the final task ends.

![Codex Lid Keeper dashboard](docs/images/dashboard-zh.png)

![Battery guard settings](docs/images/settings-power-zh.png)

## What the app shows

- **Actual Codex activity.** Read-only rollout lifecycle markers detect new
  work immediately, turn-state logs cover compatibility fallback, and trusted
  Hooks provide a second durable lifecycle path.
- **Accurate concurrent counts.** Runtime observations and Hook leases are
  merged by Codex session, so two running tasks show `2` without double-counting
  the same task.
- **Live system power data.** AC state and battery charge come directly from
  macOS. If neither activity source is available, the task count shows `—`
  rather than sample data.
- **Two guard policies.** Run only on AC power (the default), or explicitly
  allow battery operation with a configurable charge floor.
- **Reversible display dimming.** The app saves the built-in display
  brightness, waits three seconds, dims it to minimum, and restores it after
  completion, cancellation, or app exit.
- **A native menu-bar app.** Check state, change power policy, prepare to close,
  or trigger emergency restore without keeping the main window open.
- **A four-step readiness rail.** Codex, power policy, battery safety, and
  recovery health must all be ready before closed-lid mode can be armed.

## Safety warning

This project relies on the undocumented macOS `pmset disablesleep` setting.
Apple may change or remove this behavior in any macOS update.

**Never put a running, closed MacBook in a bag, sleeve, drawer, bed, sofa, or
other poorly ventilated space.** Keep the first hardware test supervised on an
open desk and stop if the Mac becomes unusually warm.

## Install

Requirements: a MacBook running macOS 13 or later, Apple Command Line Tools, a
current Codex desktop build, and administrator access.

```bash
git clone https://github.com/Apex-Studio-He/codex-lid-keeper.git
cd codex-lid-keeper
./scripts/install.sh
```

The installer builds and tests the source, then:

1. installs `Codex Lid Keeper.app` in `/Applications`;
2. installs a fixed-function, root-owned power helper;
3. installs a per-user daemon and independent root watchdog;
4. backs up and merges five Codex Hooks without replacing unrelated Hooks;
5. adds an exact-command sudoers boundary; and
6. launches the app.

The administrator-password prompt appears in Terminal through the standard
macOS `sudo` flow, not inside the app. Codex Lid Keeper never reads or stores
the password.

If Codex reports changed Hook definitions, open `/hooks`, review the five
Codex Lid Keeper handlers, and trust them. The read-only runtime detector can
bootstrap tasks that were already running, while trusted Hooks remain the
stable lifecycle path for later Codex versions.

> This Alpha is built locally from source and ad-hoc signed. It does not yet
> have Developer ID signing or Apple notarization. Review the installer and
> [security model](SECURITY.md) before use.

## How activity tracking works

Tracking has two local inputs. First, a read-only detector follows only
`task_started`, `task_complete`, and `turn_id` lifecycle fields in recent
Codex rollouts, plus the working directory needed for the project label. A
minimal turn-state log query remains as a compatibility fallback. The detector
does not model or persist thread titles, prompts, responses, or tool payloads.
This makes new and already-running tasks visible without waiting for a later
progress log.

The app also consumes these Codex lifecycle events:

- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `Stop`
- `SessionEnd`

Each `session_id + turn_id` becomes a renewable task lease. Runtime and Hook
observations are deduplicated by session. Multiple local tasks remain
independent, and the final task must end before sleep is restored. A Hook only
queues a privacy-minimal event and immediately returns; it never waits for
`sudo` or power reconciliation.

Prompt text, model responses, tool inputs, and tool outputs are not persisted.

## Power policies

### AC only

The default. Closed-lid guarding activates only while external power is
present and charge is above the configured floor. Disconnecting AC restores
the project-owned sleep setting.

### AC or battery

An explicit advanced option. Work can continue after AC is disconnected, but
the helper restores sleep when charge falls below the selected threshold. The
UI accepts `30%...100%`, while the root watchdog keeps a non-configurable 30%
hard floor.

The helper captures AC and battery profiles separately and restores the exact
prior values. It never assumes the user's previous value was `0`.

## Recovery boundaries

Restoration occurs when:

- the final Codex task ends;
- the user pauses, clears tasks, or chooses emergency restore;
- live power no longer matches the selected policy;
- charge falls below the configured floor;
- a task lease expires;
- the user daemon stops heartbeating for two minutes; or
- the uninstaller runs.

The root-owned record lives at:

```text
/var/db/com.zundu.codex-lid-keeper.power.json
```

The helper restores only state backed by a valid ownership record. It refuses
to guess if that record is malformed.

## Build and test safely

These checks use fakes or an isolated dry-run home. They never enable the live
sleep override:

```bash
./scripts/build.sh
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py --binary .build/release/codex-lid-keeper
./scripts/build_app.sh
```

Current baseline:

```text
45/45 self-tests passed
Ran 5 tests ... OK
non-blocking dry-run Hook lifecycle passed
```

Coverage includes immediate three-task rollout detection, stale-log suppression
after task completion, Hook/runtime deduplication, strict event-spool capacity,
crash replay, AC and battery policies, exact prior-state restoration,
low-charge safety, watchdog expiry, and migration from older state. Physical
closed-lid networking, thermal behavior, and model compatibility remain manual
hardware tests.

## Emergency restore

Emergency restore is available in the main window, menu bar, and Settings. It
can also be run from the repository:

```bash
./scripts/emergency-restore.sh
```

or through the installed helper:

```bash
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" emergency-restore
```

It pauses automation, clears task leases, and restores project-owned sleep and
brightness state.

## Uninstall

```bash
./scripts/uninstall.sh
```

The uninstaller restores owned power state before removing the app, helper,
sudoers rule, launchd jobs, and project Hook handlers. User logs and
configuration are retained, and their location is printed.

## Project status

This is an experimental public Alpha, not an Apple or OpenAI product. It does
not yet provide:

- Developer ID signing and notarization;
- a DMG or automatic updater;
- a complete MacBook compatibility matrix; or
- guarantees for future macOS releases.

We especially need test results from:

- Apple Silicon and Intel MacBooks;
- macOS 13, 14, 15, and newer releases;
- AC-only and battery-capable policies;
- multiple concurrent Codex tasks; and
- closed-lid networking, progress, temperature, and final restoration.

## Resources

- [Bilingual testing guide / 双语测试指南](TESTING.md)
- [Architecture / 架构说明](docs/ARCHITECTURE.md)
- [Contributing / 参与贡献](CONTRIBUTING.md)
- [Changelog / 变更记录](CHANGELOG.md)
- [Security policy](SECURITY.md) |
  [安全说明](SECURITY.zh-CN.md)

## Acknowledgements and license

The design research was informed by
[CodexAwake](https://github.com/Lu233/CodexAwake),
[wake](https://github.com/Moarram/wake), and
[claude-awake](https://github.com/Ami3466/claude-awake).
No source from those projects is vendored here.

Licensed under the [MIT License](LICENSE).
