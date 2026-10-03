import SwiftUI
import AppKit
import ClaudeSessionCore

/// The menu-bar menu: one row per running session, clicking a row focuses its terminal tab.
struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let sessions = model.liveSorted
        let now = currentMillis()
        ForEach(sessions, id: \.sessionId) { session in
            Button(label(session, now: now)) { model.focus(session) }
                .disabled(!session.isFocusable)
        }
        if !sessions.isEmpty { Divider() }
        Text(summary(total: sessions.count, waiting: model.waitingCount))

        Divider()
        Button("Open Sessions Window") {
            openWindow(id: SessionsWindow.id)
            NSApp.activate()
        }
        .keyboardShortcut("o")

        if model.pluginStatus == .notInstalled {
            Divider()
            Button(model.isInstallingPlugin ? "Installing helper plugin…" : "Install helper plugin…") {
                model.installPlugin()
            }
            .disabled(model.isInstallingPlugin)
        }

        Divider()
        Button("Quit Claude Session Manager") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func label(_ session: LiveSession, now: Int64) -> String {
        var parts = [session.phase.label]
        if let reason = session.waitingReason { parts.append(reason) }
        // Only where the wait is the point: how long a session has been idle answers no question.
        if session.phase == .running || session.phase == .waiting, session.observedAt > 0 {
            parts.append(Duration.milliseconds(max(0, now - session.observedAt)).humanized)
        }
        if !session.isFocusable { parts.append("no tab") }
        return "\(session.phase.dot)  \(session.name) · \(parts.joined(separator: " · "))"
    }

    private func summary(total: Int, waiting: Int) -> String {
        if total == 0 { return "No Claude Code sessions" }
        let sessions = "\(total) session\(total == 1 ? "" : "s")"
        return waiting == 0 ? sessions : "\(sessions) · \(waiting) waiting"
    }
}

enum MenuBarIcon {
    private static let calm = NSColor(red: 0x2F / 255, green: 0x81 / 255, blue: 0xF7 / 255, alpha: 1)
    private static let waiting = NSColor(red: 1, green: 0xA5 / 255, blue: 0, alpha: 1)

    /// A coloured dot: blue when calm, orange when any session is waiting. Not a template image,
    /// so the menu bar keeps its colour.
    static func dot(waiting isWaiting: Bool) -> NSImage {
        let color = isWaiting ? waiting : calm
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    static func tooltip(total: Int, waiting: Int) -> String {
        if total == 0 { return "Claude Session Manager — no sessions" }
        if waiting > 0 { return "Claude Session Manager — \(waiting) waiting of \(total)" }
        return "Claude Session Manager — \(total) session\(total == 1 ? "" : "s")"
    }
}
