import AppKit
import Darwin
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct CodexLidKeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate
    @StateObject private var model = DashboardModel()

    var body: some Scene {
        WindowGroup("Codex Lid Keeper") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 540)
        }
        .defaultSize(width: 780, height: 610)

        MenuBarExtra {
            MenuPanelView()
                .environmentObject(model)
        } label: {
            Label(
                model.menuTitle,
                systemImage: model.menuSymbol
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 430)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        if CommandLine.arguments.contains("--unregister-login-item") {
            do {
                try LoginItemManager.shared.setEnabled(false)
                Darwin.exit(EXIT_SUCCESS)
            } catch {
                let message =
                    "Unable to unregister the login item: \(error)\n"
                FileHandle.standardError.write(Data(message.utf8))
                Darwin.exit(EXIT_FAILURE)
            }
        }
        NSApp.setActivationPolicy(.regular)
        BrightnessController.shared.restoreIfNeeded()
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    func applicationWillTerminate(_ notification: Notification) {
        BrightnessController.shared.restoreIfNeeded()
    }
}

final class LoginItemManager {
    static let shared = LoginItemManager()

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
