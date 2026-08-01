//
//  BrowserBookmarkBundle.swift
//  Sumi
//
//  Phase T8 capability bag: bookmark commands (+ nested import/export).
//

import Foundation

/// Groups bookmark command surface so BrowserManager no longer holds a peer
/// `lazy var` Owner. Import/export stays nested under the command owner.
@MainActor
final class BrowserBookmarkBundle {
    let bookmarkCommandOwner: BrowserBookmarkCommandOwner

    init(browserManager: BrowserManager) {
        let spaces = browserManager.spaceStateOwner
        let regularTabs = browserManager
            .regularTabCollectionOwner
        let membership = browserManager
            .tabCollectionMembershipOwner
        let presentation = browserManager.bookmarkEditorPresentationState
        self.bookmarkCommandOwner = BrowserBookmarkCommandOwner(
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry.activeWindow },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.activePageResolver
                    .resolve(in: windowState)?.tab
            },
            bookmarkManager: { [weak browserManager] in browserManager?.bookmarkManager },
            bookmarkEditorPresentationRequest: { [presentation] in
                presentation.request
            },
            setBookmarkEditorPresentationRequest: { [presentation] request in
                if let request {
                    presentation.present(request)
                } else if let current = presentation.request {
                    presentation.clear(current)
                }
            },
            openNativeBrowserSurface: { [weak browserManager] kind, url, windowState, preferredSpaceId in
                browserManager?.chromeBundle.nativeSurfaceRoutingOwner.openNativeBrowserSurface(
                    kind,
                    url: url,
                    in: windowState,
                    preferredSpaceId: preferredSpaceId
                )
            },
            openHistoryURL: { [weak browserManager] url, windowState, preferredOpenMode in
                browserManager?.historyBundle.historyNavigationOwner.openHistoryURL(
                    url,
                    in: windowState,
                    preferredOpenMode: preferredOpenMode
                )
            },
            replaceTabsWithBookmarkURLs: { [weak browserManager] urls, windowState in
                guard let browserManager else { return }
                if windowState.isIncognito {
                    let tabs = windowState.ephemeralTabs
                    tabs.forEach {
                        _ = browserManager.tabCloseOrchestration.closeTab(
                            $0,
                            in: windowState
                        )
                    }
                } else if let spaceID = windowState.currentSpaceId {
                    browserManager.tabClosureService.clearRegularTabs(for: spaceID)
                }
                browserManager.historyBundle.historyNavigationOwner
                    .openHistoryURLsInNewTabs(urls, in: windowState)
            },
            openHistoryURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.historyBundle.historyNavigationOwner.openHistoryURLsInNewWindow(urls)
            },
            windowIds: { [weak browserManager] in
                browserManager.map { Array($0.windowRegistry.windows.keys) } ?? []
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.windowCommands.createNewWindow()
            },
            awaitNextRegisteredWindow: { [weak browserManager] existingWindowIDs in
                await browserManager?.windowRegistry.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                )
            },
            space: { [spaces] spaceId in
                spaceId.flatMap(spaces.space(with:))
            },
            tabsInSpace: { [regularTabs] space in
                regularTabs.tabs(in: space)
            },
            allTabs: { [membership] in
                membership.allTabs()
            },
            detectedImportSources: {
                SumiBookmarkImportSource.detectedBrowserSources()
            },
            readBookmarks: { source in
                try source.readBookmarks()
            },
            date: {
                Date()
            },
            presenter: BrowserBookmarkCommandAppKitPresenter(
                nativeSurfaceAppearance: { [weak browserManager] in
                    guard let browserManager,
                          let settings = browserManager.sumiSettings,
                          let windowState = browserManager.windowRegistry.activeWindow
                    else { return nil }
                    return windowState.nativeSurfaceAppearance(
                        settings: settings,
                        in: browserManager.windowRegistry
                    )
                }
            )
        )
    }
}
