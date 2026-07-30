# Security Policy

[English](SECURITY.md) | [简体中文](SECURITY.zh-CN.md)

## Security model

Codex Lid Keeper changes an undocumented macOS power setting with root
privileges. Its primary security goals are:

1. never expose a general privileged command runner;
2. never let a normal user replace the sudo-authorized executable;
3. restore only a setting this project owns;
4. fail safe after missing lifecycle events or component failure;
5. avoid retaining Codex prompt or project content.

The installed executable lives under root-owned
`/Library/PrivilegedHelperTools`. The sudoers entry permits only:

```text
com.zundu.codex-lid-keeper power enable-ac
com.zundu.codex-lid-keeper power enable-battery
com.zundu.codex-lid-keeper power restore
```

No command string, path, setting name, or setting value is supplied by Hook
input.

Before changing a `pmset` profile, the root process writes a root-owned
ownership record containing the selected mode and previous AC/battery
`disablesleep` values. AC-only mode changes only the AC profile. Battery mode
captures and changes both profiles. If that record cannot be decoded,
restoration stops with an error instead of guessing.

A root LaunchDaemon restores owned state if the user agent's heartbeat becomes
stale. It follows the recorded power mode, fails safe when live power is
unknown, and enforces an independent 30% battery floor.

## Data handling

Hook JSON is read from standard input with a 1 MiB limit. The Hook atomically
queues a minimal event and returns without calling `sudo`, querying power, or
waiting for the user agent. Only these fields are decoded:

- `session_id`
- `turn_id`
- `cwd` (reduced to the final path component)
- `hook_event_name`

Prompts, transcripts, model responses, tool inputs, and tool outputs are not
decoded or stored. `cwd` is reduced to its final path component before the
event is persisted.

To recognize tasks immediately, including work that began before Hook
installation, the user daemon opens Codex's local state read-only. It selects
only thread `id`, `rollout_path`, `cwd`, and update/archive metadata, then
examines at most the final 4 MiB of each recent rollout. Lines are rejected
before JSON decoding unless they contain an exact lifecycle marker. The
decoder models only:

- the `event_msg` envelope;
- `task_started` or `task_complete`; and
- `turn_id`.

A separate compatibility query reads turn-state metadata only from rows whose
target is `codex_core::session::turn`. Neither path selects or models thread
titles, previews, first messages, prompt text, responses, or tool payloads.
No rollout contents are copied into Keeper state or logs. The full `cwd` is
reduced to its final component before it enters Keeper state. If these local
formats become unavailable or incompatible, runtime detection is disabled and
tracking falls back to Hooks.

Each queued event is limited to 64 KiB, created with `0600` permissions, and
validated again by the daemon. The file and event directory are synchronized
around the atomic rename. Events dated more than five minutes ahead of the
daemon clock are rejected so clock correction cannot create an excessively
long lease. Processing is idempotent by event ID. The spool is capped at 4,096
pending events; if it is full or unavailable, the Hook fails open so Codex work
is not blocked, while existing power ownership remains subject to the root
watchdog. State and log files are user-only, and the log rotates at 1 MiB with
one retained generation.

## Installation review

The installer changes sensitive system locations. Review:

- `scripts/install.sh`
- `scripts/uninstall.sh`
- `Resources/com.zundu.codex-lid-keeper.recovery.plist`
- `Sources/CodexLidKeeperCore/CodexRuntimeTaskDetector.swift`
- the generated `/etc/sudoers.d/codex-lid-keeper`

The installer validates the sudoers fragment with `visudo` before installing
it. Codex separately requires Hook trust review.

## Reporting a vulnerability

Do not include secrets, Hook payloads, transcripts, or personal paths in a
public report. Open a
[GitHub Security Advisory](https://github.com/Apex-Studio-He/codex-lid-keeper/security/advisories/new)
with:

- affected commit and macOS version;
- reproduction steps using dry-run mode where possible;
- the expected and observed privilege boundary;
- whether live power settings were changed.

## Supported versions

The current default branch and latest App Alpha are maintained. The app is
ad-hoc signed rather than Developer ID signed and notarized. This project
remains experimental and should not be deployed unattended.
