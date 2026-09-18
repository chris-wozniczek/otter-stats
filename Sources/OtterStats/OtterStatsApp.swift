import SwiftUI
import AppKit

struct OtterStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = UsageStore()
    @StateObject private var updates = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(store).environmentObject(updates)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarGlyph.image())
                if let title = store.menuBarTitle {
                    Text(title).font(.system(size: 12, weight: .medium).monospacedDigit())
                }
            }
            .task { store.start(); updates.start() }
        }
        .menuBarExtraStyle(.window)

        Window("Otter Stats", id: "dashboard") {
            DashboardView().environmentObject(store)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Refresh") { store.refresh() }.keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView().environmentObject(store).environmentObject(updates)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}
