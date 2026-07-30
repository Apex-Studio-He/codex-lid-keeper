# Codex Lid Keeper Launch Kit / 发布素材与渠道检查表

Last verified / 最后核对：2026-07-30

This file is a factual launch reference, not evidence that every MacBook has
passed a closed-lid test.

这是一份可核对的发布事实表，不代表所有 MacBook 都已经通过合盖测试。

## One-line position / 一句话定位

**English**

> A Codex-aware macOS lid guard: active local work starts the guard; the final
> task restores sleep and brightness.

**中文**

> 让守护跟着真实 Codex 任务走：有任务才接管，最后一个结束就恢复。

Do not market this as another permanent keep-awake toggle. The narrow,
verifiable difference is Codex lifecycle automation, concurrent task counting,
and final-task restoration.

不要把它宣传成“又一个防睡眠开关”。真正能核对的差异是：跟踪 Codex 生命周期、
识别并发任务，以及最后一个任务结束后自动恢复。

## Verified facts / 已验证事实

- Native SwiftUI app, menu-bar control, macOS 13+.
- Current graphical interface is Simplified Chinese; English documentation is
  available.
- Universal `arm64 + x86_64` GUI and CLI.
- MIT-licensed source.
- 58 native self-tests, 8 Hook compatibility tests, isolated dry-run lifecycle
  test, and mounted-DMG verification.
- Two local lifecycle signals merged and deduplicated by Codex session.
- AC-only default; explicit battery opt-in; 30–100% user floor and independent
  30% root floor.
- Exact prior AC/battery `disablesleep` values are captured and restored.
- Prompt text, model responses, tool inputs, and tool outputs are not modeled
  or persisted by Keeper.
- App is ad-hoc signed, not Developer ID signed or Apple-notarized.
- Physical closed-lid networking, temperature, and broad compatibility remain
  tester evidence.

## Claims not to make / 不要这样宣传

- “first”, “only”, “safest”, “works on every MacBook”
- signed, notarized, Gatekeeper-approved, production-ready
- temperature protection or automatic updates
- “does not read any Codex files”
- physical closed-lid success without a continuous real-hardware recording

不要说“首个”“唯一”“最安全”“所有机型都能用”，也不要把 ad-hoc 签名说成正式
签名 / 公证。准确的隐私说法是：只读检查范围刻意收窄，并且不建立或保存提示词、
回复和工具载荷字段。

## Repository metadata / 仓库元数据

Recommended description:

> Codex-aware macOS lid guard: keeps active local tasks running, then restores
> sleep and brightness. Public alpha; supervised testing only.

Topics:

```text
codex
launchd
macbook
macos
menu-bar-app
open-source
openai-codex
power-management
sleep-prevention
swift
swiftui
```

Primary download:

```text
https://github.com/Apex-Studio-He/codex-lid-keeper/releases/download/v0.3.0-app-alpha/Codex-Lid-Keeper-v0.3.0-universal.dmg
```

## Asset index / 素材索引

| Asset | Size | Use |
|---|---:|---|
| `docs/images/social-preview.jpg` | 1280×640 | GitHub Social Preview |
| `docs/images/producthunt-thumbnail.png` | 240×240 | Product thumbnail |
| `docs/images/gallery-01-hero.jpg` | 1270×760 | Lifecycle differentiation |
| `docs/images/gallery-02-safety.jpg` | 1270×760 | Power and recovery controls |
| `docs/images/dashboard-zh.png` | 1560×1170 | Full real dashboard |
| `docs/images/settings-power-zh.png` | 1120×965 | Full real Settings window |
| `docs/demo/codex-lid-keeper-ui-walkthrough.mp4` | 1280×720, 29 s | Real-UI screenshot overview only |

The abstract background was generated without logos, UI, devices, or data.
Every product state shown on top comes from the real app screenshots.

抽象背景不含 Logo、界面、设备或任务数据；叠加的产品状态都来自真实 App 截图。

## Product Hunt fields

Product Hunt should wait until the project has Developer ID/notarization,
English UI localization, a real closed-lid demo, and several independent
hardware reports.

- Name: `Codex Lid Keeper`
- URL: `https://github.com/Apex-Studio-He/codex-lid-keeper`
- Tagline: `Keep local Codex work running after your MacBook lid closes`
- Description:

  > Codex Lid Keeper is an open-source macOS app that keeps eligible local
  > Codex tasks running after lid close, then restores the previous sleep
  > policy and display brightness after the final task. Public Alpha:
  > supervised testing only.

- Pricing: `Free`
- Status: `Beta`
- Tags: `Developer Tools`, `Mac`, `Open Source`

The maker comment must be written personally; Product Hunt prohibits
AI-generated comments.

## V2EX and Show HN

Do not copy AI-generated or AI-edited submission text to either platform.
V2EX explicitly rejects AI-generated content, and current HN moderator
guidance requires submission text to be written by hand.

Codex can provide only a fact checklist for the developer to rewrite:

1. the concrete personal problem that led to the project;
2. the real “three tasks showed two” debugging story;
3. why simple `pmset 1/0` is not enough;
4. what has and has not been verified;
5. the ad-hoc signing/notarization limitation;
6. the ventilation and supervised-test warning; and
7. one request: model, macOS, Codex version, and sanitized test result.

V2EX independent work belongs in `分享创造`. Show HN should wait until the
publisher can remain in the comments and the download is straightforward.
Never ask for votes.

## Reddit

- `r/MacOS`: developer self-promotion is limited to Saturday
  `00:00–23:59 UTC`; disclose the developer relationship and remain in the
  comments.
- `r/macapps`: wait until account/community requirements and repository trust
  gates are met. A close alternative, Lidless, already offers notarization,
  temperature controls, timers, and updates.

An honest comparison:

- Lidless: broader manual/general lid operation and more mature distribution.
- Codex Lid Keeper: narrower Codex lifecycle automation, concurrent counts,
  and automatic final-task restoration.
- Current disadvantage: no notarization, temperature cutoff, updater, or broad
  compatibility matrix.

Do not cross-post identical copy, mass-message users, request votes, or
coordinate comments.

## Required real-hardware demo / 实机演示要求

Do not replace these shots with animation:

1. show real Codex and Keeper counts side by side;
2. show AC-only, live charge, and recovery ready;
3. keep one continuous external shot while the lid closes;
4. show synchronized observable progress from another device;
5. let tasks finish `3 → 2 → 1 → 0`;
6. show `powerOwned: no` and brightness restoration; and
7. end with the ventilation warning and Public Alpha label.

拍不到连续实机镜头，就只发布“界面预览”，不要写成“已经证明合盖运行”。

## Metrics to watch / 后续指标

- GitHub Release asset download count;
- unique hardware test reports;
- Mac model/chip and macOS coverage;
- install, update, uninstall, and emergency-restore pass rate;
- final-task restoration and unplug/low-charge failures;
- DMG checksum or Gatekeeper support questions.

Clone counts, page views, and stars are not user or installation counts.
