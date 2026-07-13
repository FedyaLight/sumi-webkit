import Foundation

/// Cancels asynchronous extension work before terminal runtime shutdown.
/// Claim invalidation is first so cancellation callbacks cannot revive state.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeActivityCancellation {
    struct Resources {
        let initialDocumentPreparation:
            ExtensionInitialDocumentRuntimePreparationOwner?
        let deferredTabRegistration: ExtensionDeferredTabRegistration?
        let nativeMessagingWakes:
            ExtensionNativeMessagingBackgroundWakeOwner?
        let publicationReconciler: ExtensionRuntimePublicationReconciler?
        let runtime: ExtensionManagerRuntime
        let auxiliaryWindows: (any ExtensionAuxiliaryWindowControl)?
        let nativeMessagingRelay: SumiNativeMessagingRelay?
    }

    private let loadRegistry: ExtensionContextLoadRegistry
    private let backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner
    private let nativeMessagingPorts: ExtensionNativeMessagingPortRegistry
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        loadRegistry: ExtensionContextLoadRegistry,
        backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner,
        nativeMessagingPorts: ExtensionNativeMessagingPortRegistry,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.loadRegistry = loadRegistry
        self.backgroundRuntimeState = backgroundRuntimeState
        self.nativeMessagingPorts = nativeMessagingPorts
        self.diagnostics = diagnostics
    }

    func cancel(reason: String, resources: Resources) {
        loadRegistry.invalidateAll()
        resources.initialDocumentPreparation?
            .cancelContentScriptContextLoadTasks()
        resources.initialDocumentPreparation?
            .cancelInitialDocumentNativeMessagingWarmupTasks()
        resources.deferredTabRegistration?.cancelAll()
        resources.nativeMessagingWakes?.cancelAllWakeTasks()
        backgroundRuntimeState.cancelAllWakeTasks()
        resources.publicationReconciler?.retire(
            runtime: resources.runtime,
            auxiliaryControl: resources.auxiliaryWindows
        )
        diagnostics.trace(
            "nativeMessagingCancelSessions reason=\(reason) "
                + "count=\(nativeMessagingPorts.count)"
        )
        nativeMessagingPorts.disconnectAll()
        resources.nativeMessagingRelay?.clearAllLoopGuardState()
    }
}
