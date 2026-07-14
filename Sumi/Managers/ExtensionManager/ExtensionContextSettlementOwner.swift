import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextSettlementOwner {
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private let installedExtensions: InstalledExtensionCollection
    private let markPublicationReady: @MainActor () -> Void
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        profileRuntime: ExtensionProfileRuntime,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority,
        installedExtensions: InstalledExtensionCollection,
        markPublicationReady: @escaping @MainActor () -> Void,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.profileRuntime = profileRuntime
        self.runtimeLifecycle = runtimeLifecycle
        self.installedExtensions = installedExtensions
        self.markPublicationReady = markPublicationReady
        self.diagnostics = diagnostics
    }

    func settle(_ loadedContext: ExtensionLoadedContext) -> Bool {
        let receipt = loadedContext.bindingReceipt
        let profileID = receipt.key.profileId
        guard profileRuntime.context(ifCurrent: receipt) === loadedContext.context,
              profileRuntime.controller(ifCurrent: receipt) === loadedContext.controller,
              loadedContext.context.isLoaded,
              installedExtensions.records.contains(where: {
                  $0.id == receipt.key.extensionId && $0.isEnabled
              })
        else { return false }

        let enabledIDs = Set(
            installedExtensions.records.lazy.filter(\.isEnabled).map(\.id)
        )
        let readiness = profileRuntime.readinessContext(
            for: profileID,
            hasEnabledExtensionDemand: enabledIDs.isEmpty == false,
            enabledExtensionIDs: enabledIDs,
            globalRuntimeReady: runtimeLifecycle.isReady
        )
        runtimeLifecycle.updateReadiness(isReady: readiness.isProfileReady)
        markPublicationReady()
        diagnostics.trace(
            "markExtensionRuntimeReady profile=\(profileID.uuidString) "
                + "loadedContexts=\(profileRuntime.contexts(for: profileID).count) "
                + "allEnabledLoaded=\(readiness.isProfileReady) "
                + "unloadedEnabledExtensionIDs=\(readiness.unloadedEnabledExtensionIDs.joined(separator: ","))"
        )
        return true
    }
}
