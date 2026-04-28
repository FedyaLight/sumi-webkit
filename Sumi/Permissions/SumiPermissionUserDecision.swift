import Foundation

enum SumiPermissionUserDecision: Equatable, Sendable {
    case approveOnce
    case approveForSession
    case approvePersistently
    case denyOnce
    case denyForSession
    case dismiss
    case denyPersistently
    case setAskPersistently
    case cancel(reason: String)
    case expire(reason: String)
}
