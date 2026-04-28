import Foundation

enum SumiStorageAccessPendingStrategy: Equatable, Sendable {
    case denyUntilPromptUIExists

    var reason: String {
        switch self {
        case .denyUntilPromptUIExists:
            return "webkit-storage-access-prompt-ui-unavailable-deny"
        }
    }
}
