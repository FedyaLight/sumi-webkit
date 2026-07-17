import Foundation

@MainActor
enum BrowserTabRuntimeLifecycleFactory {
    static func make(
        state: TabStateStore,
        runtimeConnection: TabRuntimePortConnection,
        startupRestorePolicy: TabStartupRestorePolicy,
        startupRestoreLifecycle: TabStartupRestoreLifecycle,
        membership: TabCollectionMembershipOwner,
        runtimePreparation: TabRuntimePreparationOwner,
        storeRestore: TabStoreRestoreService,
        spaceProfiles: SpaceProfileReconciliationService,
        spaceAvailability: SpaceProfileTransitionAvailability,
        pendingPins: PendingShortcutPinAdopter,
        liveShortcutTabs: LiveShortcutTabRegistry
    ) -> TabRuntimeLifecycle {
        let restoreStarter = startupRestorePolicy.isEnabled
            ? TabRuntimeAttachmentRestoreStarter(
                connection: runtimeConnection,
                policy: startupRestorePolicy,
                lifecycle: startupRestoreLifecycle,
                restore: storeRestore
            )
            : nil
        let deferredWork = TabRuntimeAttachmentDeferredWorkOwner(
            connection: runtimeConnection,
            spaceProfiles: spaceProfiles,
            spaceAvailability: spaceAvailability,
            pendingPins: pendingPins
        )
        return TabRuntimeLifecycle(
            runtimePorts: TabRuntimePortsAttachmentOwner(
                connection: runtimeConnection,
                bootstrap: TabRuntimeAttachmentBootstrap(
                    connection: runtimeConnection,
                    membership: membership,
                    runtimePreparation: runtimePreparation,
                    selection: state.selection
                ),
                settlement: TabRuntimeAttachmentSettlement(
                    connection: runtimeConnection,
                    spaces: state.spaces,
                    deferredWork: deferredWork,
                    restoreStarter: restoreStarter
                )
            ),
            faviconRefresh: TabFaviconPresentationRefreshOwner(
                notificationCenter: .default,
                debounceNanoseconds: TabFaviconPresentationRefreshOwner
                    .defaultDebounceNanoseconds,
                regularTabs: state.regularTabs,
                liveShortcutTabs: liveShortcutTabs
            ),
            stateStore: state
        )
    }
}
