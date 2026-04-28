import Foundation

enum SumiStorageAccessPendingStrategy: Equatable, Sendable {
    case waitForPromptUI
    case promptPresenterUnavailableDeny

    var reason: String {
        switch self {
        case .waitForPromptUI:
            return "webkit-storage-access-prompt-ui-wait"
        case .promptPresenterUnavailableDeny:
            return "webkit-storage-access-prompt-presenter-unavailable-deny"
        }
    }

    var waitsForPromptUI: Bool {
        self == .waitForPromptUI
    }
}
