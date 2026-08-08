import AppKit
import SumiDomain

/// Lifecycle orchestrator for one webview's page context menus. Bridges
/// AppKit's `willOpenMenu`/`didCloseMenu` to the blueprint rewrite, deferring
/// the rewrite when the trusted DOM snapshot has not arrived yet (the
/// `contextmenu` script message races WebKit's menu construction). Each
/// presented menu is rewritten exactly once; without a snapshot the menu
/// falls back to native items so no functionality ever disappears.
@MainActor
final class SumiWebPageMenuPresenter {
    /// How long a presented menu waits for the DOM snapshot before rewriting
    /// with native-preserving fallback (JS disabled, PDF/image documents).
    static let deferredSnapshotTimeout: TimeInterval = 0.15

    let actionOwner = SumiWebPageMenuActionOwner()

    private weak var currentMenu: NSMenu?
    private weak var currentWebView: FocusableWKWebView?
    private var hasRewrittenCurrentMenu = false

    func menuWillOpen(_ menu: NSMenu, for webView: FocusableWKWebView) {
        if currentMenu === menu, currentWebView === webView {
            return
        }
        currentMenu = menu
        currentWebView = webView
        hasRewrittenCurrentMenu = false

        applyAppearance(to: menu, for: webView)

        if let snapshot = webView.contextMenu.recentTarget() {
            rewrite(menu, for: webView, snapshot: snapshot)
            return
        }

        webView.contextMenu.awaitNextRecord { [weak self, weak menu, weak webView] snapshot in
            guard let self, let menu, let webView else { return }
            self.rewrite(menu, for: webView, snapshot: snapshot)
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.deferredSnapshotTimeout
        ) { [weak self, weak menu, weak webView] in
            guard let self, let menu, let webView else { return }
            self.rewrite(menu, for: webView, snapshot: nil)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard currentMenu === menu else { return }
        currentWebView?.contextMenu.clear()
        currentMenu = nil
        currentWebView = nil
        hasRewrittenCurrentMenu = false
    }

    // MARK: - Rewrite

    private func rewrite(
        _ menu: NSMenu,
        for webView: FocusableWKWebView,
        snapshot: SumiWebPageContextMenuTargetSnapshot?
    ) {
        guard currentMenu === menu,
              currentWebView === webView,
              !hasRewrittenCurrentMenu
        else { return }
        hasRewrittenCurrentMenu = true
        webView.contextMenu.cancelPendingRecordHandler()

        let context = SumiWebPageMenuContext(
            menu: menu,
            snapshot: snapshot,
            searchProviderName: searchProviderName(for: webView),
            isLoading: webView.isLoading,
            isDeveloperInspectionEnabled: RuntimeDiagnostics.isDeveloperInspectionEnabled
        )
        actionOwner.prepare(webView: webView, context: context)
        SumiWebPageMenuRewriteEngine(
            menu: menu,
            context: context,
            itemFactory: SumiWebPageMenuItemFactory(actionTarget: actionOwner)
        ).apply(SumiWebPageMenuBlueprint(context: context))
        actionOwner.updateOwnedItemState(in: menu)
    }

    // MARK: - Presentation-wide concerns

    private func applyAppearance(to menu: NSMenu, for webView: FocusableWKWebView) {
        guard let appearance = webView.owningTab?.webPageMenuCommands.appearance(
            for: webView,
            fallback: webView.window?.effectiveAppearance
        ) else { return }
        menu.sumiApplyAppearance(appearance)
    }

    private func searchProviderName(for webView: FocusableWKWebView) -> String {
        guard let settings = webView.owningTab?.sumiSettings else {
            return SearchProvider.duckDuckGo.displayName
        }
        return settings.resolvedSearchEngineDisplayName
    }
}
