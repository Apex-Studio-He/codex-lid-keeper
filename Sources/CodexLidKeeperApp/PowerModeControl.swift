import CodexLidKeeperCore
import SwiftUI

struct PowerModeControl: View {
    @EnvironmentObject private var model: DashboardModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("守护使用什么电源")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                    if !compact {
                        Text("默认仅接电；电池模式会受到最低电量保护")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Picker(
                "守护使用什么电源",
                selection: powerModeBinding
            ) {
                Label("仅接电", systemImage: "powerplug.fill")
                    .tag(GuardPowerMode.acOnly)
                Label(
                    "接电或电池",
                    systemImage: "battery.75percent"
                )
                .tag(GuardPowerMode.allowBattery)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.status?.configuration.powerMode == .allowBattery {
                Label(
                    batteryMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var powerModeBinding: Binding<GuardPowerMode> {
        Binding(
            get: {
                model.status?.configuration.powerMode ?? .acOnly
            },
            set: model.setPowerMode
        )
    }

    private var batteryMessage: String {
        let floor = model.status?.configuration
            .minimumBatteryPercent ?? 30
        return "拔电后仍会继续运行；电量低于 \(floor)% 时立即恢复睡眠。"
    }
}
