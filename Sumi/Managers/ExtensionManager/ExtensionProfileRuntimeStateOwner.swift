import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionProfileRuntimeStateOwner {
    @MainActor
    struct ExtensionSnapshot {
        let extensionId: String
        let profileId: UUID
        let controller: WKWebExtensionController?
        let context: WKWebExtensionContext?
        let readiness: ExtensionRuntimeReadinessContext

        var controllerExists: Bool {
            controller != nil
        }

        var contextExists: Bool {
            context != nil
        }

        var contextLoaded: Bool {
            context?.isLoaded ?? false
        }

        var missingEnabledExtensionIDs: [String] {
            readiness.missingEnabledExtensionIDs
        }
    }

    private let manager: ExtensionManager

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    var currentController: WKWebExtensionController? {
        manager.profileRuntime.controllerForCurrentProfile()
    }

    var currentContexts: [String: WKWebExtensionContext] {
        manager.profileRuntime.contextsForCurrentProfile()
    }

    func contexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        manager.profileRuntime.contexts(for: profileId)
    }

    func context(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> WKWebExtensionContext? {
        let resolvedProfileId = manager.resolvedProfileId(
            explicitProfileId: profileId
        )
        guard let resolvedProfileId else { return nil }
        return contexts(for: resolvedProfileId)[extensionId]
    }

    func allLoadedExtensionIDs() -> Set<String> {
        manager.profileRuntime.allLoadedExtensionIDs()
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        manager.profileRuntime.profileId(for: extensionContext)
    }

    func contextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        manager.profileRuntime.contextIdentity(for: extensionContext)
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        manager.profileRuntime.profileId(for: controller)
    }

    func countLoadedContexts() -> Int {
        manager.profileRuntime.countLoadedExtensionContexts()
    }

    func readinessContext(
        for profileId: UUID
    ) -> ExtensionRuntimeReadinessContext {
        manager.profileRuntime.readinessContext(
            for: profileId,
            hasEnabledExtensionDemand: manager.hasEnabledInstalledExtensions,
            enabledExtensionIDs: Set(manager.enabledPersistedExtensionEntities().map(\.id)),
            globalRuntimeReady: manager.runtimeSession.runtimeState == .ready
        )
    }

    func missingEnabledExtensionIDs(for profileId: UUID) -> [String] {
        readinessContext(for: profileId).missingEnabledExtensionIDs
    }

    func isProfileReady(for profileId: UUID) -> Bool {
        readinessContext(for: profileId).isProfileReady
    }

    func isExtensionReady(
        extensionId: String,
        profileId: UUID
    ) -> Bool {
        readinessContext(for: profileId)
            .isExtensionReady(extensionID: extensionId)
    }

    func extensionSnapshot(
        extensionId: String,
        profileId: UUID
    ) -> ExtensionSnapshot {
        ExtensionSnapshot(
            extensionId: extensionId,
            profileId: profileId,
            controller: manager.profileRuntime.controllersByProfile[profileId],
            context: context(for: extensionId, profileId: profileId),
            readiness: readinessContext(for: profileId)
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    var extensionController: WKWebExtensionController? {
        profileRuntimeStateOwner.currentController
    }

    var extensionContexts: [String: WKWebExtensionContext] {
        profileRuntimeStateOwner.currentContexts
    }

    func extensionContexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        profileRuntimeStateOwner.contexts(for: profileId)
    }

    func setExtensionContext(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        let generation = profileRuntime.setContext(
            context,
            extensionId: extensionId,
            profileId: profileId
        )
        traceExtensionContextBindingGeneration(
            profileId: profileId,
            generation: generation,
            reason: "setExtensionContext"
        )
    }

    func extensionContextBindingGeneration(for profileId: UUID) -> UInt64 {
        profileRuntime.contextBindingGeneration(for: profileId)
    }

    func bumpExtensionContextBindingGeneration(
        for profileId: UUID,
        reason: String
    ) {
        let next = profileRuntime.bumpContextBindingGeneration(for: profileId)
        traceExtensionContextBindingGeneration(
            profileId: profileId,
            generation: next,
            reason: reason
        )
    }

    private func traceExtensionContextBindingGeneration(
        profileId: UUID,
        generation: UInt64,
        reason: String
    ) {
        runtimeDiagnostics.trace(
            "extensionContextBindingGeneration profile=\(profileId.uuidString) generation=\(generation) reason=\(reason)"
        )
    }

    @discardableResult
    func removeExtensionContext(
        extensionId: String,
        profileId: UUID
    ) -> WKWebExtensionContext? {
        guard let removed = profileRuntime.removeContext(
            extensionId: extensionId,
            profileId: profileId
        ) else { return nil }
        traceExtensionContextBindingGeneration(
            profileId: profileId,
            generation: removed.generation,
            reason: "removeExtensionContext"
        )
        return removed.context
    }

    func allLoadedExtensionIDs() -> Set<String> {
        profileRuntimeStateOwner.allLoadedExtensionIDs()
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        profileRuntimeStateOwner.profileId(for: extensionContext)
    }

    func contextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        profileRuntimeStateOwner.contextIdentity(for: extensionContext)
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        profileRuntimeStateOwner.profileId(for: controller)
    }

    func resolvedProfileId(for tab: Tab?) -> UUID? {
        profileRuntime.resolvedProfileId(
            for: tab,
            runtime: runtime
        )
    }

    func resolvedProfileId(for windowState: BrowserWindowState) -> UUID? {
        profileRuntime.resolvedProfileId(
            for: windowState,
            runtime: runtime
        )
    }

    func resolvedProfileId(explicitProfileId: UUID?) -> UUID? {
        profileRuntime.resolvedProfileId(
            explicitProfileId: explicitProfileId,
            runtime: runtime
        )
    }

    var fallbackProfileId: UUID? {
        resolvedProfileId(explicitProfileId: nil)
    }

    func isPrivateExtensionRuntimeProfile(_ profileId: UUID?) -> Bool {
        profileRuntime.isPrivateRuntimeProfile(profileId)
    }

    func windowMatchesProfile(
        _ windowState: BrowserWindowState,
        profileId: UUID
    ) -> Bool {
        profileRuntime.windowMatchesProfile(
            windowState,
            profileId: profileId,
            runtime: runtime
        )
    }

    func getExtensionContext(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> WKWebExtensionContext? {
        profileRuntimeStateOwner.context(for: extensionId, profileId: profileId)
    }

    func missingEnabledExtensionIDs(for profileId: UUID) -> [String] {
        profileRuntimeStateOwner.missingEnabledExtensionIDs(for: profileId)
    }

    func isProfileExtensionRuntimeReady(for profileId: UUID) -> Bool {
        profileRuntimeStateOwner.isProfileReady(for: profileId)
    }

    func isExtensionRuntimeReady(
        extensionId: String,
        profileId: UUID
    ) -> Bool {
        profileRuntimeStateOwner.isExtensionReady(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func extensionRuntimeReadinessContext(
        for profileId: UUID
    ) -> ExtensionRuntimeReadinessContext {
        profileRuntimeStateOwner.readinessContext(for: profileId)
    }

    func countLoadedExtensionContexts() -> Int {
        profileRuntimeStateOwner.countLoadedContexts()
    }
}
