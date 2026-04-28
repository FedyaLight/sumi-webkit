import Foundation

enum SumiNotificationPendingStrategy: Equatable, Sendable {
    case denyUntilPromptUIExists

    var reason: String {
        switch self {
        case .denyUntilPromptUIExists:
            return "notification-prompt-ui-unavailable-deny"
        }
    }
}
