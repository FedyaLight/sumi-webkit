import Foundation

enum SumiPopupPendingStrategy: Equatable, Sendable {
    case backgroundPromptUnavailableBlock

    var reason: String {
        switch self {
        case .backgroundPromptUnavailableBlock:
            return "popup-background-prompt-unavailable-block"
        }
    }
}
