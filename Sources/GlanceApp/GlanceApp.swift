import AppKit
import SwiftUI

@main
struct GlanceAppMain: App {
    static let settingsWindowID = "settings"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = GlanceStore()
    @StateObject private var updater = GlanceUpdater()
    @Environment(\.openWindow) private var openWindow
    private let appMetadata = GlanceAppMetadata()

    var body: some Scene {
        MenuBarExtra("Glance", systemImage: store.statusIconName) {
            MenuContentView(store: store)
        }
        .menuBarExtraStyle(.window)

        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(appMetadata.aboutMenuTitle) {
                    appMetadata.showAboutPanel()
                }

                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: Self.settingsWindowID)
                    DispatchQueue.main.async {
                        NSApp.windows
                            .first(where: { $0.identifier?.rawValue == Self.settingsWindowID || $0.title == "Settings" })?
                            .center()
                    }
                }
                .keyboardShortcut(",")
            }
        }

        Window("Settings", id: Self.settingsWindowID) {
            GlanceSettingsView(store: store, updater: updater)
        }
    }
}
