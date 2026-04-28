import Foundation

enum SumiNotificationPendingStrategy: Equatable, Sendable {
    case waitForPromptUI
    case denyUntilPromptUIExists

    var reason: String {
        switch self {
        case .waitForPromptUI:
            return "notification-prompt-ui-wait"
        case .denyUntilPromptUIExists:
            return "notification-prompt-ui-unavailable-deny"
        }
    }

    var waitsForPromptUI: Bool {
        self == .waitForPromptUI
    }
}
