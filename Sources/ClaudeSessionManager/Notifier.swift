import Foundation
import UserNotifications
import ClaudeSessionCore

/// Posts notifications and turns a click into focusing that notification's own session.
///
/// Needs a real app bundle: `UNUserNotificationCenter` crashes in a bare `swift run` executable,
/// so it is skipped there.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onClick: (String?) -> Void = { _ in }

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func start() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ notification: SessionNotification) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        if let url = notification.focusUrl { content.userInfo = ["focusUrl": url] }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let url = response.notification.request.content.userInfo["focusUrl"] as? String
        Task { @MainActor in self.onClick(url) }
        completionHandler()
    }
}
