# Architecture / 架构说明

[English](#english) | [中文](#中文说明)

## English

### Design goals

- Observe actual Codex task activity rather than application presence.
- Keep Hooks fast and independent of privilege escalation.
- Support overlapping sessions and turns.
- Restore only power state the project owns.
- Fail safe after missing events, process crashes, power-policy mismatch, low
  battery, or stale heartbeats.
- Make all automated tests incapable of changing live power policy.

### Runtime flow

```mermaid
flowchart TD
    A["Codex lifecycle Hook"] --> B["Decode minimal fields"]
    B --> C["Private atomic event spool"]
    C --> D["DaemonCoordinator.runCycle"]
    N["Read-only Codex turn metadata"] --> O["Runtime task detector"]
    O --> D
    D --> E["Idempotent lease reducer"]
    E --> P["Deduplicate observations by session"]
    P --> F{"Active task + selected power policy + safe battery?"}
    F -- "Yes" --> G["Exact sudo command"]
    G --> H["Root-owned helper"]
    H --> I["pmset -c or -b disablesleep 1"]
    F -- "No" --> J["Restore captured prior profiles"]
    K["Root watchdog"] --> J
    L["SwiftUI app + menu bar"] --> D
    L --> M["Reversible built-in display dimming"]
```

The Hook's interface is one JSON object on stdin and inert `{}` on stdout. It
does not know about leases, power sources, sudo, or launchd.

The runtime detector reads only `codex_core::session::turn` state records from
Codex's local log database and `id + cwd` from its thread database. It does not
select thread titles, prompts, responses, or tool content. This secondary path
bootstraps work that started before Hooks were installed. Hook and runtime
observations use the same session/turn identity and are deduplicated before
display and reconciliation.

`DaemonCoordinator.runCycle` is the main runtime interface. It owns the
ordering between event consumption, startup recovery, maintenance scheduling,
IOKit sampling, privileged heartbeat cadence, and reconciliation. This keeps
stateful timing rules out of the CLI loop.

### Core modules

| Module | Responsibility |
|---|---|
| `HookProcessor` | Decode only required Hook fields and create canonical events |
| `HookEventPipeline` | Private atomic queue, validation, ordering, replay IDs, bounded drain |
| `CodexRuntimeTaskDetector` | Read minimal turn-state metadata and bootstrap already-running work |
| `LeaseReducer` | Acquire, renew, delayed release, session release, hard expiry |
| `DaemonCoordinator` | Decide when a cycle needs power/state reconciliation |
| `KeeperReconciler` | Convert leases, configuration, and power snapshot into an action |
| `KeeperController` | Give the app one status/configuration/recovery interface |
| `PrivilegedPowerManager` | Capture prior AC/battery state, enable, heartbeat, and restore |
| `LockedStateStore` | Cross-process serialization and atomic state persistence |
| `BrightnessController` | Save, dim, cancel, and restore built-in display brightness |

### Privilege seam

The normal user process may invoke exactly:

```text
sudo -n /Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper power enable-ac
sudo -n /Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper power enable-battery
sudo -n /Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper power restore
```

The executable and parent directory are root-owned. No Hook-controlled argument
crosses this seam. Watchdog execution is launched as root by launchd and uses a
fixed command.

### Ownership protocol

Before the first change, the root helper:

1. reads the AC and battery sections of `pmset -g custom`;
2. records the requested mode and the prior values it will change;
3. writes a root-owned ownership record;
4. enables AC only, or AC and battery, through fixed commands;
5. updates the record timestamp on heartbeat.

Restoration reads the record, writes each captured profile value, and removes
the record only after successful commands. Switching modes restores the old
ownership before capturing the new one. A malformed record is never guessed.

### Failure behavior

| Failure | Expected behavior |
|---|---|
| Hook times out or queue is full | Codex proceeds; existing ownership remains watchdog-protected |
| Codex runtime database is missing or changes incompatibly | Fall back to trusted Hooks; show unknown count until either source reports |
| Daemon crashes after state save | Event replay ID prevents duplicate semantic application |
| Daemon disappears | Root watchdog restores after heartbeat expiry |
| AC is removed | AC-only mode restores; battery mode continues only above its charge floor |
| Battery is below threshold | Ownership is restored |
| Event is missing | Lease eventually reaches hard expiry |
| Future-dated event | Event is rejected beyond five-minute skew |
| Ownership record is malformed | Refuse to guess; surface an error |
| Configuration is invalid | User daemon fails closed; emergency restore remains available |

### Persistence

```text
~/Library/Application Support/CodexLidKeeper/
├── config.json
├── state.json
├── state.lock
├── daemon.lock
├── keeper.log
├── keeper.log.1
└── events/pending/*.json

/var/db/com.zundu.codex-lid-keeper.power.json
```

User data is private to the current account. The ownership record is root-only.
Prompts and tool payloads are not part of any persisted model.

## 中文说明

### 设计时先守住几条线

- 判断依据是“Codex 有没有任务在跑”，不是“Codex 窗口开没开”；
- Hook 只负责报信，不能在里面等 sudo；
- 多个 session、多个 turn 要能同时存在，互不误伤；
- 只恢复自己改过的设置，不能顺手覆盖用户原来的配置；
- 丢事件、崩进程、供电不符合所选策略、低电量都要能收尾；
- 自动测试绝不能碰开发机真实的电源设置。

### 一条事件怎么走

Codex 调用 Hook 后，`HookProcessor` 只取任务识别所需的几个字段，
`HookEventPipeline` 随即把事件写进私有队列。写完 Hook 就返回，不参与后面的
电源判断。

安装前已经开始的任务不会触发新 Hook，所以还有一条只读补充链路：
`CodexRuntimeTaskDetector` 只筛选 Codex 本地日志里的 turn 状态，并从线程库读取
`id + cwd`。查询不会选取任务标题、提示词、回复或工具内容。两条链路最后按
session / turn 去重，同一个任务不会算两次。

后台的 `DaemonCoordinator.runCycle` 是整条运行链路的入口。它负责决定：

- 现在要不要消费队列；
- 启动时是否需要清理上次遗留的状态；
- 什么时候读取 IOKit；
- 什么时候续 root 心跳；
- 什么时候让 `KeeperReconciler` 重新判断。

这样，CLI 只负责循环调用，不需要自己拼一堆时间和状态条件。

几个核心模块分别做这些事：

- `HookProcessor`：把 Hook 输入整理成统一事件；
- `HookEventPipeline`：写队列、校验、排序、去重和分批处理；
- `CodexRuntimeTaskDetector`：只读补记安装前已经在跑的任务；
- `LeaseReducer`：新增任务、续期、延迟结束和强制过期；
- `DaemonCoordinator`：安排每一轮后台工作；
- `KeeperReconciler`：结合任务、电源和配置，决定保持还是恢复；
- `KeeperController`：给图形 App 提供统一的状态、配置和恢复接口；
- `PrivilegedPowerManager`：记录 AC / 电池原值、修改设置、续心跳和恢复；
- `LockedStateStore`：保证多个进程不会把状态文件写乱。
- `BrightnessController`：保存、调暗、取消和恢复内置屏幕亮度。

### sudo 边界

普通用户进程只能通过 sudo 调三条固定命令：

```text
power enable-ac
power enable-battery
power restore
```

被授权的程序和它所在的目录都归 root 管。Hook 不能追加参数，也不能让 root 去改
别的设置。

### 怎么判断“这项设置归我管”

第一次修改前，root Helper 会读取 `pmset -g custom` 的 AC 和电池部分，把当前
模式与即将修改的原值写进 root 所有的记录文件，然后才执行修改。“仅接电”只动
AC；“接电或电池”会分别处理两套配置。

恢复时先读记录，再逐项写回原值。切换模式也会先完整恢复旧模式。命令成功以后才
删除记录。如果记录坏了，就报错停下，绝不猜一个值硬写。

### 各种故障会怎样

- **Hook 超时或队列满：** 不拦 Codex；已经接管的电源状态继续由 watchdog 兜底。
- **Codex 运行数据库不存在或格式变化：** 回退到受信任的 Hook；两条链路都没
  报过状态前，界面显示未知数量。
- **保存状态后 daemon 崩了：** 重启后可能重读事件，但事件 ID 会拦住重复执行。
- **daemon 一直没回来：** root watchdog 等心跳过期后恢复。
- **运行中拔电：** 仅接电模式会恢复；电池模式只在高于安全线时继续。
- **电量过低：** 正常后台会恢复，root watchdog 还有独立的 30% 硬底线。
- **结束事件丢了：** 租约到最长时间后自动过期。
- **事件时间明显不对：** 比本机快五分钟以上就直接丢弃。
- **所有权记录损坏：** 报错，不猜原值。
- **配置文件写坏了：** 后台停止接管，但紧急恢复命令仍然可用。

用户目录里只保存任务识别、配置、状态和日志，不保存提示词或工具内容。只读检测
不会复制 Codex 数据库正文；root 所有权记录只有 root 能访问。
