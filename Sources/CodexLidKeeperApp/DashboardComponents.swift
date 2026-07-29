import CodexLidKeeperCore
import SwiftUI

struct SectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

struct ActiveTasksView: View {
    let status: KeeperStatusSnapshot
    let hooksInstalled: Bool
    let hookTrackingConfirmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionTitle(
                    title: "正在运行",
                    subtitle: "只显示项目名和任务时间，不保存对话内容"
                )
                Spacer()
                Text(
                    hookTrackingConfirmed
                        ? "\(status.activeLeases.count)"
                        : "—"
                )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if status.activeLeases.isEmpty {
                Label(
                    emptyMessage,
                    systemImage: hookTrackingConfirmed
                        ? "moon.zzz"
                        : "link.badge.plus"
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 46)
            } else {
                ForEach(status.activeLeases) { lease in
                    HStack(spacing: 12) {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lease.projectName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(
                                "运行 \(durationText(from: lease.startedAt))"
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("活跃")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .panelStyle()
    }

    private var emptyMessage: String {
        if !hookTrackingConfirmed {
            return hooksInstalled
                ? "等待 Codex 首次上报任务状态"
                : "安装并信任 Codex Hooks 后开始准确计数"
        }
        if status.pendingEventCount > 0 {
            return "正在接收 Codex 任务状态"
        }
        return "当前没有正在执行的本地 Codex 任务"
    }

    private func durationText(from date: Date) -> String {
        let minutes = max(
            0,
            Int(Date().timeIntervalSince(date) / 60)
        )
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }
}

extension View {
    func panelStyle() -> some View {
        self
            .padding(18)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.07))
            }
    }
}

extension DashboardView {
    func statusText(_ status: KeeperStatusSnapshot) -> String {
        if !model.hookTrackingConfirmed { return "等待任务检测" }
        if model.isPreparedToClose { return "可以合盖" }
        if status.powerOwned { return "正在守护" }
        if status.codexIsWorking { return "Codex 工作中" }
        if !status.automationEnabled { return "已暂停" }
        return "等待任务"
    }

    func statusHeadline(_ status: KeeperStatusSnapshot) -> String {
        if !model.hookTrackingConfirmed { return "正在连接 Codex" }
        if model.isPreparedToClose { return "现在可以合盖" }
        if status.powerOwned { return "Codex 正在继续工作" }
        if status.codexIsWorking { return "检测到 Codex 任务" }
        if !status.automationEnabled { return "守护功能已暂停" }
        return "等待 Codex 开始工作"
    }

    func statusDetail(_ status: KeeperStatusSnapshot) -> String {
        if !model.hookTrackingConfirmed {
            return "完成 Hooks 安装后，会自动统计真实任务"
        }
        if model.isPreparedToClose {
            return "亮度即将降到最低，任务结束后自动恢复"
        }
        if status.powerOwned {
            return "睡眠设置由 watchdog 保护，异常时会自动恢复"
        }
        if status.codexIsWorking {
            return "正在等待电源或后台守护完成接管"
        }
        return "启动本地 Codex 任务后，这里会自动显示状态"
    }

    func statusSymbol(_ status: KeeperStatusSnapshot) -> String {
        if !model.hookTrackingConfirmed {
            return "link.badge.plus"
        }
        if model.isPreparedToClose { return "checkmark.circle.fill" }
        if status.powerOwned { return "bolt.shield.fill" }
        if status.codexIsWorking { return "circle.dotted" }
        if !status.automationEnabled { return "pause.circle.fill" }
        return "moon.zzz.fill"
    }

    func statusColor(_ status: KeeperStatusSnapshot) -> Color {
        if model.errorMessage != nil || status.lastError != nil {
            return .orange
        }
        if !model.hookTrackingConfirmed { return .orange }
        if model.isPreparedToClose || status.powerOwned {
            return .green
        }
        if status.codexIsWorking { return .blue }
        return .secondary
    }
}
