import Foundation

enum SumiRuntimePermissionOperationResult: Equatable, Hashable, Sendable {
    case applied
    case unsupported(reason: String)
    case requiresReload(SumiRuntimePermissionReloadRequirement)
    case deniedByRuntime(reason: String)
    case noOp
    case failed(reason: String)

    var isSuccessfulNoThrowResult: Bool {
        switch self {
        case .applied, .noOp, .requiresReload:
            return true
        case .unsupported, .deniedByRuntime, .failed:
            return false
        }
    }
}
