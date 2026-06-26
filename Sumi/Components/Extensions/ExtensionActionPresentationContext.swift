//
//  ExtensionActionPresentationContext.swift
//  Sumi
//
//  Window-scoped browser context used by extension action controls.
//

import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionActionPresentationContext {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let profileId: UUID?

    func presentActionPopup(for installedExtension: InstalledExtension) async {
        let currentTab = await currentActionTabForClick()
        let actionProfileId =
            currentTab?.profileId
            ?? windowState.currentProfileId
            ?? browserManager.currentProfile?.id

        browserManager.extensionsModule.captureActionPopupAnchor(
            extensionId: installedExtension.id,
            windowId: windowState.id,
            profileId: actionProfileId
        )

        let result = await browserManager.extensionsModule
            .openActionPopupFromURLHub(
                extensionId: installedExtension.id,
                currentTab: currentTab
            )
        guard result.opened == false else { return }

        browserManager.showBrowserExtensionsUnavailableAlert(
            extensionName: installedExtension.name,
            informativeText: result.message
        )
    }

    func openExtensionsSettings() {
        browserManager.openSettingsTab(selecting: .extensions, in: windowState)
    }

    func pinToToolbar(extensionId: String) {
        browserManager.extensionsModule.pinToToolbar(extensionId)
    }

    func unpinFromToolbar(extensionId: String) {
        browserManager.extensionsModule.unpinFromToolbar(extensionId)
    }

    func openOptionsPage(for installedExtension: InstalledExtension) async {
        await browserManager.extensionsModule.openOptionsPage(
            extensionId: installedExtension.id,
            profileId: extensionActionProfileId
        )
    }

    private var extensionActionProfileId: UUID? {
        profileId
            ?? currentActionTab?.profileId
            ?? windowState.currentProfileId
            ?? browserManager.currentProfile?.id
    }

    private func currentActionTabForClick() async -> Tab? {
        if let currentTab = currentActionTab {
            return currentTab
        }

        guard windowState.isAwaitingInitialSessionResolution
                || !browserManager.tabManager.hasLoadedInitialData
        else {
            return nil
        }

        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let currentTab = currentActionTab {
                return currentTab
            }
            if !windowState.isAwaitingInitialSessionResolution
                && browserManager.tabManager.hasLoadedInitialData
            {
                return nil
            }
        }
        return currentActionTab
    }

    private var currentActionTab: Tab? {
        browserManager.currentTab(for: windowState)
            ?? windowState.currentTabId.flatMap { browserManager.tabManager.tab(for: $0) }
            ?? browserManager.shellSelectionService.currentTab(
                for: windowState,
                tabStore: browserManager.tabManager.runtimeStore
            )
    }
}
