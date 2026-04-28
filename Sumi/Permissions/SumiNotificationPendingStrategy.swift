import Foundation

enum SumiNotificationPendingStrategy: Equatable, Sendable {
    case waitForPromptUI
    case promptPresenterUnavailableDeny

    var reason: String {
        switch self {
        case .waitForPromptUI:
            return "notification-prompt-ui-wait"
        case .promptPresenterUnavailableDeny:
            return "notification-prompt-presenter-unavailable-deny"
        }
    }

    var waitsForPromptUI: Bool {
        self == .waitForPromptUI
    }
}
