import Foundation
import IOKit.ps

public protocol PowerSourceProviding {
    func currentSnapshot() -> PowerSnapshot
}

public struct SystemPowerSourceProvider: PowerSourceProviding {
    public init() {}

    public func currentSnapshot() -> PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return .unknown
        }

        var batteryPercent: Int?
        var powerStateKnown = false
        var onACPower = false

        for source in sources {
            guard let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue(),
                  let description = raw as? [String: Any] else {
                continue
            }

            if let state = description[kIOPSPowerSourceStateKey] as? String {
                powerStateKnown = true
                if state == kIOPSACPowerValue {
                    onACPower = true
                }
            }

            if let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
               let maximum = description[kIOPSMaxCapacityKey] as? NSNumber,
               maximum.doubleValue > 0 {
                batteryPercent = Int(
                    (current.doubleValue / maximum.doubleValue * 100).rounded()
                )
            }
        }

        return PowerSnapshot(
            isOnACPower: powerStateKnown ? onACPower : nil,
            batteryPercent: batteryPercent
        )
    }
}

public struct StaticPowerSourceProvider: PowerSourceProviding {
    private let snapshot: PowerSnapshot

    public init(snapshot: PowerSnapshot) {
        self.snapshot = snapshot
    }

    public func currentSnapshot() -> PowerSnapshot {
        snapshot
    }
}
