import Foundation

/// Toolbar pinning + site-access policy surface for `SumiExtensionsModule`.
@MainActor
final class SumiExtensionToolbarSiteAccessOwner {
    typealias LoadedManagerProvider = @MainActor () -> ExtensionManager?
    typealias EnabledManagerProvider = @MainActor () -> ExtensionManager?
    typealias CurrentProfileIDProvider = @MainActor () -> UUID?
    typealias StructuralRevisionInvalidator = @MainActor () -> Void

    private let managerIfLoadedAndEnabled: LoadedManagerProvider
    private let managerIfEnabled: EnabledManagerProvider
    private let fallbackProfileId: CurrentProfileIDProvider
    private let invalidateTabStructuralRevision: StructuralRevisionInvalidator

    init(
        managerIfLoadedAndEnabled: @escaping LoadedManagerProvider,
        managerIfEnabled: @escaping EnabledManagerProvider,
        fallbackProfileId: @escaping CurrentProfileIDProvider,
        invalidateTabStructuralRevision: @escaping StructuralRevisionInvalidator
    ) {
        self.managerIfLoadedAndEnabled = managerIfLoadedAndEnabled
        self.managerIfEnabled = managerIfEnabled
        self.fallbackProfileId = fallbackProfileId
        self.invalidateTabStructuralRevision = invalidateTabStructuralRevision
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        profileId: UUID?
    ) -> [PinnedToolbarSlot] {
        guard let manager = managerIfLoadedAndEnabled() else { return [] }
        return manager.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileId: profileId ?? manager.profileRuntime.currentProfileId
        )
    }

    func isPinnedToToolbar(_ extensionId: String) -> Bool {
        managerIfLoadedAndEnabled()?.isPinnedToToolbar(extensionId) ?? false
    }

    func pinToToolbar(_ extensionId: String) {
        managerIfEnabled()?.pinToToolbar(extensionId)
        invalidateTabStructuralRevision()
    }

    func unpinFromToolbar(_ extensionId: String) {
        managerIfEnabled()?.unpinFromToolbar(extensionId)
        invalidateTabStructuralRevision()
    }

    func movePinnedToolbarSlot(id: String, to targetIndex: Int) {
        managerIfEnabled()?.movePinnedToolbarSlot(id: id, to: targetIndex)
        invalidateTabStructuralRevision()
    }

    func orderedUnpinnedExtensionIDs(
        candidateIDs: [String],
        profileId: UUID?
    ) -> [String] {
        guard let manager = managerIfLoadedAndEnabled() else { return candidateIDs }
        return manager.orderedUnpinnedExtensionIDs(
            candidateIDs: candidateIDs,
            profileId: profileId
        )
    }

    func moveUnpinnedExtension(
        id: String,
        to targetIndex: Int,
        within currentOrder: [String]
    ) {
        managerIfEnabled()?.moveUnpinnedExtension(
            id: id,
            to: targetIndex,
            within: currentOrder
        )
        invalidateTabStructuralRevision()
    }

    func siteAccessPolicy(
        extensionId: String,
        profileId: UUID?
    ) -> SafariExtensionSiteAccessPolicy? {
        guard let manager = managerIfEnabled() else { return nil }
        guard let resolvedProfileId = resolvedProfileId(
            profileId,
            manager: manager
        ) else { return nil }
        return manager.siteAccessPolicy(
            extensionId: extensionId,
            profileId: resolvedProfileId
        )
    }

    func setDefaultSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID?
    ) {
        guard let manager = managerIfEnabled() else { return }
        guard let resolvedProfileId = resolvedProfileId(
            profileId,
            manager: manager
        ) else { return }
        manager.setDefaultSiteAccess(
            access,
            extensionId: extensionId,
            profileId: resolvedProfileId
        )
    }

    func setPrivateBrowsingAccess(
        _ isAllowed: Bool,
        extensionId: String,
        profileId: UUID?
    ) {
        guard let manager = managerIfEnabled() else { return }
        guard let resolvedProfileId = resolvedProfileId(
            profileId,
            manager: manager
        ) else { return }
        manager.setPrivateBrowsingAccess(
            isAllowed,
            extensionId: extensionId,
            profileId: resolvedProfileId
        )
    }

    func setConfiguredSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID?,
        matchPatternString: String
    ) {
        guard let manager = managerIfEnabled() else { return }
        guard let resolvedProfileId = resolvedProfileId(
            profileId,
            manager: manager
        ) else { return }
        manager.setConfiguredSiteAccess(
            access,
            extensionId: extensionId,
            profileId: resolvedProfileId,
            matchPatternString: matchPatternString
        )
    }

    private func resolvedProfileId(
        _ profileId: UUID?,
        manager: ExtensionManager
    ) -> UUID? {
        profileId
            ?? manager.profileRuntime.currentProfileId
            ?? fallbackProfileId()
    }
}
