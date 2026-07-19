import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextSettlementOwner {
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private let installedExtensions: InstalledExtensionCollection
    private let bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission?
    private let publishReadyProfile:
        @MainActor (UUID, WKWebExtensionController) -> Bool
    private let markPublicationReady: @MainActor () -> Void
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        profileRuntime: ExtensionProfileRuntime,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority,
        installedExtensions: InstalledExtensionCollection,
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission? = nil,
        publishReadyProfile: @escaping @MainActor (
            UUID,
            WKWebExtensionController
        ) -> Bool,
        markPublicationReady: @escaping @MainActor () -> Void,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.profileRuntime = profileRuntime
        self.runtimeLifecycle = runtimeLifecycle
        self.installedExtensions = installedExtensions
        self.bootstrapChromeAdmission = bootstrapChromeAdmission
        self.publishReadyProfile = publishReadyProfile
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
        let didPublish = readiness.isProfileReady
            && publishReadyProfile(profileID, loadedContext.controller)
        if didPublish {
            markPublicationReady()
        }
        diagnostics.trace(
            "markExtensionRuntimeReady profile=\(profileID.uuidString) "
                + "loadedContexts=\(profileRuntime.contexts(for: profileID).count) "
                + "allEnabledLoaded=\(readiness.isProfileReady) "
                + "controllerPublished=\(didPublish) "
                + "unloadedEnabledExtensionIDs=\(readiness.unloadedEnabledExtensionIDs.joined(separator: ","))"
        )
        bootstrapChromeAdmission?.finishBootstrap(
            extensionIdentity: receipt.key.extensionId,
            profileID: profileID
        )
        return true
    }
}
