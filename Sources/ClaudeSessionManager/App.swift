import SwiftUI
import AppKit

@main
struct ClaudeSessionManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            Image(nsImage: MenuBarIcon.dot(waiting: model.waitingCount > 0))
                .help(MenuBarIcon.tooltip(total: model.live.count, waiting: model.waitingCount))
        }
        .menuBarExtraStyle(.menu)

        Window("Claude Sessions", id: SessionsWindow.id) {
            SessionsWindow()
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 400)
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") { model.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Menu bar only until the window opens. Info.plist says so too (LSUIElement); this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        // Before launch finishes, so a click on a notification that launched the app is delivered.
        MainActor.assumeIsolated { AppModel.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
