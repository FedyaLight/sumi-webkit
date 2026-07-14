//
//  ExtensionActionPresentationContext.swift
//  Sumi
//
//  Window-scoped browser context used by extension action controls.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionActionBrowserContext {
    let extensionsModule: SumiExtensionsModule
    let windowState: BrowserWindowState
    let currentTab: () -> Tab?
    let currentProfileID: () -> UUID?
    let openSettingsTab: (SettingsTabs) -> Void
    let showExtensionUnavailableAlert: (_ extensionName: String, _ message: String) -> Void

    static func live(
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) -> ExtensionActionBrowserContext {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        return ExtensionActionBrowserContext(
            extensionsModule: browserManager.optionalModules.extensions,
            windowState: windowState,
            currentTab: { [weak browserManager, weak windowState] in
                guard let browserManager, let windowState else { return nil }
                return browserManager.shellRuntime.windowTabs.currentTab(for: windowState)
                    ?? windowState.currentTabId.flatMap { browserManager.tabManager.tabCollectionMembershipOwner.tab(for: $0) }
                    ?? browserManager.shellRuntime.windowSelection.currentTab(
                        for: windowState,
                        tabStore: browserManager.tabManager.runtimeStore
                    )
            },
            currentProfileID: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile?.id
            },
            openSettingsTab: { [weak browserManager, weak windowState] tab in
                guard let browserManager, let windowState else { return }
                browserManager.urlBarBundle.settingsNavigation.openSettings(
                    selecting: tab,
                    in: windowState
                )
            },
            showExtensionUnavailableAlert: { extensionName, message in
                BrowserExtensionUnavailableAlert.present(
                    extensionName: extensionName,
                    informativeText: message
                )
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionActionPresentationContext {
    let browserContext: ExtensionActionBrowserContext
    let profileId: UUID?

    func presentActionPopup(
        for installedExtension: BrowserExtensionToolbarDisplayRecord
    ) async {
        // The target is click-time authority. Waiting for startup selection
        // could silently retarget this action to a tab selected after the
        // click, so capture once before the first suspension.
        let currentTab = currentActionTab
        let actionProfileId =
            currentTab?.profileId
            ?? browserContext.windowState.currentProfileId
            ?? browserContext.currentProfileID()

        let anchorSessionToken = browserContext.extensionsModule
            .captureActionPopupAnchor(
            extensionId: installedExtension.id,
            windowId: browserContext.windowState.id,
            profileId: actionProfileId,
            tab: currentTab
            )

        guard let anchorSessionToken else {
            browserContext.showExtensionUnavailableAlert(
                installedExtension.name,
                "Sumi could not bind this popup request to the clicked browser window."
            )
            return
        }
        let result = await browserContext.extensionsModule
            .openActionPopupFromURLHub(
                extensionId: installedExtension.id,
                currentTab: currentTab,
                anchorSessionToken: anchorSessionToken
            )
        guard result.opened == false else { return }

        browserContext.showExtensionUnavailableAlert(installedExtension.name, result.message)
    }

    func openExtensionsSettings() {
        browserContext.openSettingsTab(.extensions)
    }

    func pinToToolbar(extensionId: String) {
        browserContext.extensionsModule.pinToToolbar(extensionId)
    }

    func unpinFromToolbar(extensionId: String) {
        browserContext.extensionsModule.unpinFromToolbar(extensionId)
    }

    func openOptionsPage(
        for installedExtension: BrowserExtensionToolbarDisplayRecord
    ) async {
        await browserContext.extensionsModule.openOptionsPage(
            extensionId: installedExtension.id,
            profileId: extensionActionProfileId
        )
    }

    private var extensionActionProfileId: UUID? {
        profileId
            ?? currentActionTab?.profileId
            ?? browserContext.windowState.currentProfileId
            ?? browserContext.currentProfileID()
    }

    private var currentActionTab: Tab? {
        browserContext.currentTab()
    }
}
