import Foundation

struct SumiRuntimePermissionReloadRequirement: Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case reload
        case rebuild
    }

    var kind: Kind
    var permissionType: SumiPermissionType
    var reason: String
    var currentAutoplayState: SumiRuntimeAutoplayState?
    var requestedAutoplayState: SumiRuntimeAutoplayState?

    init(
        kind: Kind,
        permissionType: SumiPermissionType,
        reason: String,
        currentAutoplayState: SumiRuntimeAutoplayState? = nil,
        requestedAutoplayState: SumiRuntimeAutoplayState? = nil
    ) {
        self.kind = kind
        self.permissionType = permissionType
        self.reason = reason
        self.currentAutoplayState = currentAutoplayState
        self.requestedAutoplayState = requestedAutoplayState
    }
}
