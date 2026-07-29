import AppKit
import CodexLidKeeperCore
import SwiftUI

struct MenuPanelView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.13))
                        .frame(width: 34, height: 34)
                    Image(systemName: model.menuSymbol)
                        .foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.menuTitle)
                        .font(.system(size: 14, weight: .semibold))
                    Text(statusSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let status = model.status {
                Divider()
                PowerModeControl(compact: true)
                Divider()
                HStack {
                    Label(
                        powerLabel(status),
                        systemImage: status.livePower.isOnACPower == true
                            ? "powerplug.fill"
                            : "battery.75percent"
                    )
                    Spacer()
                    Text(
                        status.livePower.batteryPercent.map {
                            "\($0)%"
                        } ?? "未知"
                    )
                    .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))

                Button {
                    if model.isPreparedToClose {
                        model.cancelReadyMode()
                    } else {
                        model.prepareToClose()
                    }
                } label: {
                    Label(
                        model.isPreparedToClose
                            ? "取消合盖准备"
                            : "调暗并准备合盖",
                        systemImage: model.isPreparedToClose
                            ? "xmark"
                            : "checkmark.shield.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.readyToClose)
            }

            HStack {
                Button("打开主窗口") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first {
                        $0.canBecomeMain
                    }?.makeKeyAndOrderFront(nil)
                }
                Spacer()
                Button("紧急恢复") {
                    model.emergencyRestore()
                }
                .foregroundStyle(.red)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 340)
        .tint(.blue)
    }

    private var statusColor: Color {
        guard let status = model.status else { return .secondary }
        if model.errorMessage != nil || status.lastError != nil {
            return .orange
        }
        if model.isPreparedToClose || status.powerOwned {
            return .green
        }
        return status.codexIsWorking ? .blue : .secondary
    }

    private var statusSubtitle: String {
        guard let status = model.status else {
            return "正在读取状态"
        }
        if !model.hookTrackingConfirmed {
            return "正在连接 Codex 任务状态"
        }
        if status.activeLeases.isEmpty {
            return "没有正在运行的任务"
        }
        return "\(status.activeLeases.count) 个任务"
    }

    private func powerLabel(
        _ status: KeeperStatusSnapshot
    ) -> String {
        if status.livePower.isOnACPower == true {
            return "已接电"
        }
        if status.configuration.powerMode == .allowBattery {
            return "电池守护"
        }
        return "等待接电"
    }
}
