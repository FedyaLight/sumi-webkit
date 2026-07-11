//
//  BrowserProfileLifecycleBundle.swift
//  Sumi
//
//  Profile switch + startup policy composition.
//

import Foundation

/// Groups the two profile-lifecycle workflows without forwarding behavior.
@MainActor
final class BrowserProfileLifecycleBundle {
    let profileSwitchTransition: BrowserProfileSwitchTransitionOwner
    let startupPolicy: BrowserStartupPolicy

    init(browserManager: BrowserManager) {
        self.profileSwitchTransition = Self.makeProfileSwitchTransition(
            browserManager: browserManager
        )
        self.startupPolicy = Self.makeStartupPolicy(browserManager: browserManager)
    }

    private static func makeProfileSwitchTransition(
        browserManager: BrowserManager
    ) -> BrowserProfileSwitchTransitionOwner {
        BrowserProfileSwitchTransitionOwner(
            host: browserManager,
            auxiliaryWindowTeardown: browserManager.auxiliaryWindows.teardown,
            bookmarkManager: browserManager.bookmarkManager,
            extensionsModule: browserManager.optionalModules.extensions,
            faviconService: browserManager.dataServices.faviconService,
            historyManager: browserManager.historyManager,
            tabManager: browserManager.tabManager,
            notifications: { [weak browserManager] in
                browserManager?.notificationPresenter
            },
            runAutomaticPermissionCleanupIfNeeded: { [weak browserManager] profile in
                _ = await browserManager?.privacyBundle.automaticDataCleanupOwner
                    .runAutomaticPermissionCleanupIfNeeded(for: profile)
            },
            scheduleAutomaticBrowsingDataCleanup: { [weak browserManager] reason in
                browserManager?.privacyBundle.automaticDataCleanupOwner.scheduleAutomaticBrowsingDataCleanup(
                    reason: reason
                )
            }
        )
    }

    private static func makeStartupPolicy(
        browserManager: BrowserManager
    ) -> BrowserStartupPolicy {
        let windowSessions = browserManager.windowSessionBundle
        let openWindows = windowSessions.history.catalog
        let sessionRestore = windowSessions.restoreService
        let sessionRecovery = windowSessions.sessionRecovery
        let regularWindows: @MainActor () -> [BrowserWindowState] = { [weak browserManager] in
            browserManager?.windowRegistry?.allWindows
                .filter { !$0.isIncognito } ?? []
        }
        let cleanStartup = CleanStartupWorkflow(
            regularWindows: regularWindows,
            startupRestore: browserManager.startupSessionRestoreOwner,
            tabManager: browserManager.tabManager,
            glanceManager: browserManager.glanceManager,
            openWindows: openWindows,
            selectTab: { [weak browserManager] tab, windowState, loadPolicy in
                browserManager?.selectTab(
                    tab,
                    in: windowState,
                    loadPolicy: loadPolicy
                )
            },
            showEmptyState: { [weak browserManager] windowState, presentBar in
                browserManager?.showEmptyState(
                    in: windowState,
                    presentNewTabFloatingBar: presentBar
                )
            }
        )
        let windowRestore = StartupWindowRestoreService(
            startupRestore: browserManager.startupSessionRestoreOwner,
            archive: windowSessions.history.archive,
            openWindows: openWindows,
            startupWindow: {
                regularWindows()
                    .min { $0.id.uuidString < $1.id.uuidString }
            },
            applySnapshot: { snapshot, windowState in
                sessionRestore.applyWindowSessionSnapshot(
                    snapshot.session,
                    to: windowState
                )
            },
            reopenWindow: { snapshot in
                await sessionRecovery.reopenWindow(from: snapshot)
            }
        )
        return BrowserStartupPolicy(
            cleanStartup: cleanStartup,
            windowRestore: windowRestore,
            startupPageURL: { [weak browserManager] in
                browserManager?.sumiSettings?.resolvedStartupPageURL
            }
        )
    }
}
