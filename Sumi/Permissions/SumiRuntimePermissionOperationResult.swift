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

struct SumiRuntimePermissionBatchResult: Equatable, Sendable {
    var resultsByPermissionType: [SumiPermissionType: SumiRuntimePermissionOperationResult]

    init(_ resultsByPermissionType: [SumiPermissionType: SumiRuntimePermissionOperationResult] = [:]) {
        self.resultsByPermissionType = resultsByPermissionType
    }

    subscript(permissionType: SumiPermissionType) -> SumiRuntimePermissionOperationResult? {
        resultsByPermissionType[permissionType]
    }

    var hasFailure: Bool {
        resultsByPermissionType.values.contains { result in
            switch result {
            case .failed, .deniedByRuntime:
                return true
            case .applied, .unsupported, .requiresReload, .noOp:
                return false
            }
        }
    }
}
