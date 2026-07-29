# Codex Lid Keeper

[English](README.md) | [简体中文](README.zh-CN.md)

> **v0.1.0-alpha — source-only tester release**
>
> Start with the [testing guide](TESTING.md), review the
> [security model](SECURITY.md), and keep the emergency restore command nearby.
> This release is intentionally not distributed as an unsigned binary.

Codex Lid Keeper is an experimental macOS helper that keeps a MacBook running
with its lid closed while local Codex work is active, then restores the user's
previous closed-lid sleep setting after the final task ends.

It is intentionally conservative:

- AC power is mandatory.
- Battery below 30% forces restoration even while connected to power.
- Every task is a renewable lease with an eight-hour hard expiry.
- A root watchdog restores the prior setting if the user agent stops
  heartbeating for two minutes.
- Hooks return after atomically queuing a minimal lifecycle event; they never
  wait for `sudo` or power reconciliation.
- Hook payloads are reduced to session, turn, event, timestamp, and project
  identifiers. Prompt text and tool inputs are never stored.

> **Warning**
>
> This project uses the undocumented `pmset disablesleep` setting. Apple can
> change or remove that behavior in any macOS update. Never put a running,
> closed MacBook in a bag, sleeve, drawer, or other poorly ventilated space.

## Current scope

The repository contains a working headless MVP:

- non-blocking Codex lifecycle Hook adapter and crash-safe event spool
- concurrent task lease state machine
- native IOKit AC/battery checks
- root-owned sleep-setting ownership record
- noninteractive, exact-command sudo boundary
- launchd user agent and root recovery watchdog
- status, pause, resume, clear, and emergency restore commands
- safe Hook merge/unmerge scripts
- zero-dependency Swift self-tests and isolated dry-run integration tests

It does not yet include a menu-bar UI, signed app bundle, notarized installer,
DMG, or automatic updates. Real closed-lid behavior must still be acceptance
tested on each target Mac model and macOS version.

## Requirements

- A MacBook running macOS 13 or later
- Apple Command Line Tools with Swift 6
- A current Codex build with lifecycle Hooks
- An administrator account for installation

Codex requires the user to review and trust new or changed command Hooks before
they run.

## Build and test without changing power settings

These commands do not call privileged `pmset` operations:

```bash
swift build
swift run codex-lid-keeper-self-test
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py
```

The integration test uses an isolated temporary home and a dry-run power marker.

## Install

Review the source first, then run:

```bash
./scripts/install.sh
```

The installer builds and runs the self-tests before requesting administrator
access. It then:

1. installs a root-owned executable at
   `/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper`;
2. installs a sudoers rule that permits only `power enable` and `power restore`
   for that exact root-owned executable;
3. installs a root recovery watchdog in `/Library/LaunchDaemons`;
4. installs a user reconciliation agent in `~/Library/LaunchAgents`;
5. backs up and merges five handlers into `~/.codex/hooks.json`.

After installation, open `/hooks` in Codex, inspect the new definitions, and
trust them. Hooks whose definition has not been trusted are skipped by Codex.

Check the state with:

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper status
```

## Commands

```text
status [--json]      Show leases, queued events, power state, and latest decision
pause                Restore owned state and stop future activation
resume               Re-enable activation
clear                Clear stuck leases without changing pause/resume preference
emergency-restore    Pause, clear leases, and restore the previous setting
config show          Print bounded safety configuration
```

Runtime state and logs live in:

```text
~/Library/Application Support/CodexLidKeeper/
```

The generated `config.json` accepts:

- `minimumBatteryPercent`: `30...100`, default `30`
- `leaseDuration`: `60...86400` seconds, default `28800`
- `releaseDelay`: `0...300` seconds, default `20`
- `eventPollInterval`: `0.25...5` seconds, default `1`
- `powerHeartbeatInterval`: `5...30` seconds, default `10`

AC power cannot be disabled in this MVP. The root watchdog always enforces a
30% battery floor; configuration can make that threshold more conservative,
not less. Invalid configuration fails closed. An existing `pollInterval` value
is accepted as the legacy power-heartbeat interval during migration.

## How it works

```text
Codex lifecycle Hook
        │ decode only the required fields
        ▼
