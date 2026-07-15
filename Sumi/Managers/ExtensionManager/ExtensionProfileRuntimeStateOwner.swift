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

    private let profileRuntime: ExtensionProfileRuntime
    private let installedExtensions: InstalledExtensionCollection
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority

    init(
        profileRuntime: ExtensionProfileRuntime,
        installedExtensions: InstalledExtensionCollection,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    ) {
        self.profileRuntime = profileRuntime
        self.installedExtensions = installedExtensions
        self.runtimeLifecycle = runtimeLifecycle
    }

    var currentController: WKWebExtensionController? {
        profileRuntime.controllerForCurrentProfile()
    }

    var currentContexts: [String: WKWebExtensionContext] {
        profileRuntime.contextsForCurrentProfile()
    }

    func contexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        profileRuntime.contexts(for: profileId)
    }

    func context(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> WKWebExtensionContext? {
        let resolvedProfileId = profileId ?? profileRuntime.currentProfileId
        guard let resolvedProfileId else { return nil }
        return contexts(for: resolvedProfileId)[extensionId]
    }

    func allLoadedExtensionIDs() -> Set<String> {
        profileRuntime.allLoadedExtensionIDs()
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        profileRuntime.profileId(for: extensionContext)
    }

    func contextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        profileRuntime.contextIdentity(for: extensionContext)
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        profileRuntime.profileId(for: controller)
    }

    func countLoadedContexts() -> Int {
        profileRuntime.countLoadedExtensionContexts()
    }

    func readinessContext(
        for profileId: UUID
    ) -> ExtensionRuntimeReadinessContext {
        let catalogSnapshot = installedExtensions.records
        let enabledExtensionIDs = Set(
            catalogSnapshot.lazy.filter(\.isEnabled).map(\.id)
        )
        return profileRuntime.readinessContext(
            for: profileId,
            hasEnabledExtensionDemand: enabledExtensionIDs.isEmpty == false,
            enabledExtensionIDs: enabledExtensionIDs,
            globalRuntimeReady: runtimeLifecycle.isReady
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
            controller: profileRuntime.controllersByProfile[profileId],
            context: context(for: extensionId, profileId: profileId),
            readiness: readinessContext(for: profileId)
        )
    }
}
