import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextSettlementOwner {
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private let installedExtensions: InstalledExtensionCollection
    private let bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission?
    private let publishProfileProjection:
        @MainActor (UUID, WKWebExtensionController) -> Bool
    private let markPublicationReady: @MainActor () -> Void
    private let finalizeProfilePublication: (@MainActor (UUID) -> Void)?
    private let diagnostics: ExtensionRuntimeDiagnostics
    private var publishedProfileID: UUID?
    private weak var publishedController: WKWebExtensionController?
    private var finalizedContextGenerationByProfile: [UUID: UInt64] = [:]

    init(
        profileRuntime: ExtensionProfileRuntime,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority,
        installedExtensions: InstalledExtensionCollection,
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission? = nil,
        publishProfileProjection: @escaping @MainActor (
            UUID,
            WKWebExtensionController
        ) -> Bool,
        markPublicationReady: @escaping @MainActor () -> Void,
        finalizeProfilePublication: (@MainActor (UUID) -> Void)? = nil,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.profileRuntime = profileRuntime
        self.runtimeLifecycle = runtimeLifecycle
        self.installedExtensions = installedExtensions
        self.bootstrapChromeAdmission = bootstrapChromeAdmission
        self.publishProfileProjection = publishProfileProjection
        self.markPublicationReady = markPublicationReady
        self.finalizeProfilePublication = finalizeProfilePublication
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
        let projectionWasPublished =
            publishedProfileID == profileID
            && publishedController === loadedContext.controller
        let projectionIsPublished: Bool
        if projectionWasPublished {
            projectionIsPublished = true
        } else {
            projectionIsPublished = publishProfileProjection(
                profileID,
                loadedContext.controller
            )
            if projectionIsPublished {
                publishedProfileID = profileID
                publishedController = loadedContext.controller
            }
        }
        if readiness.isProfileReady && projectionIsPublished {
            markPublicationReady()
            let contextGeneration = profileRuntime.contextBindingGeneration(
                for: profileID
            )
            if finalizedContextGenerationByProfile[profileID]
                != contextGeneration {
                finalizedContextGenerationByProfile[profileID] =
                    contextGeneration
                finalizeProfilePublication?(profileID)
            }
        }
        diagnostics.trace(
            "markExtensionRuntimeReady profile=\(profileID.uuidString) "
                + "loadedContexts=\(profileRuntime.contexts(for: profileID).count) "
                + "allEnabledLoaded=\(readiness.isProfileReady) "
                + "controllerPublished=\(projectionIsPublished) "
                + "unloadedEnabledExtensionIDs=\(readiness.unloadedEnabledExtensionIDs.joined(separator: ","))"
        )
        bootstrapChromeAdmission?.finishBootstrap(
            extensionIdentity: receipt.key.extensionId,
            profileID: profileID
        )
        return true
    }
}
