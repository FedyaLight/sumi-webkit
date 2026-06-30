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

    func inactiveLoadedContextIdentities(
        keepingProfileId: UUID
    ) -> [(profileId: UUID, extensionId: String)] {
        state.inactiveLoadedContextIdentities(keepingProfileId: keepingProfileId)
    }

    func readinessContext(
        for profileId: UUID,
        hasEnabledExtensionDemand: Bool,
        enabledExtensionIDs: Set<String>,
        globalRuntimeReady: Bool
    ) -> ExtensionRuntimeReadinessContext {
        state.readinessContext(
            for: profileId,
            hasEnabledExtensionDemand: hasEnabledExtensionDemand,
            enabledExtensionIDs: enabledExtensionIDs,
            globalRuntimeReady: globalRuntimeReady
        )
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
        runtime: ExtensionManagerRuntime
    ) -> UUID? {
        guard let tab else { return currentProfileId }
        if let profileId = tab.profileId {
            return profileId
        }
        if let profile = tab.resolveProfile() {
            return profile.id
        }
        if let windowId = tab.primaryWindowId,
           let windowState = runtime.windowState(windowId) {
            return resolvedProfileId(
                for: windowState,
                runtime: runtime
            )
        }
        return currentProfileId ?? runtime.currentProfile()?.id
    }

    func resolvedProfileId(
        explicitProfileId: UUID?,
        runtime: ExtensionManagerRuntime
    ) -> UUID? {
        explicitProfileId ?? currentProfileId ?? runtime.currentProfile()?.id
    }

    func resolvedProfileId(
        for windowState: BrowserWindowState,
        runtime: ExtensionManagerRuntime
    ) -> UUID? {
        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            return profile.id
        }
        if let profileId = windowState.currentProfileId {
            return profileId
        }
        return runtime.currentProfile()?.id
    }

    func windowMatchesProfile(
        _ windowState: BrowserWindowState,
        profileId: UUID,
        runtime: ExtensionManagerRuntime
    ) -> Bool {
        resolvedProfileId(
            for: windowState,
            runtime: runtime
        ) == profileId
    }

    func currentProfile(in runtime: ExtensionManagerRuntime) -> Profile? {
        guard let currentProfileId else { return runtime.currentProfile() }
        return runtime.profile(currentProfileId) ?? runtime.currentProfile()
    }

    func websiteDataStore(
        for profileId: UUID,
        runtime: ExtensionManagerRuntime
    ) -> WKWebsiteDataStore {
        websiteDataStoreCache.store(
            for: profileId,
            activeProfile: activeProfile(
                for: profileId,
                runtime: runtime
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
        runtime: ExtensionManagerRuntime
    ) -> Profile? {
        if let profile = runtime.profile(profileId) {
            return profile
        }

        return runtime.ephemeralProfile(profileId)
    }
}
