//
//  BrowserChromeBundle.swift
//  Sumi
//
//  Phase N2 capability bag: chrome commands, sidebar chrome, workspace theme.
//

import AppKit
import Foundation

/// Groups chrome-adjacent owners and the Phase 4C chrome command façade so
/// BrowserManager no longer holds separate peer `lazy var` Owners for thin
/// sidebar / theme / native-surface / dialog presentation wiring.
@MainActor
final class BrowserChromeBundle {
    let commands: BrowserChromeCommands
    let sidebarActionOwner: BrowserSidebarActionOwner
    let sidebarPresentationOwner: BrowserSidebarPresentationOwner
    let workspaceThemeTransitionOwner: BrowserWorkspaceThemeTransitionOwner
    let workspaceThemeEditorOwner: BrowserWorkspaceThemeEditorOwner
    let nativeSurfaceRoutingOwner: BrowserNativeSurfaceRoutingOwner
    let zoomCommandOwner: BrowserZoomCommandOwner
    let sharingPickerPresentationOwner: BrowserSharingPickerPresentationOwner
    let nativeDialogPresentationOwner: BrowserNativeDialogPresentationOwner

    init(browserManager: BrowserManager) {
        self.commands = BrowserChromeCommands(browserManager: browserManager)
        self.sidebarActionOwner = BrowserSidebarActionOwner(
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            liveFolderManager: { [liveFolderManager = browserManager.liveFolderManager] in
                liveFolderManager
            },
            sumiSettings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
        self.sidebarPresentationOwner = BrowserSidebarPresentationOwner(
            browserManager: browserManager
        )
        self.workspaceThemeTransitionOwner = BrowserWorkspaceThemeTransitionOwner(
            browserManager: browserManager
        )
        self.workspaceThemeEditorOwner = BrowserWorkspaceThemeEditorOwner(
            pickerSession: { [weak browserManager] in
                browserManager?.workspaceThemePickerSession
            },
            setPickerSession: { [weak browserManager] session in
                browserManager?.workspaceThemePickerSession = session
            },
            currentSpace: { [weak browserManager] in
                browserManager?.tabManager.spaceStateOwner.currentSpace
            },
            spaceLookup: { [weak browserManager] spaceID in
                browserManager?.tabManager.spaceStateOwner.spaces.first(where: { $0.id == spaceID })
            },
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            sidebarHostRecoveryCoordinator: { [weak browserManager] in
                browserManager?.sidebarHostRecoveryCoordinator ?? SidebarHostRecoveryCoordinator()
            },
            commitWorkspaceTheme: { [weak browserManager] theme, windowState in
                browserManager?.chromeBundle.workspaceThemeTransitionOwner.commitWorkspaceTheme(
                    theme,
                    for: windowState
                )
            },
            syncWorkspaceThemeAcrossWindows: { [weak browserManager] space, animate in
                browserManager?.chromeBundle.workspaceThemeTransitionOwner.syncWorkspaceThemeAcrossWindows(
                    for: space,
                    animate: animate
                )
            },
            scheduleStructuralPersistence: { [weak browserManager] in
                browserManager?.tabManager.structuralPersistence.markAllSpacesStructurallyDirty()
                browserManager?.tabManager.scheduleStructuralPersistence()
            },
            presentNotice: { [weak browserManager] notice, source in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.presentNoticeSheet(notice, source: source)
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
        self.nativeSurfaceRoutingOwner = BrowserNativeSurfaceRoutingOwner(
            browserManager: browserManager
        )
        let fallbackZoomManager = browserManager.zoomManager
        self.zoomCommandOwner = BrowserZoomCommandOwner(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.activePageRoutingOwner.activePageTab(for: windowState)
            },
            activePresentationWebView: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.activePageRoutingOwner.activePresentationWebView(
                    for: windowState
                )
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
            },
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.windowSessionBundle.tabContextOwner.windowState(containing: tab)
            },
            webView: { [weak browserManager] tabId, windowId in
                browserManager?.webViewRoutingService.webView(for: tabId, in: windowId)
            },
            zoomManager: { [weak browserManager] in
                browserManager?.zoomManager ?? fallbackZoomManager
            },
            sizeOverride: { [weak browserManager] url, profileId in
                browserManager?.boostsModule.sizeOverride(for: url, profileId: profileId) ?? 1.0
            },
            incrementZoomStateRevision: { [weak browserManager] in
                guard let browserManager else { return }
                browserManager.zoomStateRevision += 1
            },
            notifications: { [weak browserManager] in
                browserManager?.notificationPresenter
            }
        )
        self.sharingPickerPresentationOwner = BrowserSharingPickerPresentationOwner(
            browserManager: browserManager
        )
        self.nativeDialogPresentationOwner = BrowserNativeDialogPresentationOwner(
            windowRegistry: { [weak browserManager] in browserManager?.windowRegistry },
            nativeModalPresentation: { [weak browserManager] in browserManager?.nativeModalPresentation },
            setNativeModalPresentation: { [weak browserManager] presentation in
                browserManager?.nativeModalPresentation = presentation
            },
            postCollapsedSidebarOverlayDismissal: { [weak browserManager] in
                guard let browserManager else { return }
                NotificationCenter.default.post(
                    name: .sumiShouldHideCollapsedSidebarOverlay,
                    object: browserManager
                )
            },
            dismissFloatingBarForActiveWindow: { [weak browserManager] preserveDraft in
                browserManager?.urlBarBundle.floatingBarRoutingOwner.dismissFloatingBarForActiveWindow(
                    preserveDraft: preserveDraft
                )
            },
            dismissThemePickerDiscardingIfNeeded: { [weak browserManager] in
                browserManager?.chromeBundle.workspaceThemeEditorOwner.dismissThemePickerDiscardingIfNeeded()
            },
            dismissThemePickerCommittingIfNeeded: { [weak browserManager] in
                browserManager?.chromeBundle.workspaceThemeEditorOwner.dismissThemePickerCommittingIfNeeded()
            },
            terminateApplication: {
                NSApplication.shared.terminate(nil)
            },
            keyWindow: {
                NSApp.keyWindow
            },
            mainWindow: {
                NSApp.mainWindow
            },
            recoverSidebarHost: { [weak browserManager] window in
                browserManager?.sidebarHostRecoveryCoordinator.recover(in: window)
            },
            presentSharingServicePicker: { [weak browserManager] items, source in
                browserManager?.chromeBundle.sharingPickerPresentationOwner.presentSharingServicePicker(
                    items,
                    source: source
                )
            }
        )
    }
}
