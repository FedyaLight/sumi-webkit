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
        manager.profileRuntimeOwner.controllerForCurrentProfile()
    }

    var currentContexts: [String: WKWebExtensionContext] {
        manager.profileRuntimeOwner.contextsForCurrentProfile()
    }

    func contexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        manager.profileRuntimeOwner.contexts(for: profileId)
    }

    func context(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> WKWebExtensionContext? {
        let resolvedProfileId = manager.profileRuntimeOwner.resolvedProfileId(
            explicitProfileId: profileId,
            browserManager: manager.browserManager
        )
        guard let resolvedProfileId else { return nil }
        return contexts(for: resolvedProfileId)[extensionId]
    }

    func allLoadedExtensionIDs() -> Set<String> {
        manager.profileRuntimeOwner.allLoadedExtensionIDs()
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        manager.profileRuntimeOwner.profileId(for: extensionContext)
    }

    func contextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        manager.profileRuntimeOwner.contextIdentity(for: extensionContext)
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        manager.profileRuntimeOwner.profileId(for: controller)
    }

    func countLoadedContexts() -> Int {
        manager.profileRuntimeOwner.countLoadedExtensionContexts()
    }

    func readinessContext(
        for profileId: UUID
    ) -> ExtensionRuntimeReadinessContext {
        manager.profileRuntimeOwner.readinessContext(
            for: profileId,
            hasEnabledExtensionDemand: manager.hasEnabledInstalledExtensions,
            enabledExtensionIDs: Set(manager.enabledPersistedExtensionEntities().map(\.id)),
            globalRuntimeReady: manager.runtimeState == .ready
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
            controller: manager.extensionControllersByProfile[profileId],
            context: context(for: extensionId, profileId: profileId),
            readiness: readinessContext(for: profileId)
        )
    }
}
