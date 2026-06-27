import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileRuntimeOwner {
    private var state = ExtensionProfileRuntimeState()
    private let websiteDataStoreCache: ExtensionProfileWebsiteDataStoreCache
    var currentProfileId: UUID?

    init(
        initialProfileId: UUID?,
        websiteDataStoreCache: ExtensionProfileWebsiteDataStoreCache =
            ExtensionProfileWebsiteDataStoreCache()
    ) {
        self.currentProfileId = initialProfileId
        self.websiteDataStoreCache = websiteDataStoreCache
    }

    var controllersByProfile: [UUID: WKWebExtensionController] {
        state.controllersByProfile
    }

    var contextsByProfile: [UUID: [String: WKWebExtensionContext]] {
        state.contextsByProfile
    }

    var contextBindingGenerationsByProfile: [UUID: UInt64] {
        state.contextBindingGenerationByProfile
    }

    func replaceControllers(_ controllers: [UUID: WKWebExtensionController]) {
        state.replaceControllers(controllers)
    }

    func replaceContexts(_ contexts: [UUID: [String: WKWebExtensionContext]]) {
        state.replaceContexts(contexts)
    }

    func replaceContextBindingGenerations(_ generations: [UUID: UInt64]) {
        state.replaceContextBindingGenerations(generations)
    }

    func controller(for profileId: UUID) -> WKWebExtensionController? {
        state.controller(for: profileId)
    }

    func controllerForCurrentProfile() -> WKWebExtensionController? {
        guard let currentProfileId else { return nil }
        return state.controller(for: currentProfileId)
    }

    func setController(
        _ controller: WKWebExtensionController,
        for profileId: UUID
    ) {
        state.setController(controller, for: profileId)
    }

    func contextsForCurrentProfile() -> [String: WKWebExtensionContext] {
        guard let currentProfileId else { return [:] }
        return state.contexts(for: currentProfileId)
    }

    func contexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        state.contexts(for: profileId)
    }

    func setContext(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) -> UInt64 {
        state.setContext(
            context,
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func removeContext(
        extensionId: String,
        profileId: UUID
    ) -> (context: WKWebExtensionContext, generation: UInt64)? {
        state.removeContext(extensionId: extensionId, profileId: profileId)
    }

    func contextBindingGeneration(for profileId: UUID) -> UInt64 {
        state.contextBindingGeneration(for: profileId)
    }

    @discardableResult
    func bumpContextBindingGeneration(for profileId: UUID) -> UInt64 {
        state.bumpContextBindingGeneration(for: profileId)
    }

    func allLoadedExtensionIDs() -> Set<String> {
        state.allLoadedExtensionIDs()
    }

    func extensionId(for extensionContext: WKWebExtensionContext) -> String? {
        state.extensionId(for: extensionContext)
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        state.profileId(for: extensionContext)
    }

    func contextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        state.contextIdentity(for: extensionContext)
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        state.profileId(for: controller)
    }

    func countLoadedExtensionContexts() -> Int {
        state.countLoadedExtensionContexts()
    }

    func activateProfile(
        _ profileId: UUID,
        hasExtensionDemand: Bool,
        runtimeIsReadyOrLoading: Bool
    ) -> Bool {
        currentProfileId = profileId
        return controllersByProfile.isEmpty == false
            || hasExtensionDemand
            || runtimeIsReadyOrLoading
    }

    func resolvedProfileId(
        for tab: Tab?,
        browserManager: BrowserManager?
    ) -> UUID? {
        guard let tab else { return currentProfileId }
        if let profileId = tab.profileId {
            return profileId
        }
        if let profile = tab.resolveProfile() {
            return profile.id
        }
        if let windowId = tab.primaryWindowId,
           let windowState = browserManager?.windowRegistry?.windows[windowId]
        {
            return resolvedProfileId(
                for: windowState,
                browserManager: browserManager
            )
        }
        return currentProfileId ?? browserManager?.currentProfile?.id
    }

    func resolvedProfileId(
        explicitProfileId: UUID?,
        browserManager: BrowserManager?
    ) -> UUID? {
        explicitProfileId ?? currentProfileId ?? browserManager?.currentProfile?.id
    }

    func resolvedProfileId(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager?
    ) -> UUID? {
        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            return profile.id
        }
        if let profileId = windowState.currentProfileId {
            return profileId
        }
        return browserManager?.currentProfile?.id
    }

    func windowMatchesProfile(
        _ windowState: BrowserWindowState,
        profileId: UUID,
        browserManager: BrowserManager?
    ) -> Bool {
        resolvedProfileId(
            for: windowState,
            browserManager: browserManager
        ) == profileId
    }

    func currentProfile(in browserManager: BrowserManager?) -> Profile? {
        guard let currentProfileId else { return browserManager?.currentProfile }
        return browserManager?.profileManager.profiles.first {
            $0.id == currentProfileId
        } ?? browserManager?.currentProfile
    }

    func websiteDataStore(
        for profileId: UUID,
        browserManager: BrowserManager?
    ) -> WKWebsiteDataStore {
        websiteDataStoreCache.store(
            for: profileId,
            activeProfile: activeProfile(
                for: profileId,
                browserManager: browserManager
            ),
            currentProfileId: currentProfileId
        )
    }

    func rememberPrivateRuntimeProfileIfNeeded(_ profile: Profile) {
        websiteDataStoreCache.rememberPrivateRuntimeProfileIfNeeded(profile)
    }

    func isPrivateRuntimeProfile(_ profileId: UUID?) -> Bool {
        websiteDataStoreCache.isPrivateRuntimeProfile(profileId)
    }

    func removeAllWebsiteDataStores() {
        websiteDataStoreCache.removeAll()
    }

    private func activeProfile(
        for profileId: UUID,
        browserManager: BrowserManager?
    ) -> Profile? {
        if let profile = browserManager?.profileManager.profiles.first(where: {
            $0.id == profileId
        }) {
            return profile
        }

        return browserManager?.windowRegistry?.windows.values
            .compactMap(\.ephemeralProfile)
            .first(where: { $0.id == profileId })
    }
}
