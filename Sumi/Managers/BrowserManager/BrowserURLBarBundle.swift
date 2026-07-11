//
//  BrowserURLBarBundle.swift
//  Sumi
//
//  Phase 5A capability bag: URL bar context, floating bar, and URL-bar commands.
//

import Foundation
import SumiDomain

/// Groups URL-bar capabilities and the behavior-free floating-bar service set.
@MainActor
final class BrowserURLBarBundle {
    let settingsNavigation: BrowserSettingsNavigationService
    let contextOwner: BrowserURLBarContextOwner
    let floatingBar: FloatingBarServices

    init(browserManager: BrowserManager) {
        let settingsNavigation = BrowserSettingsNavigationService(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            settingsSurfaceURL: { pane in
                BrowserPermissionSettingsRoutes.settingsSurfaceURL(for: pane)
            },
            siteSettingsSurfaceURL: { tab in
                BrowserPermissionSettingsRoutes.privacySiteSettingsSurfaceURL(
                    focusing: tab
                )
            },
            openNativeSurface: { [weak browserManager] kind, url, windowState in
                browserManager?.chromeBundle.nativeSurfaceRoutingOwner
                    .openNativeBrowserSurface(kind, url: url, in: windowState)
            }
        )
        let clipboard = BrowserURLClipboardService(
            notifications: { [weak browserManager] in
                browserManager?.notificationPresenter
            }
        )
        self.settingsNavigation = settingsNavigation

        self.floatingBar = Self.makeFloatingBarServices(
            browserManager: browserManager,
            activePageResolver: browserManager.shellRuntime.activePageResolver
        )
        self.contextOwner = BrowserURLBarContextOwner(
            browserManager: browserManager,
            clipboard: clipboard,
            settingsNavigation: settingsNavigation
        )
    }
}
