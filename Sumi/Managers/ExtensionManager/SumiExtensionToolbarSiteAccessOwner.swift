import Foundation

/// Toolbar pinning + site-access policy surface for `SumiExtensionsModule`.
@MainActor
final class SumiExtensionToolbarSiteAccessOwner {
    typealias LoadedManagerProvider = @MainActor () -> ExtensionManager?
    typealias EnabledManagerProvider = @MainActor () -> ExtensionManager?
    typealias CurrentProfileIDProvider = @MainActor () -> UUID?
    private let managerIfLoadedAndEnabled: LoadedManagerProvider
    private let managerIfEnabled: EnabledManagerProvider
    private let fallbackProfileId: CurrentProfileIDProvider

    init(
        managerIfLoadedAndEnabled: @escaping LoadedManagerProvider,
        managerIfEnabled: @escaping EnabledManagerProvider,
        fallbackProfileId: @escaping CurrentProfileIDProvider
    ) {
        self.managerIfLoadedAndEnabled = managerIfLoadedAndEnabled
        self.managerIfEnabled = managerIfEnabled
        self.fallbackProfileId = fallbackProfileId
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [BrowserExtensionToolbarDisplayRecord],
        profileId: UUID?
    ) -> [PinnedToolbarSlot] {
        guard let manager = managerIfLoadedAndEnabled() else { return [] }
        return manager.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileId: profileId
        )
    }

    func pinnedToolbarExtensionIDs(profileId: UUID?) -> [String] {
        managerIfLoadedAndEnabled()?.pinnedToolbarExtensionIDs(
            profileId: profileId
        ) ?? []
    }

    @discardableResult
    func pinToToolbar(_ extensionId: String, profileId: UUID?) -> Bool {
        managerIfEnabled()?.pinToToolbar(
            extensionId,
            profileId: profileId
        ) ?? false
    }

    @discardableResult
    func unpinFromToolbar(_ extensionId: String, profileId: UUID?) -> Bool {
        managerIfEnabled()?.unpinFromToolbar(
            extensionId,
            profileId: profileId
        ) ?? false
    }

    @discardableResult
    func movePinnedToolbarSlot(
        id: String,
        to targetIndex: Int,
        profileId: UUID?
    ) -> Bool {
        managerIfEnabled()?.movePinnedToolbarSlot(
            id: id,
            to: targetIndex,
            profileId: profileId
        ) ?? false
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

    @discardableResult
    func moveUnpinnedExtension(
        id: String,
        to targetIndex: Int,
        within currentOrder: [String],
        profileId: UUID?
    ) -> Bool {
        managerIfEnabled()?.moveUnpinnedExtension(
            id: id,
            to: targetIndex,
            within: currentOrder,
            profileId: profileId
        ) ?? false
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
