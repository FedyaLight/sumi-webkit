import Foundation

/// Product-facing browser integration boundary. Each leaf owns one coherent
/// operation family and none can recover the manager or any graph.
@available(macOS 15.5, *)
@MainActor
struct ExtensionModuleBrowserRuntime {
    let preparation: ExtensionNormalTabPreparationRuntime
    let publication: ExtensionBrowserPublicationRuntime
    let interaction: ExtensionNormalTabInteractionRuntime
    let initialDocument: ExtensionInitialDocumentRuntime
}

/// Exact one-product factory retained by the normal-tab graph.
@available(macOS 15.5, *)
@MainActor
struct ExtensionModuleBrowserRuntimeFactory {
    private let configuration: ExtensionWebViewConfigurationPreparation
    private let lifecycle:
        ExtensionBrowserAttachmentAuthority.NormalTabLifecycle
    private let requestedTabs:
        ExtensionBrowserAttachmentAuthority.RequestedTabs
    private let publication: ExtensionBrowserPublicationRuntime
    private let interaction: ExtensionNormalTabInteractionRuntime
    private let initialDocument: ExtensionInitialDocumentRuntime

    init(
        configuration: ExtensionWebViewConfigurationPreparation,
        lifecycle: ExtensionBrowserAttachmentAuthority.NormalTabLifecycle,
        requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs,
        browserEvents: ExtensionBrowserAttachmentAuthority.BrowserEvents,
        profileTransition: ExtensionProfileRuntimeTransition,
        keyboard: ExtensionKeyboardCommandDispatchOwner,
        recentRequests: ExtensionRecentTabRequestHistory,
        deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore,
        nativeMessaging: ExtensionNativeMessagingSessionControl
    ) {
        self.configuration = configuration
        self.lifecycle = lifecycle
        self.requestedTabs = requestedTabs
        publication = ExtensionBrowserPublicationRuntime(
            events: browserEvents,
            profiles: profileTransition
        )
        interaction = ExtensionNormalTabInteractionRuntime(
            lifecycle: lifecycle,
            requestedTabs: requestedTabs,
            keyboard: keyboard,
            recentRequests: recentRequests
        )
        initialDocument = ExtensionInitialDocumentRuntime(
            owners: deferredRuntimeOwners,
            nativeMessaging: nativeMessaging,
            requestedTabs: requestedTabs
        )
    }

    func make(userScripts: [SumiPageScript]) -> ExtensionModuleBrowserRuntime {
        ExtensionModuleBrowserRuntime(
            preparation: ExtensionNormalTabPreparationRuntime(
                userScripts: userScripts,
                configurations: configuration,
                lifecycle: lifecycle,
                requestedTabs: requestedTabs
            ),
            publication: publication,
            interaction: interaction,
            initialDocument: initialDocument
        )
    }
}
