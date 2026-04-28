import Foundation

enum SumiExternalSchemePendingStrategy: Equatable, Sendable {
    case blockUntilPromptUIExists

    var reason: String {
        switch self {
        case .blockUntilPromptUIExists:
            return "external-scheme-prompt-ui-unavailable-block"
        }
    }
}
