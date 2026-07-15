import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeBrowserRolePhaseProduct {
    let normalTabLifecycle:
        ExtensionBrowserAttachmentAuthority.NormalTabLifecycle
    let requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs
    let normalTabQuery: ExtensionBrowserAttachmentAuthority.NormalTabQuery
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleRuntimeBrowserRolePhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        browser: ExtensionManagerBrowserFoundation,
        coordination: ExtensionRuntimeCoordinationPhaseProduct
    ) -> ExtensionRuntimeBrowserRolePhaseProduct {
        ExtensionRuntimeBrowserRolePhaseProduct(
            normalTabLifecycle:
                ExtensionBrowserAttachmentAuthority.NormalTabLifecycle(
                    attachment: browser.attachment
                ),
            requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs(
                attachment: browser.attachment,
                runtimeLoadStatus: runtime.loadStatus,
                profileRuntime: runtime.profileRuntime,
                deferredOwners: coordination.deferredRuntimeOwners
            ),
            normalTabQuery:
                ExtensionBrowserAttachmentAuthority.NormalTabQuery(
                    attachment: browser.attachment
                )
        )
    }
}
