//
//  BrowserPrivacyBundle.swift
//  Sumi
//
//  Phase 5A capability bag: permission pinning + automatic data cleanup.
//

import Foundation
import SumiDomain

/// Groups privacy-adjacent BrowserManager owners so new privacy features attach
/// here instead of as another peer `lazy var` on BrowserManager.
@MainActor
final class BrowserPrivacyBundle {
    let automaticDataCleanupOwner: BrowserAutomaticDataCleanupOwner
    let permissionSidebarPinningOwner: BrowserPermissionSidebarPinningOwner

    init(browserManager: BrowserManager) {
        self.automaticDataCleanupOwner = BrowserAutomaticDataCleanupOwner(
            browserManager: browserManager
        )
        self.permissionSidebarPinningOwner = BrowserPermissionSidebarPinningOwner(
            permissionStateSnapshot: { [weak browserManager] in
                guard let browserManager else {
                    return SumiPermissionCoordinatorState(
                        activeQueriesByPageId: [:],
                        queueCountByPageId: [:],
                        latestEvent: nil,
                        latestSystemBlockedEvent: nil
                    )
                }
                return await browserManager.permissionRuntime.permissionCoordinator.stateSnapshot()
            },
            windowForPermissionPageId: { [weak browserManager] pageId in
                guard let browserManager else { return nil }
                return BrowserPermissionSettingsRoutes.windowState(
                    displayingPermissionPageId: pageId,
                    in: browserManager.windowRegistry,
                    tabsForDisplay: { windowState in
                        browserManager.shellRuntime.windowTabs.tabsForDisplay(in: windowState)
                    }
                )
            },
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            pinningController: SumiPermissionSidebarPinningController()
        )
    }

    func reconcilePermissionSidebarPinning(reason: String) async {
        await permissionSidebarPinningOwner.reconcile(reason: reason)
    }
}
