import Foundation

enum SumiRuntimePermissionOperationResult: Equatable, Hashable, Sendable {
    case applied
    case unsupported(reason: String)
    case requiresReload(SumiRuntimePermissionReloadRequirement)
    case deniedByRuntime(reason: String)
    case noOp
    case failed(reason: String)

}
