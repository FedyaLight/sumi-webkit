import Foundation

struct SumiPermissionAuthorizationQuery: Identifiable, Equatable, Sendable {
    let id: String
    let pageId: String
    let profilePartitionId: String
    let displayDomain: String
    let requestingOrigin: SumiPermissionOrigin
    let topOrigin: SumiPermissionOrigin
    let permissionTypes: [SumiPermissionType]
    let presentationPermissionType: SumiPermissionType?
    let availablePersistences: Set<SumiPermissionPersistence>
    let defaultPersistence: SumiPermissionPersistence
    let systemAuthorizationSnapshots: [SumiSystemPermissionSnapshot]
    let policySources: [SumiPermissionDecisionSource]
    let policyReasons: [String]
    let createdAt: Date
    let isEphemeralProfile: Bool
    let hasUserGesture: Bool?
    let shouldOfferSystemSettings: Bool
    let disablesPersistentAllow: Bool
    let requiresSystemAuthorizationPrompt: Bool
}
