import SwiftUI
import ClaudeSessionCore

/// How a live phase reads and looks, shared by the window and the menu bar so they always agree.
extension Phase {
    var label: String {
        switch self {
        case .waiting: "Waiting"
        case .running: "Working"
        default: "Idle"
        }
    }

    var color: Color {
        switch self {
        case .waiting: .orange
        case .running: .green
        default: .blue
        }
    }

    /// Menu items are text only, so the coloured dot is an emoji matching `color`.
    var dot: String {
        switch self {
        case .waiting: "🟠"
        case .running: "🟢"
        default: "🔵"
        }
    }
}

extension LiveSession {
    /// What the session is waiting on, in words, or nil when it is not waiting.
    var waitingReason: String? {
        phase == .waiting ? NotificationComposer.waitingBody(waitingFor) : nil
    }
}
