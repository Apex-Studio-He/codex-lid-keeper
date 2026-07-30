import AppKit
import CodexLidKeeperCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var launchAtLogin =
        LoginItemManager.shared.isEnabled
    @State private var loginError: String?

    var body: some View {
        TabView {
            general
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }
            safety
                .tabItem {
                    Label("安全", systemImage: "shield")
                }
            integration
                .tabItem {
                    Label("权限", systemImage: "lock")
                }
        }
        .padding(20)
        .onAppear {
            launchAtLogin = LoginItemManager.shared.isEnabled
        }
        .alert(
            "无法更改登录项",
            isPresented: Binding(
                get: { loginError != nil },
                set: { if !$0 { loginError = nil } }
            )
        ) {
            Button("知道了") {
                loginError = nil
            }
        } message: {
            Text(loginError ?? "")
        }
        .alert(
            "Codex Hooks 已安装",
            isPresented: Binding(
                get: { model.hookInstallMessage != nil },
                set: {
                    if !$0 {
                        model.clearHookInstallMessage()
                    }
                }
            )
        ) {
            Button("知道了") {
                model.clearHookInstallMessage()
            }
        } message: {
            Text(model.hookInstallMessage ?? "")
        }
    }

    private var general: some View {
        Form {
            Section("启动与显示") {
                Toggle("登录后自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { value in
                        do {
                            try LoginItemManager.shared.setEnabled(value)
                        } catch {
                            launchAtLogin =
                                LoginItemManager.shared.isEnabled
                            loginError = error.localizedDescription
                        }
                    }
                Toggle(
                    "准备合盖时将内置屏幕亮度降到最低",
                    isOn: $model.dimWhenReady
                )
                .disabled(!model.brightnessAvailable)
                Text(
                    "实际合盖后内置屏幕会熄灭；这个选项负责合盖前调暗，并在任务结束后恢复原亮度。"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var safety: some View {
        Form {
            Section("电源策略") {
                PowerModeControl(compact: false)
                if let configuration = model.status?.configuration {
                    LabeledContent("最低电量") {
                        HStack {
                            Slider(
                                value: batteryBinding(configuration),
                                in: 30...100,
                                step: 5
                            )
                            .frame(width: 190)
                            Text(
                                "\(configuration.minimumBatteryPercent)%"
                            )
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }
            Section("恢复") {
                Button("立即执行紧急恢复", role: .destructive) {
                    model.emergencyRestore()
                }
                Text(
                    "会暂停自动守护、清空任务租约，并恢复本项目接管的睡眠与亮度设置。"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var integration: some View {
        Form {
            Section("系统集成") {
                IntegrationRow(
                    title: "root Helper",
                    detail: "负责精确修改并恢复睡眠设置",
                    ready: model.helperInstalled
                )
                IntegrationRow(
                    title: "恢复 watchdog",
                    detail: "任务或心跳异常时自动恢复睡眠设置",
                    ready: model.recoveryProtectionReady
                )
                IntegrationRow(
                    title: "用户后台 Agent",
                    detail: "接收任务事件并维护恢复心跳",
                    ready: model.userAgentLoaded
                )
                IntegrationRow(
                    title: "Codex Hooks",
                    detail: "只记录任务生命周期，不保存对话内容",
                    ready: model.hooksInstalled
                )
                if let error = model.hooksConfigurationError {
                    Label(
                        "无法读取 Hooks 配置：\(error)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                }
                IntegrationRow(
                    title: "亮度控制",
                    detail: "只作用于支持的内置显示器",
                    ready: model.brightnessAvailable
                )
                if !model.systemComponentsReady || !model.hooksInstalled {
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
                    }
                }
            }
            Button("打开系统登录项设置") {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        .formStyle(.grouped)
    }

    private func batteryBinding(
        _ configuration: RuntimeConfiguration
    ) -> Binding<Double> {
        Binding(
            get: {
                Double(
                    model.status?.configuration
                        .minimumBatteryPercent
                        ?? configuration.minimumBatteryPercent
                )
            },
            set: {
                model.setMinimumBatteryPercent(Int($0))
            }
        )
    }
}

private struct IntegrationRow: View {
    let title: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                ready ? "已就绪" : "需要处理",
                systemImage: ready
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(ready ? .green : .orange)
            .font(.system(size: 11, weight: .medium))
        }
        .accessibilityElement(children: .combine)
    }
}
