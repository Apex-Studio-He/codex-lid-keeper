# Codex Lid Keeper

English | [简体中文](README.zh-CN.md)

[![CI](https://github.com/Apex-Studio-He/codex-lid-keeper/actions/workflows/ci.yml/badge.svg)](https://github.com/Apex-Studio-He/codex-lid-keeper/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/Apex-Studio-He/codex-lid-keeper?include_prereleases)](https://github.com/Apex-Studio-He/codex-lid-keeper/releases/tag/v0.3.0-app-alpha)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111820)](https://github.com/Apex-Studio-He/codex-lid-keeper)
[![MIT](https://img.shields.io/badge/license-MIT-2388ff)](LICENSE)

![Codex Lid Keeper — a guard that follows the task](docs/images/social-preview.jpg)

> **v0.3.0 Public Alpha — MacBook testers wanted**
>
> Codex Lid Keeper is ready for careful testing, not unattended deployment.
> Start on an open, hard, well-ventilated desk and read the
> [testing guide](TESTING.md) before closing the lid.

Codex Lid Keeper is a native macOS app that follows actual local Codex work.
When eligible tasks are active, it can keep the MacBook running after lid
close. After the final task—or when a safety boundary fails—it restores the
previous sleep policy and saved display brightness.

This is deliberately narrower than a general keep-awake toggle: the guard
starts and stops with Codex task lifecycle.

## Download

The v0.3.0 DMG contains a Universal app for Apple Silicon and Intel, the
complete system-component installer, an uninstaller, and bilingual safety
notes.

- [Download the Universal DMG](https://github.com/Apex-Studio-He/codex-lid-keeper/releases/download/v0.3.0-app-alpha/Codex-Lid-Keeper-v0.3.0-universal.dmg)
- [Download SHA256SUMS](https://github.com/Apex-Studio-He/codex-lid-keeper/releases/download/v0.3.0-app-alpha/SHA256SUMS)
- [Open the v0.3.0 release notes](https://github.com/Apex-Studio-He/codex-lid-keeper/releases/tag/v0.3.0-app-alpha)

Verify both files from the same directory:

```bash
shasum -a 256 -c SHA256SUMS
```

Then:

1. open the DMG;
2. Control-click **Install Codex Lid Keeper.command** and choose **Open**;
3. let Terminal request administrator access through standard macOS `sudo`;
4. open `/hooks` in Codex, review the five lifecycle Hooks, and trust them.

Do not drag only the app into `/Applications`. The graphical app also needs
the fixed-function Helper, recovery watchdog, user agent, exact sudoers rule,
and Codex Hooks. The included installer places all of them together.

### Gatekeeper disclosure

The app is ad-hoc signed so macOS can check the bundle's internal signature
structure, but that signature does not authenticate the publisher. v0.3.0 is
**not** Developer ID signed or Apple-notarized. macOS will therefore warn
before the first launch. Use Control-click → Open for this Alpha only after
reviewing the source, GitHub Release checksum, and
[security model](SECURITY.md). Never disable Gatekeeper system-wide.

The password prompt belongs to Terminal and `sudo`; there is intentionally no
username or password field inside the app. Codex Lid Keeper cannot read or
store that password.

## Why task awareness matters

![Codex-aware lifecycle](docs/images/gallery-01-hero.jpg)

- **Actual activity, not an open window.** Recent read-only rollout lifecycle
  markers detect new and already-running work. Trusted Hooks provide an
  independent durable path.
- **Concurrent counts are deduplicated.** Runtime observations and Hook leases
  are merged by Codex session, so the same task is not counted twice.
- **A missed completion Hook can heal.** A matching rollout
  `task_complete` clears only that exact `session_id + turn_id`; newer work in
  the same session remains protected.
- **The final task owns the finish line.** One task ending does not restore
  sleep while another eligible task remains active.
- **Unavailable data is not invented.** If both local activity sources are
  unavailable, the UI displays `—`.

## Power and recovery boundaries

![Power and recovery settings](docs/images/gallery-02-safety.jpg)

- **AC only** is the default.
- **AC or battery** is explicit opt-in, with a configurable 30–100% charge
  floor.
- The independent root watchdog enforces a non-configurable 30% minimum.
- “Ready to close” requires the recovery job to be loaded, the user Agent to
  be running with a live PID and held daemon lock, and the root power heartbeat
  to be fresh. The app checks again immediately before display dimming.
- AC and battery profiles are captured separately and restored to their exact
  previous values.
- The built-in display can be saved, dimmed after a three-second countdown,
  and restored after completion, cancellation, or app exit.
- Main window, menu bar, and Settings all expose emergency restore.

Restoration runs when:

- the final task ends;
- the user pauses, clears tasks, or chooses emergency restore;
- current power no longer matches the selected policy;
- charge falls below the configured floor;
- a lease expires;
- the user daemon stops heartbeating for two minutes; or
- the uninstaller runs.

## Safety warning

This project relies on the undocumented macOS `pmset disablesleep` setting.
Apple may change or remove this behavior in a future update.

**Never put a running, closed MacBook in a bag, sleeve, drawer, bed, sofa, or
other poorly ventilated space.** Keep the first test supervised on an open
desk. Stop if the machine becomes unusually warm or power behavior is unclear.

Physical closed-lid networking, temperature, and model compatibility remain
hardware-test questions; the automated suite does not prove them.

## Privacy boundary

The app does not model or persist prompt text, model responses, tool inputs,
or tool outputs.

Its read-only runtime detector selects only recent thread identity, rollout
path, working directory, and update/archive metadata. It examines at most the
final 4 MiB of each recent rollout and decodes only lifecycle envelope type,
`task_started` / `task_complete`, and `turn_id`. Full paths are reduced to the
final project-directory component before entering Keeper state.

Hooks decode only:

- `session_id`
- `turn_id`
- `cwd` (reduced to the final component)
- `hook_event_name`

See [SECURITY.md](SECURITY.md) for the complete privilege and data model.

## What gets installed

The bundled installer validates its app identifier, plist files, architecture,
and code-signature integrity before asking for administrator access. It then
installs:

- `/Applications/Codex Lid Keeper.app`;
- a root-owned fixed-function helper under
  `/Library/PrivilegedHelperTools`;
- a root recovery LaunchDaemon;
- a per-user reconciliation LaunchAgent;
- an exact-command sudoers rule; and
- five merged Codex lifecycle Hooks.

Hook installation is implemented natively in Swift. Release users do not need
Python, Swift, Xcode, or Command Line Tools.

## Build from source

Source development requires macOS 13+, Swift 6 Command Line Tools, a current
Codex build, and administrator access for live installation.

```bash
git clone https://github.com/Apex-Studio-He/codex-lid-keeper.git
cd codex-lid-keeper
./scripts/build.sh
/usr/bin/python3 scripts/test_hooks_config.py
/usr/bin/python3 scripts/test_e2e.py --binary .build/release/codex-lid-keeper
./scripts/build_distribution.sh
```

Install the locally built app and components:

```bash
./scripts/install.sh
```

Current automated baseline:

```text
58/58 native self-tests passed
Ran 8 Hook compatibility tests ... OK
non-blocking dry-run Hook lifecycle passed
Universal DMG verification passed
```

Tests use fakes or an isolated home and never enable the live sleep override.
Coverage includes immediate three-task detection, exact missed-`Stop`
recovery, new-turn isolation, Hook/runtime deduplication, event capacity and
replay, AC/battery policy, prior-state restoration, low charge, watchdog
expiry, native Hook configuration, and state migration.

## UI overview

[Watch the 29-second UI screenshot overview](docs/demo/codex-lid-keeper-ui-walkthrough.mp4).

It is made from real interface screenshots and summarizes the safety controls;
it is **not** a physical closed-lid test video. A valid hardware demonstration
must show a continuous supervised lid close, observable task progress, and
final restoration.

## Emergency restore

From an installed app:

```bash
"/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper" emergency-restore
```

From a source checkout:

```bash
./scripts/emergency-restore.sh
```

This pauses automation, clears leases, and restores project-owned sleep and
brightness state.

## Uninstall

Open the DMG and run **Uninstall Codex Lid Keeper.command**, or use:

```bash
./scripts/uninstall.sh
```

The uninstaller restores owned power state before removing the app, Helper,
sudoers rule, launchd jobs, login item, and project Hooks. User logs and
configuration are retained, and their location is printed.

## We need your test report

Useful coverage includes:

- Apple Silicon and Intel MacBooks;
- macOS 13, 14, 15, and newer;
- one, two, and three concurrent Codex tasks;
- AC-only and battery-enabled policies;
- unplug and low-charge restoration;
- supervised closed-lid networking and progress;
- temperature observations on an open desk; and
- emergency and final-task restoration.

Start with the [bilingual testing guide](TESTING.md), then use the
[hardware test form](https://github.com/Apex-Studio-He/codex-lid-keeper/issues/new?template=test_report.yml).
Do not upload prompts, transcripts, full Hook files, session IDs, or
unsanitized paths.

## Current limitations

- no Developer ID signing or Apple notarization;
- no automatic updater;
- no temperature-based cutoff;
- the graphical interface is currently Simplified Chinese only;
- incomplete MacBook/macOS compatibility evidence;
- undocumented macOS behavior may change; and
- not intended for unattended or enclosed-space operation.

## Resources

- [Testing guide / 测试指南](TESTING.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Security policy](SECURITY.md) |
  [安全说明](SECURITY.zh-CN.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)
- [Launch facts and channel checklist](docs/LAUNCH-KIT.md)

## Acknowledgements and license

Design research was informed by
[CodexAwake](https://github.com/Lu233/CodexAwake),
[wake](https://github.com/Moarram/wake), and
[claude-awake](https://github.com/Ami3466/claude-awake).
No source from those projects is vendored here.

Codex Lid Keeper is not an Apple or OpenAI product. Licensed under the
[MIT License](LICENSE).
