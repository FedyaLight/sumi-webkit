import Foundation

enum SumiPopupPendingStrategy: Equatable, Sendable {
    case blockUntilPromptUIExists

    var reason: String {
        switch self {
        case .blockUntilPromptUIExists:
            return "popup-prompt-ui-unavailable-block"
        }
    }
}

