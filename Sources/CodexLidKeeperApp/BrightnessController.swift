import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.graphics

final class BrightnessController {
    static let shared = BrightnessController()

    private let savedBrightnessKey =
        "com.zundu.codex-lid-keeper.saved-brightness"
    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(
        label: "com.zundu.codex-lid-keeper.brightness"
    )
    private let pendingDimLock = NSLock()
    private var pendingDimToken: UUID?

    var canControlBrightness: Bool {
        currentBrightness() != nil
    }

    func dimAfterCountdown(seconds: TimeInterval = 3) throws {
        guard let current = currentBrightness() else {
            throw BrightnessError.unavailable
        }
        if defaults.object(forKey: savedBrightnessKey) == nil {
            defaults.set(Double(current), forKey: savedBrightnessKey)
        }
        let token = UUID()
        pendingDimLock.lock()
        pendingDimToken = token
        pendingDimLock.unlock()
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard self?.takePendingDim(token) == true else { return }
            try? self?.setBrightness(0)
        }
    }

    func restoreIfNeeded() {
        cancelPendingDim()
        guard defaults.object(forKey: savedBrightnessKey) != nil else {
            return
        }
        let saved = Float(defaults.double(forKey: savedBrightnessKey))
        do {
            try setBrightness(saved)
            defaults.removeObject(forKey: savedBrightnessKey)
        } catch {
            // Keep the saved value so a later launch can retry restoration.
        }
    }

    private func currentBrightness() -> Float? {
        if let displayID = builtInDisplayID(),
           let value = DisplayServicesBrightness.shared.brightness(
               for: displayID
           ) {
            return value
        }
        return legacyBrightness()
    }

    private func legacyBrightness() -> Float? {
        let service = displayService()
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var value: Float = 0
        let result = IODisplayGetFloatParameter(
            service,
            0,
            kIODisplayBrightnessKey as CFString,
            &value
        )
        return result == kIOReturnSuccess ? value : nil
    }

    private func setBrightness(_ value: Float) throws {
        let boundedValue = min(max(value, 0), 1)
        if let displayID = builtInDisplayID(),
           DisplayServicesBrightness.shared.isAvailable {
            let client = DisplayServicesBrightness.shared
            try client.setBrightness(boundedValue, for: displayID)
            return
        }

        let service = displayService()
        guard service != 0 else {
            throw BrightnessError.unavailable
        }
        defer { IOObjectRelease(service) }
        let result = IODisplaySetFloatParameter(
            service,
            0,
            kIODisplayBrightnessKey as CFString,
            boundedValue
        )
        guard result == kIOReturnSuccess else {
            throw BrightnessError.writeFailed(result)
        }
    }

    private func displayService() -> io_service_t {
        IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect")
        )
    }

    private func builtInDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success,
              count > 0 else {
            return nil
        }
        var displays = [CGDirectDisplayID](
            repeating: 0,
            count: Int(count)
        )
        guard CGGetOnlineDisplayList(
            count,
            &displays,
            &count
        ) == .success else {
            return nil
        }
        return displays.prefix(Int(count)).first {
            CGDisplayIsBuiltin($0) != 0
        }
    }

    private func takePendingDim(_ token: UUID) -> Bool {
        pendingDimLock.lock()
        defer { pendingDimLock.unlock() }
        guard pendingDimToken == token else { return false }
        pendingDimToken = nil
        return true
    }

    private func cancelPendingDim() {
        pendingDimLock.lock()
        pendingDimToken = nil
        pendingDimLock.unlock()
    }
}

enum BrightnessError: Error, LocalizedError {
    case unavailable
    case writeFailed(kern_return_t)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "无法读取内置屏幕亮度。"
        case .writeFailed(let code):
            return "无法调整内置屏幕亮度（错误码 \(code)）。"
        }
    }
}

private typealias DisplayServicesGetBrightness =
    @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32
private typealias DisplayServicesSetBrightness =
    @convention(c) (CGDirectDisplayID, Float) -> Int32

private final class DisplayServicesBrightness {
    static let shared = DisplayServicesBrightness()

    private let handle: UnsafeMutableRawPointer?
    private let getBrightness: DisplayServicesGetBrightness?
    private let setBrightness: DisplayServicesSetBrightness?

    var isAvailable: Bool {
        getBrightness != nil && setBrightness != nil
    }

    private init() {
        let path =
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        if let handle,
           let getSymbol = dlsym(
               handle,
               "DisplayServicesGetBrightness"
           ),
           let setSymbol = dlsym(
               handle,
               "DisplayServicesSetBrightness"
           ) {
            getBrightness = unsafeBitCast(
                getSymbol,
                to: DisplayServicesGetBrightness.self
            )
            setBrightness = unsafeBitCast(
                setSymbol,
                to: DisplayServicesSetBrightness.self
            )
        } else {
            getBrightness = nil
            setBrightness = nil
        }
    }

    func brightness(
        for displayID: CGDirectDisplayID
    ) -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        let result = getBrightness(displayID, &value)
        return result == 0 ? value : nil
    }

    func setBrightness(
        _ value: Float,
        for displayID: CGDirectDisplayID
    ) throws {
        guard let setBrightness else {
            throw BrightnessError.unavailable
        }
        let result = setBrightness(displayID, value)
        guard result == 0 else {
            throw BrightnessError.writeFailed(result)
        }
    }
}
