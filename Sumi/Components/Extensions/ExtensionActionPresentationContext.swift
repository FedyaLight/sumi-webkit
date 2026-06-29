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
    let userscriptsModule: SumiUserscriptsModule
    let windowState: BrowserWindowState
    let currentTab: () -> Tab?
    let currentProfileID: () -> UUID?
    let hasLoadedInitialData: () -> Bool
    let webView: (Tab) -> WKWebView?
    let openSettingsTab: (SettingsTabs) -> Void
    let showExtensionUnavailableAlert: (_ extensionName: String, _ message: String) -> Void

    static func live(
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) -> ExtensionActionBrowserContext {
        ExtensionActionBrowserContext(
            extensionsModule: browserManager.extensionsModule,
            userscriptsModule: browserManager.userscriptsModule,
            windowState: windowState,
            currentTab: { [weak browserManager, weak windowState] in
                guard let browserManager, let windowState else { return nil }
                return browserManager.currentTab(for: windowState)
                    ?? windowState.currentTabId.flatMap { browserManager.tabManager.tab(for: $0) }
                    ?? browserManager.shellSelectionService.currentTab(
                        for: windowState,
                        tabStore: browserManager.tabManager.runtimeStore
                    )
            },
            currentProfileID: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            hasLoadedInitialData: { [weak browserManager] in
                browserManager?.tabManager.hasLoadedInitialData ?? true
            },
            webView: { [weak browserManager, weak windowState] tab in
                guard let browserManager, let windowState else {
                    return tab.existingWebView
                }
                return browserManager.getWebView(for: tab.id, in: windowState.id)
                    ?? tab.existingWebView
            },
            openSettingsTab: { [weak browserManager, weak windowState] tab in
                guard let browserManager, let windowState else { return }
                browserManager.openSettingsTab(selecting: tab, in: windowState)
            },
            showExtensionUnavailableAlert: { [weak browserManager] extensionName, message in
                browserManager?.showBrowserExtensionsUnavailableAlert(
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

    func presentActionPopup(for installedExtension: InstalledExtension) async {
        let currentTab = await currentActionTabForClick()
        let actionProfileId =
            currentTab?.profileId
            ?? browserContext.windowState.currentProfileId
            ?? browserContext.currentProfileID()

        browserContext.extensionsModule.captureActionPopupAnchor(
            extensionId: installedExtension.id,
            windowId: browserContext.windowState.id,
            profileId: actionProfileId
        )

        let result = await browserContext.extensionsModule
            .openActionPopupFromURLHub(
                extensionId: installedExtension.id,
                currentTab: currentTab
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

    func openOptionsPage(for installedExtension: InstalledExtension) async {
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

    private func currentActionTabForClick() async -> Tab? {
        if let currentTab = currentActionTab {
            return currentTab
        }

        guard browserContext.windowState.isAwaitingInitialSessionResolution
                || !browserContext.hasLoadedInitialData()
        else {
            return nil
        }

        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let currentTab = currentActionTab {
                return currentTab
            }
            if !browserContext.windowState.isAwaitingInitialSessionResolution
                && browserContext.hasLoadedInitialData() {
                return nil
            }
        }
        return currentActionTab
    }

    private var currentActionTab: Tab? {
        browserContext.currentTab()
    }
}
