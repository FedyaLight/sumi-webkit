import Foundation

/// The durable scope for browser site-permission decisions shared by every
/// regular Browser Profile. Private and one-time decisions never enter it.
public enum SumiGlobalSitePermissionScope {
    public static let profilePartitionId = "local-installation"

    public static func applies(to key: SumiPermissionKey) -> Bool {
        !key.isEphemeralProfile && key.permissionType.canBePersisted
    }

    public static func isGlobal(_ key: SumiPermissionKey) -> Bool {
        !key.isEphemeralProfile && key.profilePartitionId == profilePartitionId
    }

    public static func storageKey(for key: SumiPermissionKey) -> SumiPermissionKey {
        guard applies(to: key) else { return key }
        return SumiPermissionKey(
            requestingOrigin: key.requestingOrigin,
            topOrigin: key.topOrigin,
            permissionType: key.permissionType,
            profilePartitionId: profilePartitionId
        )
    }

    public static func presentationKey(
        for storageKey: SumiPermissionKey,
        profilePartitionId: String
    ) -> SumiPermissionKey {
        guard isGlobal(storageKey) else { return storageKey }
        return SumiPermissionKey(
            requestingOrigin: storageKey.requestingOrigin,
            topOrigin: storageKey.topOrigin,
            permissionType: storageKey.permissionType,
            profilePartitionId: profilePartitionId
        )
    }
}
