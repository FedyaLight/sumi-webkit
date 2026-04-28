import Foundation

enum SumiExternalSchemePendingStrategy: Equatable, Sendable {
    case waitForPromptUI
    case promptPresenterUnavailableBlock

    var reason: String {
        switch self {
        case .waitForPromptUI:
            return "external-scheme-prompt-ui-wait"
        case .promptPresenterUnavailableBlock:
            return "external-scheme-prompt-presenter-unavailable-block"
        }
    }

    var waitsForPromptUI: Bool {
        self == .waitForPromptUI
    }
}
