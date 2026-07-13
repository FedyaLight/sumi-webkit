import Foundation

/// Private lifetime storage for normal-Tab leaf roles. It is never accepted as
/// a capability and owns no forwarding behavior.
@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalTabRuntimeComposition {
    let tabLifecycleEvents: ExtensionTabLifecycleEmitter
    let preparedTabs: ExtensionPreparedNormalTabQuery
    let publishedTabs: ExtensionPublishedNormalTabQuery
    let tabProfiles: ExtensionTabProfileResolution
    let existingControllers: ExtensionExistingTabControllerQuery
    let deferredTabRegistration: ExtensionDeferredTabRegistration
    let tabOpening: ExtensionNormalTabOpenTransaction
    let tabRegistration: ExtensionNormalTabRegistration
    let tabProperties: ExtensionTabPropertyPublisher
    let tabRebind: ExtensionTabLifecycleRebindTransaction
}

/// Construction-only composition root. ExtensionManager is used only while
/// wiring leaves and is never stored by the returned graph.
@available(macOS 15.5, *)
@MainActor
enum ExtensionNormalTabRuntimeAssembler {
    static func assemble(
        manager: ExtensionManager,
        gate: ExtensionRuntimePublicationGate,
        preparedTabVisibility: ExtensionPreparedTabVisibility,
        admission: ExtensionTabPublicationAdmission,
        publications: ExtensionWindowPublicationQuery
    ) -> ExtensionNormalTabRuntimeComposition {
        guard let tabs = manager.extensionTabQuery,
              let liveWebViews = manager.extensionWebViewHosting
        else {
            preconditionFailure(
                "Normal Tab runtime composition requires an attached browser bridge"
            )
        }
        let tabProfiles = ExtensionTabProfileResolution(
            profileRuntime: manager.profileRuntime,
            windowProfiles: manager.extensionWindowQuery
                as? any ExtensionTabWindowProfileQuery
        )
        let existingControllers = ExtensionExistingTabControllerQuery(
            profileRuntime: manager.profileRuntime,
            profiles: tabProfiles
        )
        let preparedTabs = ExtensionPreparedNormalTabQuery(
            runtimeSession: manager.runtimeSession,
            tabs: tabs
        )
        let publishedTabs = ExtensionPublishedNormalTabQuery(
            prepared: preparedTabs,
            runtimeSession: manager.runtimeSession,
            publicationGate: gate,
            profiles: tabProfiles,
            adapters: manager.adapterStore,
            windows: publications
        )
        #if DEBUG
            let events = ExtensionTabLifecycleEmitter(
                preparedTabVisibility: preparedTabVisibility,
                didOpen: { [weak manager] in
                    manager?.testHooks.didOpenTab?($0)
                },
                didClose: { [weak manager] in
                    manager?.testHooks.didCloseTab?($0)
                }
            )
        #else
            let events = ExtensionTabLifecycleEmitter(
                preparedTabVisibility: preparedTabVisibility
            )
        #endif
        let contexts = manager.initialDocumentRuntimePreparationOwner
        let deferred = ExtensionDeferredTabRegistration(
            runtimeSession: manager.runtimeSession,
            tabs: tabs,
            profiles: tabProfiles,
            contextLoading: contexts
        )
        #if DEBUG
            let opening = ExtensionNormalTabOpenTransaction(
                runtimeSession: manager.runtimeSession,
                publicationGate: gate,
                profileRuntime: manager.profileRuntime,
                profiles: tabProfiles,
                tabs: tabs,
                adapters: manager.adapterStore,
                adapterResolver: manager.adapterCatalog,
                controllers: existingControllers,
                controllerAttachment: manager.controllerAttachmentOwner,
                liveWebViews: liveWebViews,
                contextReadiness: contexts,
                deferredRegistration: deferred,
                admission: admission,
                windowPublications: publications,
                events: events,
                diagnostics: manager.runtimeDiagnostics,
                didDeferOpen: { [weak manager] tabID, reason in
                    manager?.testHooks.didDeferOpenTab?(tabID, reason)
                }
            )
        #else
            let opening = ExtensionNormalTabOpenTransaction(
                runtimeSession: manager.runtimeSession,
                publicationGate: gate,
                profileRuntime: manager.profileRuntime,
                profiles: tabProfiles,
                tabs: tabs,
                adapters: manager.adapterStore,
                adapterResolver: manager.adapterCatalog,
                controllers: existingControllers,
                controllerAttachment: manager.controllerAttachmentOwner,
                liveWebViews: liveWebViews,
                contextReadiness: contexts,
                deferredRegistration: deferred,
                admission: admission,
                windowPublications: publications,
                events: events,
                diagnostics: manager.runtimeDiagnostics
            )
        #endif
        let registration = ExtensionNormalTabRegistration(
            runtimeSession: manager.runtimeSession,
            tabs: tabs,
            preparedTabs: preparedTabs,
            controllers: manager.controllerAttachmentOwner,
            opening: opening,
            diagnostics: manager.runtimeDiagnostics
        )
        deferred.bind(resumer: registration)
        manager.webViewRuntimePreparationOwner.bind(
            tabRegistration: registration
        )
        #if DEBUG
            let properties = ExtensionTabPropertyPublisher(
                publishedTabs: publishedTabs,
                profiles: tabProfiles,
                profileRuntime: manager.profileRuntime,
                adapters: manager.adapterStore,
                liveWebViews: liveWebViews,
                didPublish: { [weak manager] tabID, changed in
                    manager?.testHooks.didChangeTabProperties?(tabID, changed)
                }
            )
        #else
            let properties = ExtensionTabPropertyPublisher(
                publishedTabs: publishedTabs,
                profiles: tabProfiles,
                profileRuntime: manager.profileRuntime,
                adapters: manager.adapterStore,
                liveWebViews: liveWebViews
            )
        #endif
        let rebind = ExtensionTabLifecycleRebindTransaction(
            runtimeSession: manager.runtimeSession,
            profileRuntime: manager.profileRuntime,
            tabs: tabs,
            profiles: tabProfiles,
            adapters: manager.adapterStore,
            adapterResolver: manager.adapterCatalog,
            controllers: existingControllers,
            controllerPreparation: manager.controllerAttachmentOwner,
            rebuildQuery: manager.controllerAttachmentOwner,
            liveWebViews: liveWebViews,
            contextReadiness: contexts,
            deferredRegistration: deferred,
            registration: registration,
            events: events
        )
        return ExtensionNormalTabRuntimeComposition(
            tabLifecycleEvents: events,
            preparedTabs: preparedTabs,
            publishedTabs: publishedTabs,
            tabProfiles: tabProfiles,
            existingControllers: existingControllers,
            deferredTabRegistration: deferred,
            tabOpening: opening,
            tabRegistration: registration,
            tabProperties: properties,
            tabRebind: rebind
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    var tabLifecycleEvents: ExtensionTabLifecycleEmitter {
        _ = runtimePublicationGate
        return normalTabRuntimeComposition!.tabLifecycleEvents
    }

    var preparedExtensionTabs: ExtensionPreparedNormalTabQuery {
        _ = runtimePublicationGate
        return normalTabRuntimeComposition!.preparedTabs
    }

    var publishedExtensionTabs: ExtensionPublishedNormalTabQuery {
        _ = runtimePublicationGate
        return normalTabRuntimeComposition!.publishedTabs
    }

    var normalTabOpening: ExtensionNormalTabOpenTransaction {
        _ = runtimePublicationGate
        return normalTabRuntimeComposition!.tabOpening
    }

    var normalTabRegistration: ExtensionNormalTabRegistration {
        _ = runtimePublicationGate
        return normalTabRuntimeComposition!.tabRegistration
    }

    var tabPropertyPublisher: ExtensionTabPropertyPublisher {
        _ = runtimePublicationGate
        return normalTabRuntimeComposition!.tabProperties
    }

    var tabLifecycleRebind: ExtensionTabLifecycleRebindTransaction {
        _ = runtimePublicationGate
        return normalTabRuntimeComposition!.tabRebind
    }

    var deferredTabRegistration: ExtensionDeferredTabRegistration {
        _ = runtimePublicationGate
        return normalTabRuntimeComposition!.deferredTabRegistration
    }

    var loadedDeferredTabRegistration: ExtensionDeferredTabRegistration? {
        normalTabRuntimeComposition?.deferredTabRegistration
    }
}
