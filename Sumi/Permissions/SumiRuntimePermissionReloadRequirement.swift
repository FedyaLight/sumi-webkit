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

    static func == (lhs: SumiRuntimePermissionReloadRequirement, rhs: SumiRuntimePermissionReloadRequirement) -> Bool {
        lhs.kind == rhs.kind
            && lhs.permissionType == rhs.permissionType
            && lhs.reason == rhs.reason
            && lhs.currentAutoplayState == rhs.currentAutoplayState
            && lhs.requestedAutoplayState == rhs.requestedAutoplayState
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(permissionType)
        hasher.combine(reason)
        hasher.combine(currentAutoplayState)
        hasher.combine(requestedAutoplayState)
    }
}
