import Foundation

enum SumiPermissionPromptAction: String, Equatable, Hashable, Sendable {
    case allowWhileVisiting
    case allowThisTime
    case allow
    case dontAllow
    case openThisTime
    case alwaysAllowExternal
    case openSystemSettings
    case dismiss
}
