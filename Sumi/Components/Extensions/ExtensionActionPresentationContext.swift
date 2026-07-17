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
    private let tabs: SidebarExtensionActionTabQuery?
    private let profileAuthority: BrowserCurrentProfileAuthority?
    private let settingsNavigation: BrowserSettingsNavigationService?

    init(
        extensionsModule: SumiExtensionsModule,
        windowState: BrowserWindowState,
        tabs: SidebarExtensionActionTabQuery,
        profileAuthority: BrowserCurrentProfileAuthority,
        settingsNavigation: BrowserSettingsNavigationService
    ) {
        self.extensionsModule = extensionsModule
        self.windowState = windowState
        self.tabs = tabs
        self.profileAuthority = profileAuthority
        self.settingsNavigation = settingsNavigation
    }

    static func unavailable(
        extensionsModule: SumiExtensionsModule,
        windowState: BrowserWindowState
    ) -> Self {
        Self(
            extensionsModule: extensionsModule,
            windowState: windowState,
            tabs: nil,
            profileAuthority: nil,
            settingsNavigation: nil
        )
    }

    private init(
        extensionsModule: SumiExtensionsModule,
        windowState: BrowserWindowState,
        tabs: SidebarExtensionActionTabQuery?,
        profileAuthority: BrowserCurrentProfileAuthority?,
        settingsNavigation: BrowserSettingsNavigationService?
    ) {
        self.extensionsModule = extensionsModule
        self.windowState = windowState
        self.tabs = tabs
        self.profileAuthority = profileAuthority
        self.settingsNavigation = settingsNavigation
    }

    static func live(
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) -> ExtensionActionBrowserContext {
        ExtensionActionBrowserContext(
            extensionsModule: browserManager.optionalModules.extensions,
            windowState: windowState,
            tabs: SidebarExtensionActionTabQuery(
                windowTabs: browserManager.shellRuntime.windowTabs,
                membership: browserManager.tabCollectionMembershipOwner,
                selection: browserManager.shellRuntime.windowSelection,
                tabStore: browserManager.runtimeStore
            ),
            profileAuthority: browserManager.currentProfileAuthority,
            settingsNavigation: browserManager.urlBarBundle.settingsNavigation
        )
    }

    func currentTab() -> Tab? {
        tabs?.currentTab(in: windowState)
    }

    func currentProfileID() -> UUID? {
        profileAuthority?.currentProfile?.id
    }

    func openSettingsTab(_ tab: SettingsTabs) {
        settingsNavigation?.openSettings(selecting: tab, in: windowState)
    }

    func showExtensionUnavailableAlert(
        _ extensionName: String,
        _ message: String
    ) {
        BrowserExtensionUnavailableAlert.present(
            extensionName: extensionName,
            informativeText: message
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
        browserContext.extensionsModule.pinToToolbar(
            extensionId,
            profileId: profileId
        )
    }

    func unpinFromToolbar(extensionId: String) {
        browserContext.extensionsModule.unpinFromToolbar(
            extensionId,
            profileId: profileId
        )
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
