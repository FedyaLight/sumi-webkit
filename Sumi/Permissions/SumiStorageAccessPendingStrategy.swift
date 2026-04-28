import Foundation

enum SumiStorageAccessPendingStrategy: Equatable, Sendable {
    case waitForPromptUI
    case denyUntilPromptUIExists

    var reason: String {
        switch self {
        case .waitForPromptUI:
            return "webkit-storage-access-prompt-ui-wait"
        case .denyUntilPromptUIExists:
            return "webkit-storage-access-prompt-ui-unavailable-deny"
        }
    }

    var waitsForPromptUI: Bool {
        self == .waitForPromptUI
    }
}
