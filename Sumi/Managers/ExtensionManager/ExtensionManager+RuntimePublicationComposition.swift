import Foundation

/// Immutable wiring state for the extension-visible browser graph. It owns no
/// behavior and is never exposed as an aggregate capability; its only purpose
/// is to make a partially assembled graph unrepresentable in ExtensionManager.
@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimePublicationComposition {
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

/// Composition root for the extension-visible browser graph. Each stored node
/// has one runtime responsibility; there is deliberately no replacement
/// bridge, service bundle, or closure-bag facade.
@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    var runtimePublicationGate: ExtensionRuntimePublicationGate {
        prepareRuntimePublicationComposition()
        return runtimePublicationComposition!.gate
    }

    var normalWindowLifecycle: ExtensionNormalWindowLifecycle {
        prepareRuntimePublicationComposition()
        return runtimePublicationComposition!.normalWindows
    }

    var auxiliaryWindowLifecycle: ExtensionAuxiliaryWindowLifecycle {
        prepareRuntimePublicationComposition()
        return runtimePublicationComposition!.auxiliaryWindows
    }

    var windowPublications: ExtensionWindowPublicationQuery {
        prepareRuntimePublicationComposition()
        return runtimePublicationComposition!.windowPublications
    }

    var tabPublicationAdmission: ExtensionTabPublicationAdmission {
        prepareRuntimePublicationComposition()
        return runtimePublicationComposition!.tabAdmission
    }

    var normalTabActivation: ExtensionNormalTabActivationTransaction {
        prepareRuntimePublicationComposition()
        return runtimePublicationComposition!.tabActivation
    }

    var normalTabClosure: ExtensionNormalTabCloseTransaction {
        prepareRuntimePublicationComposition()
        return runtimePublicationComposition!.tabClosure
    }

    var runtimeReloadTransaction: ExtensionRuntimeReloadTransaction {
        prepareRuntimePublicationComposition()
        return runtimePublicationComposition!.reload
    }

    var runtimePublicationReconciler: ExtensionRuntimePublicationReconciler {
        prepareRuntimePublicationComposition()
        return runtimePublicationComposition!.reconciler
    }

    var loadedRuntimePublicationReconciler:
        ExtensionRuntimePublicationReconciler? {
        runtimePublicationComposition?.reconciler
    }

    private func prepareRuntimePublicationComposition() {
        guard runtimePublicationComposition == nil else { return }

        let gate = ExtensionRuntimePublicationGate()
        let preparedTabVisibility = ExtensionPreparedTabVisibility(gate: gate)
        #if DEBUG
            let normalWindows = ExtensionNormalWindowLifecycle(
                resolver: ExtensionNormalWindowProjectionResolver(
                    manager: self,
                    preparedTabVisibility: preparedTabVisibility
                ),
                adapterStore: adapterStore,
                preparedTabVisibility: preparedTabVisibility,
                debugDidOpenWindow: { [weak self] windowID in
                    self?.testHooks.didOpenNormalWindow?(windowID)
                }
            )
        #else
            let normalWindows = ExtensionNormalWindowLifecycle(
                resolver: ExtensionNormalWindowProjectionResolver(
                    manager: self,
                    preparedTabVisibility: preparedTabVisibility
                ),
                adapterStore: adapterStore,
                preparedTabVisibility: preparedTabVisibility
            )
        #endif
        let auxiliaryTabPublication = ExtensionAuxiliaryTabPublicationPreparer(
            runtimeSession: runtimeSession,
            profileRuntime: profileRuntime,
            adapterStore: adapterStore,
            controllerBinding: controllerAttachmentOwner,
            adapterResolution: adapterCatalog,
            extensionsLoaded: { [weak self] in
                self?.extensionsLoaded == true
            }
        )
        #if DEBUG
            let auxiliaryWindows = ExtensionAuxiliaryWindowLifecycle(
                adapterStore: adapterStore,
                profileRuntime: profileRuntime,
                tabPublication: auxiliaryTabPublication,
                normalWindows: normalWindows,
                debugEvent: { [weak self] event in
                    self?.dispatchAuxiliaryPublicationDebugEvent(event)
                }
            )
        #else
            let auxiliaryWindows = ExtensionAuxiliaryWindowLifecycle(
                adapterStore: adapterStore,
                profileRuntime: profileRuntime,
                tabPublication: auxiliaryTabPublication,
                normalWindows: normalWindows
            )
        #endif
        let publications = ExtensionWindowPublicationQuery(
            normalWindows: normalWindows,
            auxiliaryWindows: auxiliaryWindows.publications,
            runtime: { [weak self] in self?.runtime ?? .inactive },
            control: { [weak self] in self?.extensionAuxiliaryWindows }
        )
        let admission = ExtensionTabPublicationAdmission(
            normalWindows: normalWindows,
            publications: publications,
            gate: gate
        )
        let normalTabs = ExtensionNormalTabRuntimeAssembler.assemble(
            manager: self,
            gate: gate,
            preparedTabVisibility: preparedTabVisibility,
            admission: admission,
            publications: publications
        )
        let tabLifecycleEvents = normalTabs.tabLifecycleEvents
        let tabOpening = normalTabs.tabOpening
        let activationValidator = ExtensionNormalTabActivationValidator(
            runtimeSession: runtimeSession,
            profileRuntime: profileRuntime,
            adapterStore: adapterStore,
            adapterResolution: adapterCatalog,
            normalWindows: normalWindows,
            windowPublications: publications,
            runtime: { [weak self] in self?.runtime ?? .inactive },
            windowQuery: { [weak self] in self?.extensionWindowQuery },
            extensionsLoaded: { [weak self] in
                self?.extensionsLoaded ?? false
            }
        )
        #if DEBUG
            let activation = ExtensionNormalTabActivationTransaction(
                validator: activationValidator,
                debugEvent: { [weak self] event in
                    self?.dispatchNormalTabLifecycleDebugEvent(event)
                }
            )
        #else
            let activation = ExtensionNormalTabActivationTransaction(
                validator: activationValidator
            )
        #endif
        let closure = ExtensionNormalTabCloseTransaction(
            runtimeSession: runtimeSession,
            profileRuntime: profileRuntime,
            adapterStore: adapterStore,
            windowPublications: publications,
            events: tabLifecycleEvents,
            runtime: { [weak self] in self?.runtime ?? .inactive }
        )
        let reload = ExtensionRuntimeReloadTransaction(
            runtimeSession: runtimeSession,
            profileRuntime: profileRuntime,
            normalWindows: normalWindows,
            publicationGate: gate,
            adapterResolution: adapterCatalog,
            controllerBinding: controllerAttachmentOwner,
            tabPublication: tabOpening,
            tabEvents: tabLifecycleEvents,
            isAuxiliarySessionTab: publications.isAuxiliarySessionTab,
            diagnostics: runtimeDiagnostics
        )
        let reconciler = ExtensionRuntimePublicationReconciler(
            gate: gate,
            normalWindows: normalWindows,
            auxiliaryWindows: auxiliaryWindows,
            reloadTransaction: reload,
            tabClosure: closure,
            settleDeferredCommit: { [weak self] commit in
                self?.settleRuntimePublicationCommit(commit)
            }
        )

        normalTabRuntimeComposition = normalTabs
        runtimePublicationComposition = ExtensionRuntimePublicationComposition(
            gate: gate,
            normalWindows: normalWindows,
            auxiliaryWindows: auxiliaryWindows,
            windowPublications: publications,
            tabAdmission: admission,
            tabActivation: activation,
            tabClosure: closure,
            reload: reload,
            reconciler: reconciler
        )
    }
}