private atomic event spool ── Hook returns {}
        │
        │ user agent drains up to 512 events per pass
        ▼
idempotent lease reducer ──> atomic user state
        │
        │ AC + safe battery + active lease
        ▼
root-owned power helper ──> pmset -c disablesleep 1

No leases / unplugged / low battery / stale heartbeat
        │
        ▼
restore captured prior AC state
```

Each event is atomically committed as a private `0600` file, with both the file
and containing directory synchronized before the Hook returns. The daemon polls
the spool once per second, processes events in timestamp order, and remembers
event IDs so a crash replay cannot apply an event twice. The spool accepts at
most 4,096 pending files and rejects malformed, oversized, or more than
five-minutes-future-dated records. `status` shows the pending count so a stopped
or unhealthy daemon is visible.

The helper writes `/var/db/com.zundu.codex-lid-keeper.power.json` before changing
the AC-power profile. That record captures whether `disablesleep` was already
enabled for AC power. The battery profile is never modified, and restoration
never blindly assumes the prior AC value was `0`.

The daemon reconciles once at startup, immediately after an applied event, and
every ten seconds while leases or owned power need maintenance. When fully
idle, its one-second queue check does not query IOKit or rewrite `state.json`.
Privileged ownership heartbeats are likewise limited to once every ten seconds.
A separate root LaunchDaemon checks once per minute and restores if:

- the heartbeat is at least two minutes old;
- AC power is missing or cannot be determined; or
- the battery is below the default safety threshold.

## Manual closed-lid acceptance test

Automated tests intentionally never change the live sleep setting. Test on a
desk with unobstructed ventilation:

1. Connect the original or an appropriate power adapter.
2. Start a Codex task that performs observable local work for several minutes.
3. Confirm `status` reports an active task and `Sleep override owned: yes`.
4. Close the lid for two to five minutes.
5. Reopen it and verify the Codex task and local timestamps advanced while
   closed.
6. Let the final task finish, wait at least 20 seconds, and confirm `status`
   reports zero tasks and no owned override.
7. Close the lid again and confirm normal system sleep returns.

Repeat this after significant macOS upgrades.

## Emergency restore

Normally:

```bash
./scripts/emergency-restore.sh
```

or:

```bash
/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper emergency-restore
```

If the ownership record is malformed, the helper refuses to guess. Inspect
both the record and `pmset -g custom` before making a manual change.
The emergency command itself does not depend on a valid `config.json`.

## Uninstall

```bash
./scripts/uninstall.sh
```

Uninstallation restores the owned power state before removing the helper,
sudoers rule, launchd jobs, and Hook handlers. It preserves user logs and
configuration and prints their path.

## Security and privacy

See [SECURITY.md](SECURITY.md). The important boundaries are:

- the sudo-authorized executable and its parent directory are root-owned;
- sudoers permits only two exact argument vectors;
- the root ownership marker is not user-writable;
- the Hook is fail-open for Codex work but the power watchdog fails safe;
- no prompt, transcript, tool input, or tool output is persisted.

The activity log rotates at 1 MiB and retains one previous file.

## Status and limitations

This is experimental software, not an Apple or OpenAI product. In particular:

- `pmset disablesleep` is undocumented.
- Physical closed-lid networking and thermal behavior vary by hardware.
- A signed privileged helper using Apple's Service Management APIs would be a
  stronger distribution boundary than this source-build MVP.
- There is no claim of compatibility until the manual acceptance test passes
on the target Mac.

## Tester and contributor resources

- [Bilingual testing guide / 双语测试指南](TESTING.md)
- [Architecture / 架构说明](docs/ARCHITECTURE.md)
- [Contributing / 参与贡献](CONTRIBUTING.md)
- [Changelog / 变更记录](CHANGELOG.md)
- [Security policy](SECURITY.md) |
  [安全策略（中文）](SECURITY.zh-CN.md)

## Acknowledgements

The design research was informed by:

- [Lu233/CodexAwake](https://github.com/Lu233/CodexAwake)
- [Moarram/wake](https://github.com/Moarram/wake)
- [Ami3466/claude-awake](https://github.com/Ami3466/claude-awake)

No source from those projects is vendored here.

## License

MIT. See [LICENSE](LICENSE).
