import AppKit

@MainActor
enum TabWebPageMenuCommandsFactory {
    static func make(
        for browserManager: BrowserManager,
        ownershipQuery: WebViewOwnershipQuery
    ) -> TabWebPageMenuCommands {
        func source(
            for webView: FocusableWKWebView,
            in windowRegistry: WindowRegistry?
        ) -> (tab: Tab, window: BrowserWindowState)? {
            guard let tab = webView.owningTab,
                  let tracked = ownershipQuery.trackedOwner(containing: webView),
                  tracked.tabID == tab.id,
                  let window = windowRegistry?.windows[tracked.windowID]
            else {
                return nil
            }
            return (tab, window)
        }

        return TabWebPageMenuCommands(
            appearance: { [weak browserManager] webView, fallback in
                guard let browserManager,
                      let source = source(
                          for: webView,
                          in: browserManager.windowRegistry
                      ),
                      let settings = browserManager.sumiSettings
                else {
                    return fallback
                }
                return source.window.nativeSurfaceAppearance(
                    settings: settings,
                    fallback: fallback,
                    in: browserManager.windowRegistry
                )
            },
            canBookmark: { [weak browserManager] webView in
                guard let browserManager,
                      let source = source(
                          for: webView,
                          in: browserManager.windowRegistry
                      )
                else {
                    return false
                }
                return browserManager.bookmarkManager.canBookmark(source.tab)
            },
            requestBookmarkEditor: { [weak browserManager] webView in
                guard let browserManager,
                      let source = source(
                          for: webView,
                          in: browserManager.windowRegistry
                      )
                else {
                    return false
                }
                return browserManager.bookmarkBundle.bookmarkCommandOwner
                    .requestBookmarkEditor(
                        for: source.tab,
                        in: source.window
                    )
            },
            bookmarkLink: { [weak browserManager] webView, url, title in
                guard let browserManager,
                      source(
                          for: webView,
                          in: browserManager.windowRegistry
                      ) != nil
                else {
                    return false
                }
                return (try? browserManager.bookmarkManager.createBookmark(
                    url: url,
                    title: title ?? url.absoluteString
                )) != nil
            }
        )
    }
}
