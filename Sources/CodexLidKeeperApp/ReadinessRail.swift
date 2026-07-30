import CodexLidKeeperCore
import SwiftUI

struct ReadinessRail: View {
    let status: KeeperStatusSnapshot
    let helperInstalled: Bool
    let recoveryWatchdogLoaded: Bool
    let userAgentLoaded: Bool
    let hooksInstalled: Bool
    let hookTrackingConfirmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadinessStep(
                symbol: "terminal.fill",
                title: "Codex",
                detail: codexDetail,
                state: codexState,
                isLast: false
            )
            ReadinessStep(
                symbol: powerSymbol,
                title: "电源策略",
                detail: powerDetail,
                state: powerReady ? .ready : .blocked,
                isLast: false
            )
            ReadinessStep(
                symbol: "battery.75percent",
                title: "电量",
                detail: batteryDetail,
                state: batteryReady ? .ready : .blocked,
                isLast: false
            )
            ReadinessStep(
                symbol: "arrow.counterclockwise.circle.fill",
                title: "恢复守护",
                detail: recoveryDetail,
                state: recoveryReady ? .ready : .blocked,
                isLast: true
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("合盖就绪检查")
    }

    private var codexDetail: String {
        if !hookTrackingConfirmed {
            return hooksInstalled
                ? "等待 Codex 首次上报任务状态"
                : "任务检测尚未就绪"
        }
        if status.activeLeases.isEmpty {
            return status.pendingEventCount > 0
                ? "正在接收任务状态"
                : "等待本地任务"
        }
        return "\(status.activeLeases.count) 个任务正在运行"
    }

    private var codexState: ReadinessState {
        if !hookTrackingConfirmed { return .waiting }
        return status.codexIsWorking ? .ready : .waiting
    }

    private var powerReady: Bool {
        guard let onAC = status.livePower.isOnACPower else { return false }
        return onAC || status.configuration.powerMode == .allowBattery
    }

    private var powerSymbol: String {
        status.livePower.isOnACPower == true
            ? "powerplug.fill"
            : "battery.75percent"
    }

    private var powerDetail: String {
        guard let onAC = status.livePower.isOnACPower else {
            return "无法确认电源状态"
        }
        if onAC { return "已接入电源" }
        if status.configuration.powerMode == .allowBattery {
            return "允许使用电池继续运行"
        }
        return "当前策略要求接电"
    }

    private var batteryReady: Bool {
        guard let percent = status.livePower.batteryPercent else {
            return status.livePower.isOnACPower == true
        }
        return percent >= status.configuration.minimumBatteryPercent
    }

    private var batteryDetail: String {
        guard let percent = status.livePower.batteryPercent else {
            return "电量未知"
        }
        return "\(percent)% · 安全线 \(status.configuration.minimumBatteryPercent)%"
    }

    private var recoveryReady: Bool {
        helperInstalled
            && recoveryWatchdogLoaded
            && userAgentLoaded
            && hooksInstalled
    }

    private var recoveryDetail: String {
        switch (
            helperInstalled,
            recoveryWatchdogLoaded,
            userAgentLoaded,
            hooksInstalled
        ) {
        case (true, true, true, true):
            return hookTrackingConfirmed
                ? "Helper、Agent、Hook 和 watchdog 已就绪"
                : "Helper、Agent 与 watchdog 已就绪；Hook 等待确认"
        case (false, _, _, _):
            return "尚未安装 root Helper"
        case (_, false, _, _):
            return "恢复 watchdog 或电源心跳尚未就绪"
        case (_, _, false, _):
            return "用户后台 Agent 尚未正常运行"
        case (_, _, _, false):
            return "Codex Hook 尚未安装或信任"
        }
    }
}

private struct ReadinessStep: View {
    let symbol: String
    let title: String
    let detail: String
    let state: ReadinessState
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(state.color.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: state.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(state.color)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 1, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(detail)，\(state.label)")
    }
}

private enum ReadinessState {
    case ready
    case waiting
    case blocked

    var color: Color {
        switch self {
        case .ready: .green
        case .waiting: .blue
        case .blocked: .orange
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark"
        case .waiting: "ellipsis"
        case .blocked: "exclamationmark"
        }
    }

    var label: String {
        switch self {
        case .ready: "已就绪"
        case .waiting: "等待中"
        case .blocked: "需要处理"
        }
    }
}
