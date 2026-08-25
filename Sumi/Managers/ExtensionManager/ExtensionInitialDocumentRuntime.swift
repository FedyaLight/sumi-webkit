import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionInitialDocumentRuntime {
    private let owners: ExtensionDeferredRuntimeOwnerStore
    private let lifecycle:
        ExtensionBrowserAttachmentAuthority.NormalTabLifecycle
    private let nativeMessaging: ExtensionNativeMessagingSessionControl
    private let requestedTabs:
        ExtensionBrowserAttachmentAuthority.RequestedTabs

    init(
        owners: ExtensionDeferredRuntimeOwnerStore,
        lifecycle: ExtensionBrowserAttachmentAuthority.NormalTabLifecycle,
        nativeMessaging: ExtensionNativeMessagingSessionControl,
        requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs
    ) {
        self.owners = owners
        self.lifecycle = lifecycle
        self.nativeMessaging = nativeMessaging
        self.requestedTabs = requestedTabs
    }

    func ensureInitialContexts(profileID: UUID) async
        -> PageNavigationPrerequisiteResult {
        await owners.initialDocumentRuntimePreparationOwner
            .ensureInitialExtensionContextsLoaded(for: profileID)
    }

    func ensureInitialTabPublication(
        _ tab: Tab,
        reason: String
    ) async -> PageNavigationPrerequisiteResult {
        let didReachAttachedRuntime = lifecycle.register(tab, reason: reason)
        guard owners.initialDocumentRuntimePreparationOwner
            .participatesInInitialDocumentRuntime()
        else {
            return .ready
        }
        guard didReachAttachedRuntime else { return .failed }
        return await tab.extensionPageRuntimeOwner
            .waitForSettledOpenPublicationForCurrentDocument()
            ? .ready
            : .cancelled
    }

    func warmNativeMessaging(profileID: UUID) async {
        await owners.initialDocumentRuntimePreparationOwner
            .warmInitialDocumentNativeMessaging(for: profileID)
    }

    func needsInitialContextLoad(profileID: UUID) -> Bool {
        owners.initialDocumentRuntimePreparationOwner
            .profileNeedsInitialDocumentExtensionContextLoad(
                profileId: profileID
            )
    }

    func cancelNativeMessaging(reason: String) {
        nativeMessaging.cancelAll(reason: reason)
    }

    func auxiliaryIntegration() -> AuxiliaryWindowExtensionIntegration? {
        requestedTabs.auxiliaryIntegration()
    }
}
