//
//  BrowserProfileLifecycleBundle.swift
//  Sumi
//
//  Phase 5A capability bag: profile switch + startup policy.
//

import Foundation

/// Groups profile-switch transition and startup policy owners.
@MainActor
final class BrowserProfileLifecycleBundle {
    let profileSwitchTransitionOwner: BrowserProfileSwitchTransitionOwner
    let startupPolicyOwner: BrowserStartupPolicyOwner

    init(browserManager: BrowserManager) {
        self.profileSwitchTransitionOwner = BrowserProfileSwitchTransitionOwner(
            host: browserManager,
            auxiliaryWindowManager: browserManager.auxiliaryWindowManager,
            bookmarkManager: browserManager.bookmarkManager,
            extensionsModule: browserManager.extensionsModule,
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
        self.startupPolicyOwner = BrowserStartupPolicyOwner(
            regularWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows
                    .filter { !$0.isIncognito } ?? []
            },
            startupRestoreOwner: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.startupSessionRestoreOwner
            },
            tabManager: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.tabManager
            },
            startupPageURL: { [weak browserManager] in
                browserManager?.sumiSettings?.resolvedStartupPageURL
            },
            space: { [weak browserManager] spaceId in
                browserManager?.windowSessionBundle.spaceStateOwner.space(for: spaceId)
            },
            splitManager: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.splitManager
            },
            glanceManager: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.glanceManager
            },
            selectTab: { [weak browserManager] tab, windowState, loadPolicy in
                browserManager?.selectTab(tab, in: windowState, loadPolicy: loadPolicy)
            },
            showEmptyState: { [weak browserManager] windowState, presentNewTabFloatingBar in
                browserManager?.showEmptyState(
                    in: windowState,
                    presentNewTabFloatingBar: presentNewTabFloatingBar
                )
            },
            currentRegularWindowSnapshots: { [weak browserManager] excludingWindowId in
                browserManager?.windowSessionBundle.historySessionOwner.currentRegularWindowSnapshots(excludingWindowID: excludingWindowId) ?? []
            },
            currentTabSnapshot: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.tabManager.structuralPersistence.buildSnapshot()
            },
            applyWindowSessionSnapshot: { [weak browserManager] snapshot, windowState in
                guard let browserManager else { return }
                browserManager.windowSessionService.applyWindowSessionSnapshot(
                    snapshot,
                    to: windowState,
                    runtime: WindowSessionRuntimeFactory.make(for: browserManager)
                )
            },
            reopenWindow: { [weak browserManager] snapshot in
                await browserManager?.historyBundle.historyMenuOwner.reopenWindow(from: snapshot)
            },
            refreshLastSessionWindowsStore: { [weak browserManager] excludingWindowId in
                browserManager?.windowSessionBundle.historySessionOwner.refreshLastSessionWindowsStore(excludingWindowID: excludingWindowId)
            }
        )
    }
}
