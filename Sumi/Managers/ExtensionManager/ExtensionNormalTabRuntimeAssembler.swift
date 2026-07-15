import Foundation
import WebKit

/// Private lifetime storage for normal-Tab leaf roles. It is never accepted as
/// a capability and owns no forwarding behavior.
@available(macOS 15.5, *)
@MainActor
struct ExtensionAttachedNormalTabRuntime {
    let tabLifecycleEvents: ExtensionTabLifecycleEmitter
    let preparedTabs: ExtensionPreparedNormalTabQuery
    let publishedTabs: ExtensionPublishedNormalTabQuery
    let deferredTabRegistration: ExtensionDeferredTabRegistration
    let tabOpening: ExtensionNormalTabOpenTransaction
    let tabRegistration: ExtensionNormalTabRegistration
    let liveWebViewPreparation: ExtensionLiveWebViewRuntimePreparation
    let requestedTabWebViewMaterializer:
        ExtensionRequestedTabWebViewMaterializer
    let tabProperties: ExtensionTabPropertyPublisher
    let tabRebind: ExtensionTabLifecycleRebindTransaction
}

/// Construction-only composition root. Every role is supplied explicitly;
/// the returned lifetime stores only the leaf collaborators it owns.
@available(macOS 15.5, *)
@MainActor
enum ExtensionNormalTabRuntimeAssembler {
    static func assemble(
        tabs: any ExtensionTabQuery,
        liveWebViews: any ExtensionTabWebViewHosting,
        controllerRuntime: ExtensionControllerRuntimeComposition,
        gate: ExtensionRuntimePublicationGate,
        preparedTabVisibility: ExtensionPreparedTabVisibility,
        preparedTabs: ExtensionPreparedNormalTabQuery,
        publishedTabs: ExtensionPublishedNormalTabQuery,
        admission: ExtensionTabPublicationAdmission,
        publications: ExtensionWindowPublicationQuery,
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        extensionLoadRevisions: ExtensionLoadRevisionAuthority,
        runtimePublicationEvidence: ExtensionRuntimePublicationEvidenceIssuer,
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        adapterCatalog: ExtensionAdapterCatalog,
        contextLoading: ExtensionInitialDocumentRuntimePreparationOwner,
        configurationPreparation: ExtensionWebViewConfigurationPreparation,
        diagnostics: ExtensionRuntimeDiagnostics
    ) -> ExtensionAttachedNormalTabRuntime {
        let tabProfiles = controllerRuntime.profiles
        let existingControllers = controllerRuntime.controllers
        let events = ExtensionTabLifecycleEmitter(
            preparedTabVisibility: preparedTabVisibility
        )
        let deferred = ExtensionDeferredTabRegistration(
            extensionLoadRevisions: extensionLoadRevisions,
            tabs: tabs,
            profiles: tabProfiles,
            contextLoading: contextLoading
        )
        let opening = ExtensionNormalTabOpenTransaction(
            runtimePublicationEvidence: runtimePublicationEvidence,
            publicationGate: gate,
            profileRuntime: profileRuntime,
            profiles: tabProfiles,
            tabs: tabs,
            adapters: adapterStore,
            adapterResolver: adapterCatalog,
            controllers: existingControllers,
            controllerAdmission: controllerRuntime.admission,
            liveWebViews: liveWebViews,
            contextReadiness: contextLoading,
            deferredRegistration: deferred,
            admission: admission,
            windowPublications: publications,
            events: events,
            diagnostics: diagnostics
        )
        let registration = ExtensionNormalTabRegistration(
            tabPublicationRevisions: tabPublicationRevisions,
            runtimeLoadStatus: runtimeLoadStatus,
            tabs: tabs,
            preparedTabs: preparedTabs,
            controllers: controllerRuntime.repair,
            opening: opening,
            diagnostics: diagnostics
        )
        deferred.bind(resumer: registration)
        let liveWebViewPreparation = ExtensionLiveWebViewRuntimePreparation(
            profiles: tabProfiles,
            controllers: existingControllers,
            admission: controllerRuntime.admission,
            tabRegistration: registration,
            diagnostics: diagnostics
        )
        let requestedTabWebViewMaterializer =
            ExtensionRequestedTabWebViewMaterializer(
                browserContext: liveWebViews,
                configurationPreparation:
                    configurationPreparation,
                livePreparation: liveWebViewPreparation,
                profiles: tabProfiles,
                controllers: existingControllers,
                webViews: controllerRuntime.webViews,
                controllerAdmission: controllerRuntime.admission
            )
        let properties = ExtensionTabPropertyPublisher(
            publishedTabs: publishedTabs,
            profiles: tabProfiles,
            profileRuntime: profileRuntime,
            adapters: adapterStore,
            liveWebViews: liveWebViews
        )
        let rebind = ExtensionTabLifecycleRebindTransaction(
            runtimePublicationEvidence: runtimePublicationEvidence,
            runtimeLoadStatus: runtimeLoadStatus,
            profileRuntime: profileRuntime,
            tabs: tabs,
            profiles: tabProfiles,
            adapters: adapterStore,
            adapterResolver: adapterCatalog,
            controllers: existingControllers,
            controllerPreparation: controllerRuntime.repair,
            rebuildQuery: controllerRuntime.mismatch,
            liveWebViews: liveWebViews,
            contextReadiness: contextLoading,
            deferredRegistration: deferred,
            registration: registration,
            events: events
        )
        return ExtensionAttachedNormalTabRuntime(
            tabLifecycleEvents: events,
            preparedTabs: preparedTabs,
            publishedTabs: publishedTabs,
            deferredTabRegistration: deferred,
            tabOpening: opening,
            tabRegistration: registration,
            liveWebViewPreparation: liveWebViewPreparation,
            requestedTabWebViewMaterializer:
                requestedTabWebViewMaterializer,
            tabProperties: properties,
            tabRebind: rebind
        )
    }
}
