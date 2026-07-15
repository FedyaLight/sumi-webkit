import Foundation

/// Immutable lifetime storage for extension-visible browser publication
/// transactions. It is retained only by the attached runtime authority.
@available(macOS 15.5, *)
@MainActor
struct ExtensionAttachedPublicationRuntime {
    let gate: ExtensionRuntimePublicationGate
    let normalWindows: ExtensionNormalWindowLifecycle
    let auxiliaryWindows: ExtensionAuxiliaryWindowLifecycle
    let windowPublications: ExtensionWindowPublicationQuery
    let tabAdmission: ExtensionTabPublicationAdmission
    let tabActivation: ExtensionNormalTabActivationTransaction
    let tabClosure: ExtensionNormalTabCloseTransaction
    let reload: ExtensionRuntimeReloadTransaction
    let reconciler: ExtensionRuntimePublicationReconciler
}

/// Builds the atomic activation/close/reload transaction cluster after the
/// window and normal-tab roles are complete. The returned lifetime is still
/// unpublished; only the attachment authority can install it.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPublicationTransactionFactory {
    private let tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority
    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
    private let profileRuntime: ExtensionProfileRuntime
    private let adapterStore: ExtensionBrowserAdapterStore
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let reloadSettlement: ExtensionBrowserAttachmentAuthority.Reloads
    #if DEBUG
        private var debugSignals: ExtensionManagerDebugSignals?
    #endif

    init(
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        diagnostics: ExtensionRuntimeDiagnostics,
        reloadSettlement: ExtensionBrowserAttachmentAuthority.Reloads
    ) {
        self.tabPublicationRevisions = tabPublicationRevisions
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.runtimeLoadStatus = runtimeLoadStatus
        self.profileRuntime = profileRuntime
        self.adapterStore = adapterStore
        self.diagnostics = diagnostics
        self.reloadSettlement = reloadSettlement
    }

    #if DEBUG
        func installDebugSignals(_ signals: ExtensionManagerDebugSignals) {
            debugSignals = signals
        }
    #endif

    func assemble(
        bridge: BrowserExtensionBridgeComposition,
        controller: ExtensionControllerRuntimeComposition,
        windows: ExtensionWindowPublicationAssembly,
        normalTabs: ExtensionAttachedNormalTabRuntime
    ) -> ExtensionAttachedPublicationRuntime {
        #if DEBUG
            guard let debugSignals else {
                preconditionFailure("Debug signals must be installed before assembly")
            }
        #endif
        let activationValidator = ExtensionNormalTabActivationValidator(
            runtimePublicationEvidence: runtimePublicationEvidence,
            profileRuntime: profileRuntime,
            adapterStore: adapterStore,
            adapterResolution: windows.adapters,
            normalWindows: windows.windows.normal,
            windowPublications: windows.windows.query,
            tabProfiles: controller.profiles,
            windowQuery: bridge.windows,
            extensionsLoaded: { [runtimeLoadStatus] in
                runtimeLoadStatus.extensionsLoaded
            }
        )
        #if DEBUG
            let activation = ExtensionNormalTabActivationTransaction(
                validator: activationValidator,
                debugEvent: { [debugSignals] event in
                    debugSignals.dispatchNormalTabLifecycle(event)
                }
            )
        #else
            let activation = ExtensionNormalTabActivationTransaction(
                validator: activationValidator
            )
        #endif
        let closure = ExtensionNormalTabCloseTransaction(
            tabPublicationRevisions: tabPublicationRevisions,
            adapterStore: adapterStore,
            windowPublications: windows.windows.query,
            preparedTabVisibility: windows.tabs.preparedVisibility,
            events: normalTabs.tabLifecycleEvents
        )
        let reload = ExtensionRuntimeReloadTransaction(
            runtimePublicationEvidence: runtimePublicationEvidence,
            normalWindows: windows.windows.normal,
            publicationGate: windows.tabs.gate,
            profiles: ExtensionRuntimeReloadProfileReconciler(
                profileRuntime: profileRuntime,
                reconciler: controller.reconciler
            ),
            tabPublication: normalTabs.tabOpening,
            diagnostics: diagnostics,
            tabInventory: ExtensionRuntimeReloadTabInventory(
                tabs: bridge.tabs,
                isAuxiliarySessionTab:
                    windows.windows.query.isAuxiliarySessionTab,
                windows: bridge.windows,
                tabProfiles: controller.profiles,
                profileRuntime: profileRuntime,
                controllers: controller.controllers,
                adapterResolution: windows.adapters,
                webViews: bridge.webViews
            ),
            tabRetirement: ExtensionRuntimeReloadTabRetirement(
                profileRuntime: profileRuntime,
                adapterResolution: windows.adapters,
                controllers: controller.controllers,
                tabEvents: normalTabs.tabLifecycleEvents,
                tabProfiles: controller.profiles
            )
        )
        let reconciler = ExtensionRuntimePublicationReconciler(
            gate: windows.tabs.gate,
            normalWindows: windows.windows.normal,
            auxiliaryWindows: windows.windows.auxiliary,
            reloadTransaction: reload,
            tabClosure: closure,
            settleDeferredCommit: { [reloadSettlement] commit in
                reloadSettlement.settle(commit)
            }
        )
        return ExtensionAttachedPublicationRuntime(
            gate: windows.tabs.gate,
            normalWindows: windows.windows.normal,
            auxiliaryWindows: windows.windows.auxiliary,
            windowPublications: windows.windows.query,
            tabAdmission: windows.tabs.admission,
            tabActivation: activation,
            tabClosure: closure,
            reload: reload,
            reconciler: reconciler
        )
    }
}
