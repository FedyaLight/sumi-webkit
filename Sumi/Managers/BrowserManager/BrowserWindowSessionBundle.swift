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
    let history: WindowSessionHistoryServices
    let sessionRecovery: BrowserSessionRecoveryCommands

    init(
        browserManager: BrowserManager,
        startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner,
        splitFocus: SplitShortcutFocusService,
        history: WindowSessionHistoryServices,
        persistence: WindowSessionPersistenceCoordinator
    ) {
        let persistenceRuntime = browserManager.windowSessionPersistence
        self.history = history
        let spaceResolver = WindowSessionSpaceResolver(
            spaces: browserManager.spaceStateOwner,
            membership: browserManager.tabCollectionMembershipOwner
        )
        let shortcutRestorer = WindowSessionShortcutRestorer(
            pins: browserManager.shortcutPinCollectionStateOwner,
            activation: browserManager.shortcutPresentationActivation
        )
        let splitRestorer = WindowSessionSplitRestorer(
            groups: browserManager.splitGroupStore,
            startupRestore: browserManager.startupRestoreLifecycle,
            focus: splitFocus
        )
        let themeRestorer = WindowSessionThemeRestorer(
            startupRestore: browserManager.startupRestoreLifecycle,
            spaceResolver: spaceResolver,
            themeCommitter: browserManager.chromeBundle
                .workspaceThemeTransitionOwner
        )
        let restoreService = WindowSessionRestoreService(
            snapshotStore: persistenceRuntime.snapshotStore,
            persistence: persistence,
            profileReferenceAdmission: browserManager.profileReferenceAdmission,
            membership: browserManager.tabCollectionMembershipOwner,
            startupRestore: browserManager.startupRestoreLifecycle,
            tabStore: browserManager.runtimeStore,
            glanceManager: browserManager.glanceManager,
            spaceResolver: spaceResolver,
            shortcutRestorer: shortcutRestorer,
            splitRestorer: splitRestorer,
            themeRestorer: themeRestorer,
            selectionService: browserManager.shellRuntime.windowSelection,
            selection: browserManager,
            floatingBarSanitizer: browserManager.urlBarBundle
                .floatingBar.presentation
        )
        self.restoreService = restoreService
        self.sessionRecovery = BrowserSessionRecoveryCommands.live(
            browserManager: browserManager,
            startupRestore: startupSessionRestoreOwner,
            sessionRestore: restoreService,
            openWindows: history.catalog,
            archive: history.archive,
            shortcutActivation: browserManager.shortcutPresentationActivation,
            shortcutPinStore: browserManager.shortcutPinStoreOwner
        )

        self.restoration = BrowserWindowSessionRestorationService(
            restoration: restoreService,
            tabResidences: browserManager.tabResidenceAuthority,
            extensionPublication: browserManager.windowExtensionPublication,
            currentProfile: browserManager.currentProfileAuthority,
            startupSessions: browserManager
        )
    }
}

extension BrowserManager {
    func composeWindowActivation() -> BrowserWindowActivationService {
        BrowserWindowActivationService(
            sidebarPresentation: chromeBundle.sidebarPresentationOwner,
            persistence: windowSessionPersistenceCoordinator,
            activePageResolver: shellRuntime.activePageResolver,
            findManager: findManager,
            extensions: optionalModules.extensions,
            focusedContext: BrowserWindowFocusedContextSynchronizer(
                windowState: windowStateReconciler,
                profileAdoption: profileAdoption
            ),
            nowPlaying: nativeNowPlayingController,
            backgroundMedia: backgroundMediaOptimizationService
        )
    }
}
