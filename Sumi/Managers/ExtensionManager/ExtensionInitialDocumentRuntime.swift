import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionInitialDocumentRuntime {
    private let owners: ExtensionDeferredRuntimeOwnerStore
    private let nativeMessaging: ExtensionNativeMessagingSessionControl
    private let requestedTabs:
        ExtensionBrowserAttachmentAuthority.RequestedTabs

    init(
        owners: ExtensionDeferredRuntimeOwnerStore,
        nativeMessaging: ExtensionNativeMessagingSessionControl,
        requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs
    ) {
        self.owners = owners
        self.nativeMessaging = nativeMessaging
        self.requestedTabs = requestedTabs
    }

    func ensureInitialContexts(profileID: UUID) async {
        await owners.initialDocumentRuntimePreparationOwner
            .ensureInitialExtensionContextsLoaded(for: profileID)
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
