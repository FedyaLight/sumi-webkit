import Foundation

@available(macOS 15.5, *)
@MainActor
enum ExtensionManagerToolbarRuntimeFactory {
    static func make(
        attachment: ExtensionBrowserAttachmentAuthority,
        profileRuntime: ExtensionProfileRuntime,
        contexts: ExtensionContextLifecycleAssemblyProduct,
        controller: ExtensionControllerAssemblyProduct,
        actions: ExtensionActionUIAssemblyProduct,
        normalTabs: ExtensionNormalTabAssemblyProduct,
        actionAnchors: ExtensionActionAnchorStore,
        optionsWindows: ExtensionOptionsWindowService
    ) -> ExtensionToolbarRuntime {
        ExtensionToolbarRuntime(
            ordering: ExtensionToolbarOrderingRuntime(
                pinning: actions.surface.toolbarPinning,
                hubOrdering: actions.surface.hubOrdering
            ),
            siteAccess: ExtensionToolbarSiteAccessRuntime(
                policies: actions.surface.siteAccess,
                currentProfileID: {
                    [profileRuntime] in profileRuntime.currentProfileId
                }
            ),
            options: ExtensionToolbarOptionsRuntime(
                contexts: contexts.contextResidency,
                currentProfileID: {
                    [profileRuntime] in profileRuntime.currentProfileId
                },
                controller: {
                    [profileRuntime] in profileRuntime.controller(for: $0)
                },
                callbacks: controller.browserCallbacks,
                windows: optionsWindows
            ),
            popup: ExtensionToolbarPopupRuntime(
                invocation: actions.surface.invocation,
                anchors: actionAnchors,
                anchorResolver: actions.presentation.popupAnchorResolver,
                normalTabs: normalTabs.query
            ),
            actionPresentation: makeActionPresentationQuery(
                attachment: attachment,
                profileRuntime: profileRuntime,
                normalTabs: normalTabs.query
            )
        )
    }

    private static func makeActionPresentationQuery(
        attachment: ExtensionBrowserAttachmentAuthority,
        profileRuntime: ExtensionProfileRuntime,
        normalTabs: ExtensionBrowserAttachmentAuthority.NormalTabQuery
    ) -> ExtensionActionPresentationQuery {
        ExtensionActionPresentationQuery(
            contextBindings: {
                [profileRuntime] extensionID in
                profileRuntime.contextsByProfile.compactMap {
                    profileID, contexts in
                    guard let context = contexts[extensionID],
                          let identity = profileRuntime
                          .exactContextIdentity(for: context),
                          identity.extensionId == extensionID,
                          identity.profileId == profileID,
                          let receipt = profileRuntime.contextBindingReceipt(
                              extensionId: extensionID,
                              profileId: profileID
                          ),
                          profileRuntime.context(ifCurrent: receipt) === context
                    else { return nil }
                    return ExtensionActionPresentationQuery.ContextBinding(
                        context: context,
                        receipt: receipt
                    )
                }
            },
            currentContext: {
                [profileRuntime] in profileRuntime.context(ifCurrent: $0)
            },
            stableAdapter: {
                [normalTabs] in normalTabs.stableAdapter(for: $0)
            },
            windowRegistrationReceipt: {
                [attachment] window in
                attachment.windowRegistrationReceipt(for: window)
            },
            registeredWindow: {
                [attachment] receipt in
                attachment.registeredWindow(ifCurrent: receipt)
            },
            allWindows: { [attachment] in
                attachment.allRegisteredWindows()
            },
            attachment: attachment
        )
    }
}
