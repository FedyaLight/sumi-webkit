import AppKit
import Foundation

@MainActor
final class BrowserProfileSwitchFeedback {
    private weak var notifications: BrowserNotificationPresenter?

    init(notifications: BrowserNotificationPresenter) {
        self.notifications = notifications
    }

    func present(for profile: Profile, in window: BrowserWindowState?) {
        notifications?.presentProfileSwitchNotification(
            to: profile,
            in: window
        )
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .drawCompleted
        )
    }
}
