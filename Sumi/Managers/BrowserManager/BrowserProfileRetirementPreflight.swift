import Foundation

/// Completes the fallible runtime preparation that must precede any browser-
/// shell reference mutation.
@MainActor
final class BrowserProfileRetirementPreflight {
    private let currentProfile: @MainActor () -> Profile?
    private let switchToProfile: @MainActor (Profile) async -> Void
    private let prepareLiveFolderReferences: @MainActor () async -> Bool
    private let retireExtensionRuntimeProfile: @MainActor (UUID, UUID) -> Bool

    init(
        currentProfile: @escaping @MainActor () -> Profile?,
        switchToProfile: @escaping @MainActor (Profile) async -> Void,
        prepareLiveFolderReferences: @escaping @MainActor () async -> Bool,
        retireExtensionRuntimeProfile: @escaping @MainActor (
            UUID,
            UUID
        ) -> Bool
    ) {
        self.currentProfile = currentProfile
        self.switchToProfile = switchToProfile
        self.prepareLiveFolderReferences = prepareLiveFolderReferences
        self.retireExtensionRuntimeProfile = retireExtensionRuntimeProfile
    }

    func prepare(
        deletedProfileID: UUID,
        fallbackProfile: Profile
    ) async -> Bool {
        if currentProfile()?.id == deletedProfileID {
            await switchToProfile(fallbackProfile)
            guard currentProfile()?.id == fallbackProfile.id else {
                return false
            }
        }

        return await prepareLiveFolderReferences()
            && retireExtensionRuntimeProfile(
                deletedProfileID,
                fallbackProfile.id
            )
    }
}
