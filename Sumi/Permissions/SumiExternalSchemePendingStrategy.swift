import Foundation

enum SumiExternalSchemePendingStrategy: Equatable, Sendable {
    case waitForPromptUI
    case blockUntilPromptUIExists

    var reason: String {
        switch self {
        case .waitForPromptUI:
            return "external-scheme-prompt-ui-wait"
        case .blockUntilPromptUIExists:
            return "external-scheme-prompt-ui-unavailable-block"
        }
    }

    var waitsForPromptUI: Bool {
        self == .waitForPromptUI
    }
}
