//
//  BrowserWindowSessionBundle.swift
//  Sumi
//
//  Transitional composition for persistence, restore, history, and registry
//  lifecycle services that have not yet moved to their domains.
//

import Foundation

/// Composes the remaining window-session persistence and restore services.
@MainActor
final class BrowserWindowSessionBundle {
    let restoreService: WindowSessionRestoreService
    let restoration: BrowserWindowSessionRestorationService
    let activation: BrowserWindowActivationService
    let persistence: WindowSessionPersistenceCoordinator
    let history: WindowSessionHistoryServices
    let sessionRecovery: BrowserSessionRecoveryCommands

    init(
        browserManager: BrowserManager,
        startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
    ) {
        let snapshotFactory = WindowSessionSnapshotFactory(
            glanceManager: browserManager.glanceManager
        )
        let persistenceRuntime = browserManager.windowSessionPersistence
        let persistenceScheduler = persistenceRuntime.scheduler
        let persistenceService = WindowSessionPersistenceService(
            store: persistenceRuntime.snapshotStore,
            snapshotFactory: snapshotFactory
        )
        let history = WindowSessionHistoryServices.live(
            browserManager: browserManager,
            snapshotFactory: snapshotFactory,
            startupRestore: startupSessionRestoreOwner
        )
        self.history = history
        let persistence = WindowSessionPersistenceCoordinator(
            persistence: persistenceService,
            scheduler: persistenceScheduler,
            openWindows: history.catalog,
            archive: history.archive
        )
        self.persistence = persistence
        let restoreService = WindowSessionRestoreService(
            snapshotStore: persistenceRuntime.snapshotStore,
            persistence: persistence,
            tabManager: browserManager.tabManager,
            glanceManager: browserManager.glanceManager,
            selectionService: browserManager.shellRuntime.windowSelection,
            selection: browserManager,
            floatingBarSanitizer: browserManager.urlBarBundle
                .floatingBar.presentation,
            themeCommitter: browserManager.chromeBundle
                .workspaceThemeTransitionOwner,
            splitFocus: browserManager.sidebarCommandService
                .splitShortcuts.focus
        )
        self.restoreService = restoreService
        self.sessionRecovery = BrowserSessionRecoveryCommands.live(
            browserManager: browserManager,
            startupRestore: startupSessionRestoreOwner,
            sessionRestore: restoreService,
            openWindows: history.catalog,
            archive: history.archive
        )

        self.restoration = BrowserWindowSessionRestorationService(
            restoration: restoreService,
            extensions: browserManager.optionalModules.extensions,
            profileSupport: browserManager,
            startupSessions: browserManager
        )
        self.activation = BrowserWindowActivationService(
            sidebarPresentation: browserManager.chromeBundle
                .sidebarPresentationOwner,
            persistence: persistence,
            activePageResolver: browserManager.shellRuntime.activePageResolver,
            findManager: browserManager.findManager,
            extensions: browserManager.optionalModules.extensions,
            synchronizeFocusedContext: { [weak browserManager] windowState in
                guard let browserManager else { return }
                browserManager.windowStateReconciler
                    .synchronizeFocusedSpaceContext(in: windowState)
                guard !windowState.isIncognito else { return }
                browserManager.adoptProfileIfNeeded(
                    for: windowState,
                    context: .windowActivation
                )
            },
            nowPlaying: browserManager.nativeNowPlayingController,
            backgroundMedia: browserManager.backgroundMediaOptimizationService
        )
    }
}
