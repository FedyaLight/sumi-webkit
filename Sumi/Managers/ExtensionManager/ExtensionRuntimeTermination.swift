import Foundation

/// Product-level terminal operation over the exact core shutdown transaction
/// and, when present, the immutable attached browser lifetime.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeTermination {
    private let shutdown: ExtensionRuntimeShutdown
    private let browser: ExtensionBrowserAttachmentAuthority.Retirement
    private let deferredOwners: ExtensionDeferredRuntimeOwnerStore
    private let nativeMessagingOwners: ExtensionDemandScopedNativeMessagingOwners
    private let surfacePublication: ExtensionManagerSurfacePublication

    init(
        shutdown: ExtensionRuntimeShutdown,
        browser: ExtensionBrowserAttachmentAuthority.Retirement,
        deferredOwners: ExtensionDeferredRuntimeOwnerStore,
        nativeMessagingOwners: ExtensionDemandScopedNativeMessagingOwners,
        surfacePublication: ExtensionManagerSurfacePublication
    ) {
        self.shutdown = shutdown
        self.browser = browser
        self.deferredOwners = deferredOwners
        self.nativeMessagingOwners = nativeMessagingOwners
        self.surfacePublication = surfacePublication
    }

    @discardableResult
    func shutDown(
        reason: String,
        admission: ExtensionRuntimeShutdown.Admission = .forced
    ) -> ExtensionRuntimeShutdown.Result {
        let result = browser.shutDown(
            using: shutdown,
            reason: reason,
            initialDocumentPreparation:
                deferredOwners.loadedInitialDocumentRuntimePreparationOwner,
            nativeMessagingOwners: nativeMessagingOwners,
            admission: admission
        )
        if result.completed {
            surfacePublication.clearActionSurfaceStates()
            _ = surfacePublication.resetRuntimePublicationReadiness()
        }
        return result
    }

    func executeRebuildPlan(
        _ plan: ExtensionRuntimeTabRebuildPlan,
        reason: String
    ) -> [ExtensionRuntimeTabRebuildPlan.Execution] {
        browser.executeRebuildPlan(
            plan,
            using: shutdown,
            reason: reason
        )
    }
}
