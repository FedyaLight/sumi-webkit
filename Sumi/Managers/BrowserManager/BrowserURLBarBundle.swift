//
//  BrowserURLBarBundle.swift
//  Sumi
//
//  Phase 5A capability bag: URL bar context, floating bar, and URL-bar commands.
//

import Foundation

/// Groups URL-bar / floating-bar owners and the Phase 4C URL-bar command façade.
@MainActor
final class BrowserURLBarBundle {
    let commands: BrowserURLBarCommands
    let contextOwner: BrowserURLBarContextOwner
    let floatingBarRoutingOwner: BrowserFloatingBarRoutingOwner
    let floatingBarBrowserContextOwner: BrowserFloatingBarBrowserContextOwner
    let activePageRoutingOwner: BrowserActivePageRoutingOwner

    init(browserManager: BrowserManager) {
        self.commands = BrowserURLBarCommands(
            browserManager: browserManager,
            notifications: { [weak browserManager] in browserManager?.notificationPresenter }
        )
        self.contextOwner = BrowserURLBarContextOwner(browserManager: browserManager)
        let tabLifecycleService = browserManager.tabLifecycleService
        self.floatingBarRoutingOwner = BrowserFloatingBarRoutingOwner(
            tabOpeningOwner: { tabLifecycleService.opening },
            windowRegistry: { [weak browserManager] in browserManager?.windowRegistry },
            settings: { [weak browserManager] in browserManager?.sumiSettings },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.activePageRoutingOwner.activePageTab(for: windowState)
            },
            hasValidCurrentSelection: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.spaceStateOwner.hasValidCurrentSelection(in: windowState) ?? false
            },
            cancelEmptySplitPlaceholder: { [weak browserManager] windowState in
                browserManager?.splitManager.cancelEmptySplitPlaceholder(in: windowState)
            },
            commitEmptySplitPlaceholder: { [weak browserManager] tabId, windowState in
                browserManager?.splitManager.commitEmptySplitPlaceholder(tabId: tabId, in: windowState)
            },
            replaceEmptySplitPlaceholder: { [weak browserManager] tab, windowState in
                browserManager?.splitManager.replaceEmptySplitPlaceholder(with: tab, in: windowState) ?? false
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            loadCurrentPageURL: { [weak browserManager] tab, windowState, urlString in
                browserManager?.windowSessionBundle.scopedNavigationOwner.loadFloatingBarCurrentPage(
                    urlString,
                    tab: tab,
                    in: windowState
                )
            },
            navigateCurrentPage: { [weak browserManager] tab, windowState, input in
                browserManager?.windowSessionBundle.scopedNavigationOwner.navigateFloatingBarCurrentPage(
                    input,
                    tab: tab,
                    in: windowState
                )
            },
            dismissThemePickerDiscardingIfNeeded: { [weak browserManager] in
                browserManager?.chromeBundle.workspaceThemeEditorOwner.dismissThemePickerDiscardingIfNeeded()
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            },
            schedulePersistWindowSession: { [weak browserManager] windowState, delayNanoseconds in
                browserManager?.windowSessionBundle.persistence.schedule(
                    windowState,
                    delayNanoseconds: delayNanoseconds
                )
            }
        )
        self.floatingBarBrowserContextOwner = BrowserFloatingBarBrowserContextOwner(
            browserManager: browserManager
        )
        self.activePageRoutingOwner = BrowserActivePageRoutingOwner(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.tabContextOwner.currentTab(for: windowState)
            },
            activePreviewTab: { [weak browserManager] windowState in
                browserManager?.glanceManager.activePreviewTab(for: windowState)
            },
            activePreviewWebView: { [weak browserManager] windowState in
                browserManager?.glanceManager.activePreviewWebView(for: windowState)
            },
            activeSessionURL: { [weak browserManager] windowState in
                browserManager?.glanceManager.activeSession(for: windowState)?.currentURL
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.webViewRoutingService.windowOwnedWebView(for: tab, in: windowId)
            },
            refreshActivePage: { [weak browserManager] tab, windowState in
                browserManager?.windowSessionBundle.scopedNavigationOwner.refreshWindowScopedPage(
                    tab: tab,
                    in: windowState,
                    reason: "BrowserActivePage.refresh"
                )
            },
            createNewTab: { [weak browserManager] windowState, urlString in
                browserManager?.tabLifecycleService.opening.createNewTab(in: windowState, url: urlString)
            },
            openNewTab: { [weak browserManager] urlString, context in
                browserManager?.tabLifecycleService.opening.openNewTab(url: urlString, context: context)
            },
            containsSpace: { [weak browserManager] spaceId in
                browserManager?.tabManager.spaceStateOwner.spaces.contains { $0.id == spaceId } == true
            },
            folderSpaceId: { [weak browserManager] folderId in
                browserManager?.tabManager.folderCollectionStateOwner.spaceId(for: folderId)
            },
            resolveEssentialsInsertion: { [weak browserManager] windowState, index in
                browserManager?.tabManager.essentialsShortcutPlacementOwner.resolveInsertion(
                    using: EssentialsShortcutPlacementOwner.InsertionContext(
                        target: EssentialsShortcutPlacementOwner.TargetContext(windowState: windowState),
                        targetIndex: index
                    )
                )
            },
            convertTabToShortcutPin: { [weak browserManager] tab, role, profileId, spaceId, folderId, index, openTargetFolder in
                browserManager?.tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                    tab,
                    role: role,
                    profileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    at: index,
                    openTargetFolder: openTargetFolder
                )
            },
            copyURLToPasteboard: { [weak browserManager] url, windowState in
                browserManager?.urlBarBundle.commands.copyURLToPasteboard(url, in: windowState) ?? false
            }
        )
    }
}
