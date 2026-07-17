//
//  BrowserPrivacyBundle.swift
//  Sumi
//
//  Privacy runtime composition.
//

import Foundation
import SumiDomain

@MainActor
final class BrowserPrivacyBundle {
    let automaticPermissionCleanup: BrowserAutomaticPermissionCleanup
    let automaticBrowsingDataCleanup: BrowserAutomaticBrowsingDataCleanup
    let permissionSidebarPinningOwner: BrowserPermissionSidebarPinningOwner

    init(
        permissionRuntime: BrowserManagerPermissionRuntime,
        dataServices: BrowserManagerDataServices,
        settings: BrowserSettingsState,
        history: HistoryManager,
        profiles: ProfileManager,
        currentProfile: BrowserCurrentProfileAuthority,
        windows: WindowRegistry,
        windowTabs: BrowserWindowTabContext
    ) {
        automaticPermissionCleanup = BrowserAutomaticPermissionCleanup(
            permissionRuntime: permissionRuntime,
            dataServices: dataServices
        )
        automaticBrowsingDataCleanup = BrowserAutomaticBrowsingDataCleanup(
            settings: settings,
            history: history,
            dataServices: dataServices,
            profiles: profiles,
            currentProfile: currentProfile
        )
        permissionSidebarPinningOwner = BrowserPermissionSidebarPinningOwner(
            permissionRuntime: permissionRuntime,
            windows: windows,
            windowTabs: windowTabs,
            pinningController: SumiPermissionSidebarPinningController()
        )
    }

    func reconcilePermissionSidebarPinning(reason: String) async {
        await permissionSidebarPinningOwner.reconcile(reason: reason)
    }
}
