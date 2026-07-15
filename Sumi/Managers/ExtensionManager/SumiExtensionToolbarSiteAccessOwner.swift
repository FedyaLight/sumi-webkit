import Foundation

/// Toolbar pinning + site-access policy surface for `SumiExtensionsModule`.
@MainActor
final class SumiExtensionToolbarSiteAccessOwner {
    typealias LoadedRuntimeProvider = @MainActor () -> ExtensionToolbarRuntime?
    typealias EnabledRuntimeProvider = @MainActor () -> ExtensionToolbarRuntime?
    typealias CurrentProfileIDProvider = @MainActor () -> UUID?

    private let runtimeIfLoadedAndEnabled: LoadedRuntimeProvider
    private let runtimeIfEnabled: EnabledRuntimeProvider
    private let fallbackProfileId: CurrentProfileIDProvider

    init(
        runtimeIfLoadedAndEnabled: @escaping LoadedRuntimeProvider,
        runtimeIfEnabled: @escaping EnabledRuntimeProvider,
        fallbackProfileId: @escaping CurrentProfileIDProvider
    ) {
        self.runtimeIfLoadedAndEnabled = runtimeIfLoadedAndEnabled
        self.runtimeIfEnabled = runtimeIfEnabled
        self.fallbackProfileId = fallbackProfileId
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [BrowserExtensionToolbarDisplayRecord],
        profileId: UUID?
    ) -> [PinnedToolbarSlot] {
        guard let runtime = runtimeIfLoadedAndEnabled() else { return [] }
        return runtime.ordering.orderedPinnedSlots(
            enabledExtensions: enabledExtensions,
            profileID: profileId
        )
    }

    func pinnedToolbarExtensionIDs(profileId: UUID?) -> [String] {
        runtimeIfLoadedAndEnabled()?.ordering.pinnedExtensionIDs(
            profileID: profileId
        ) ?? []
    }

    @discardableResult
    func pinToToolbar(_ extensionId: String, profileId: UUID?) -> Bool {
        runtimeIfEnabled()?.ordering.pin(
            extensionId,
            profileID: profileId
        ) ?? false
    }

    @discardableResult
    func unpinFromToolbar(_ extensionId: String, profileId: UUID?) -> Bool {
        runtimeIfEnabled()?.ordering.unpin(
            extensionId,
            profileID: profileId
        ) ?? false
    }

    @discardableResult
    func movePinnedToolbarSlot(
        id: String,
        to targetIndex: Int,
        profileId: UUID?
    ) -> Bool {
        runtimeIfEnabled()?.ordering.movePinned(
            id: id,
            to: targetIndex,
            profileID: profileId
        ) ?? false
    }

    func orderedUnpinnedExtensionIDs(
        candidateIDs: [String],
        profileId: UUID?
    ) -> [String] {
        guard let runtime = runtimeIfLoadedAndEnabled() else { return candidateIDs }
        return runtime.ordering.orderedUnpinned(
            candidateIDs: candidateIDs,
            profileID: profileId
        )
    }

    @discardableResult
    func moveUnpinnedExtension(
        id: String,
        to targetIndex: Int,
        within currentOrder: [String],
        profileId: UUID?
    ) -> Bool {
        runtimeIfEnabled()?.ordering.moveUnpinned(
            id: id,
            to: targetIndex,
            within: currentOrder,
            profileID: profileId
        ) ?? false
    }

    func siteAccessPolicy(
        extensionId: String,
        profileId: UUID?
    ) -> SafariExtensionSiteAccessPolicy? {
        guard let runtime = runtimeIfEnabled() else { return nil }
        guard let resolvedProfileId = resolvedProfileId(
            profileId,
            runtime: runtime.siteAccess
        ) else { return nil }
        return runtime.siteAccess.policy(
            extensionID: extensionId,
            profileID: resolvedProfileId
        )
    }

    func setDefaultSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID?
    ) {
        guard let runtime = runtimeIfEnabled() else { return }
        guard let resolvedProfileId = resolvedProfileId(
            profileId,
            runtime: runtime.siteAccess
        ) else { return }
        runtime.siteAccess.setDefault(
            access,
            extensionID: extensionId,
            profileID: resolvedProfileId
        )
    }

    func setPrivateBrowsingAccess(
        _ isAllowed: Bool,
        extensionId: String,
        profileId: UUID?
    ) {
        guard let runtime = runtimeIfEnabled() else { return }
        guard let resolvedProfileId = resolvedProfileId(
            profileId,
            runtime: runtime.siteAccess
        ) else { return }
        runtime.siteAccess.setPrivateBrowsing(
            isAllowed,
            extensionID: extensionId,
            profileID: resolvedProfileId
        )
    }

    func setConfiguredSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID?,
        matchPatternString: String
    ) {
        guard let runtime = runtimeIfEnabled() else { return }
        guard let resolvedProfileId = resolvedProfileId(
            profileId,
            runtime: runtime.siteAccess
        ) else { return }
        runtime.siteAccess.setConfigured(
            access,
            extensionID: extensionId,
            profileID: resolvedProfileId,
            matchPatternString: matchPatternString
        )
    }

    private func resolvedProfileId(
        _ profileId: UUID?,
        runtime: ExtensionToolbarSiteAccessRuntime
    ) -> UUID? {
        runtime.resolvedProfileID(profileId) ?? fallbackProfileId()
    }
}
