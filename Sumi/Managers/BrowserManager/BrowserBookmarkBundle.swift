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
        self.bookmarkCommandOwner = BrowserBookmarkCommandOwner(
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.activePageRoutingOwner.activePageTab(for: windowState)
            },
            bookmarkManager: { [weak browserManager] in browserManager?.bookmarkManager },
            bookmarkEditorPresentationRequest: { [weak browserManager] in
                browserManager?.bookmarkEditorPresentationRequest
            },
            setBookmarkEditorPresentationRequest: { [weak browserManager] request in
                browserManager?.bookmarkEditorPresentationRequest = request
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
            openHistoryURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.historyBundle.historyNavigationOwner.openHistoryURLsInNewWindow(urls)
            },
            windowIds: { [weak browserManager] in
                browserManager?.windowRegistry.map { Array($0.windows.keys) } ?? []
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.windowSessionBundle.commands.createNewWindow()
            },
            awaitNextRegisteredWindow: { [weak browserManager] existingWindowIDs in
                await browserManager?.windowRegistry?.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                )
            },
            space: { [weak browserManager] spaceId in
                browserManager?.windowSessionBundle.spaceStateOwner.space(for: spaceId)
            },
            tabsInSpace: { [weak browserManager] space in
                browserManager?.tabManager.regularTabCollectionOwner.tabs(in: space) ?? []
            },
            allTabs: { [weak browserManager] in
                browserManager?.tabManager.tabCollectionMembershipOwner.allTabs() ?? []
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
                          let windowState = browserManager.windowRegistry?.activeWindow
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
