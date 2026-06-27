import Foundation

@MainActor
extension FloatingBarNavigationOwner.Actions {
    static func browserManager(_ browserManager: BrowserManager) -> Self {
        Self(
            activeWindow: {
                browserManager.windowRegistry?.activeWindow
            },
            window: { windowId in
                browserManager.windowRegistry?.windows[windowId]
            },
            activePageTab: { windowState in
                browserManager.activePageTab(for: windowState)
            },
            cancelEmptySplitPlaceholder: { windowState in
                browserManager.splitManager.cancelEmptySplitPlaceholder(in: windowState)
            },
            commitEmptySplitPlaceholder: { tabId, windowState in
                browserManager.splitManager.commitEmptySplitPlaceholder(tabId: tabId, in: windowState)
            },
            replaceEmptySplitPlaceholder: { tab, windowState in
                browserManager.splitManager.replaceEmptySplitPlaceholder(with: tab, in: windowState)
            },
            selectTab: { tab, windowState in
                browserManager.selectTab(tab, in: windowState)
            },
            createNewTab: { windowState, url in
                browserManager.createNewTab(in: windowState, url: url)
            },
            createNewTabAfterSidebarInsertion: { windowState, url in
                _ = browserManager.createNewTabAfterSidebarInsertion(in: windowState, url: url)
            },
            configuredNewTabPageURL: {
                guard let settings = browserManager.sumiSettings,
                      settings.newTabMode == .specificPage else {
                    return nil
                }
                return settings.resolvedNewTabPageURL.absoluteString
            },
            normalizeURL: { text in
                let template = browserManager.sumiSettings?.resolvedSearchEngineTemplate
                    ?? SearchProvider.google.queryTemplate
                return Sumi.normalizeURL(text, queryTemplate: template)
            },
            dismissWorkspaceThemePickerIfNeededDiscarding: {
                browserManager.dismissWorkspaceThemePickerIfNeededDiscarding()
            },
            persistWindowSession: { windowState in
                browserManager.persistWindowSession(for: windowState)
            },
            schedulePersistWindowSession: { windowState in
                browserManager.schedulePersistWindowSession(for: windowState)
            }
        )
    }
}
