import AppKit
import CodexLidKeeperCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: DashboardModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            if let status = model.status {
                content(status)
            } else {
                ProgressView("正在读取守护状态…")
                    .controlSize(.large)
            }
        }
        .tint(.blue)
        .alert(
            "Codex Lid Keeper",
            isPresented: errorBinding
        ) {
            Button("知道了") {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "发生未知错误")
        }
        .alert(
            "Codex Hooks 已安装",
            isPresented: hookNoticeBinding
        ) {
            Button("知道了") {
                model.clearHookInstallMessage()
            }
        } message: {
            Text(model.hookInstallMessage ?? "")
        }
    }

    private func content(
        _ status: KeeperStatusSnapshot
    ) -> some View {
        VStack(spacing: 0) {
            header(status)
            Divider()
            ScrollView {
                VStack(spacing: 18) {
                    statusPanel(status)
                    HStack(alignment: .top, spacing: 18) {
                        readinessPanel(status)
                        controlsPanel(status)
                    }
                    taskPanel(status)
                }
                .padding(22)
            }
        }
    }

    private func header(
        _ status: KeeperStatusSnapshot
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.blue.opacity(0.13))
                    .frame(width: 38, height: 38)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Lid Keeper")
                    .font(.system(size: 16, weight: .semibold))
                Text("合盖前的任务与电源守护")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(
                text: statusText(status),
                symbol: statusSymbol(status),
                color: statusColor(status)
            )
            settingsButton
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("打开设置")
            .accessibilityLabel("打开设置")
        } else {
            Button {
                NSApp.sendAction(
                    Selector(("showPreferencesWindow:")),
                    to: nil,
                    from: nil
                )
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("打开设置")
            .accessibilityLabel("打开设置")
        }
    }

    private func statusPanel(
        _ status: KeeperStatusSnapshot
    ) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(
                        statusColor(status).opacity(0.18),
                        lineWidth: 7
                    )
                Circle()
                    .trim(
                        from: 0,
                        to: status.codexIsWorking ? 0.78 : 0.18
                    )
                    .stroke(
                        statusColor(status),
                        style: StrokeStyle(
                            lineWidth: 7,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: model.menuSymbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(statusColor(status))
            }
            .frame(width: 82, height: 82)

            VStack(alignment: .leading, spacing: 6) {
                Text(statusHeadline(status))
                    .font(.system(size: 24, weight: .semibold))
                Text(statusDetail(status))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Toggle(
                    "Codex 工作时允许合盖继续运行",
                    isOn: automationBinding(status)
                )
                .toggleStyle(.switch)
                .padding(.top, 3)
            }
            Spacer()
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private func readinessPanel(
        _ status: KeeperStatusSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(
                title: "合盖就绪",
                subtitle: "四项检查全部通过后再合盖"
            )
            ReadinessRail(
                status: status,
                helperInstalled: model.helperInstalled,
                recoveryWatchdogLoaded: model.recoveryProtectionReady,
                userAgentLoaded: model.userAgentLoaded,
                hooksInstalled: model.hooksInstalled,
                hookTrackingConfirmed: model.hookTrackingConfirmed
            )
            if let error = model.hooksConfigurationError {
                Label(
                    "无法读取 Hooks 配置：\(error)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !model.systemComponentsReady || !model.hooksInstalled {
                Divider()
                Button {
                    model.installHooksAndOpenCodex()
                } label: {
                    Label(
                        model.systemComponentsReady
                            ? "安装 Hooks 并打开 Codex"
                            : "安装或修复系统组件",
                        systemImage: model.systemComponentsReady
                            ? "link.badge.plus"
                            : "terminal"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Text(
                    model.systemComponentsReady
                        ? "会先备份现有配置，再合并五个任务生命周期 Hook。"
                        : "会在终端里请求管理员权限，安装或修复 Helper、恢复守护和 Hooks。"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func controlsPanel(
        _ status: KeeperStatusSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(
                title: "守护策略",
                subtitle: "电池模式默认关闭"
            )
            PowerModeControl(compact: false)
            Divider()
            Toggle(
                "准备合盖时将亮度降到最低",
                isOn: $model.dimWhenReady
            )
            .disabled(!model.brightnessAvailable)
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
            .controlSize(.large)
            .disabled(!model.readyToClose)
            Text(
                model.readyToClose
                    ? "点击后有 3 秒时间合盖；任务结束会恢复原亮度。"
                    : "等待 Codex、权限、电源和恢复守护全部就绪。"
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func taskPanel(
        _ status: KeeperStatusSnapshot
    ) -> some View {
        ActiveTasksView(
            status: status,
            hooksInstalled: model.hooksInstalled,
            hookTrackingConfirmed: model.hookTrackingConfirmed
        )
    }

    private func automationBinding(
        _ status: KeeperStatusSnapshot
    ) -> Binding<Bool> {
        Binding(
            get: { status.automationEnabled },
            set: model.setAutomationEnabled
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )
    }

    private var hookNoticeBinding: Binding<Bool> {
        Binding(
            get: { model.hookInstallMessage != nil },
            set: {
                if !$0 {
                    model.clearHookInstallMessage()
                }
            }
        )
    }
}

private struct StatusPill: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
            .accessibilityLabel("当前状态：\(text)")
    }
}
