import AppKit
import WebKit
import SumiDomain

/// Shapes the contextual menu after WebKit has resolved the page element under
/// the pointer. Element commands keep their native WebKit actions and targets.
@MainActor
final class SumiWebPageMenuController: NSObject, NSMenuItemValidation {
    private weak var webView: FocusableWKWebView?
    private var preparedSelectedText: String?

    func prepare(
        _ menu: NSMenu,
        for webView: FocusableWKWebView,
        targetHint: SumiWebPageContextMenuTargetKind? = nil,
        selectedText: String? = nil
    ) {
        self.webView = webView
        let recentTarget = webView.contextMenu.recentTarget()
        let resolvedTargetHint = targetHint ?? recentTarget?.kind
        let resolvedSelectedText = selectedText ?? recentTarget?.selectedText
        preparedSelectedText = resolvedSelectedText
        SumiWebPageMenuComposer(
            menu: menu,
            webView: webView,
            actionTarget: self,
            targetHint: resolvedTargetHint,
            selectedText: resolvedSelectedText
        ).compose()
        appendExtensionMenuItems(to: menu, for: webView)
        updateOwnedItemState(in: menu)

        if let appearance = webView.owningTab?.webPageMenuCommands.appearance(
            for: webView,
            fallback: webView.window?.effectiveAppearance
        ) {
            menu.sumiApplyAppearance(appearance)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = SumiWebPageMenuCommand(menuItem.identifier),
              let webView
        else { return true }

        switch command {
        case .back:
            return webView.canGoBack
        case .forward:
            return webView.canGoForward
        case .reload:
            return true
        case .stop:
            return webView.isLoading
        case .bookmarkPage:
            return webView.owningTab?.webPageMenuCommands.canBookmark(webView)
                ?? false
        case .copyPageAddress:
            return pageURL != nil
        case .copySelection:
            return selectedText != nil
        case .copyLinkToSelectedText:
            return selectedTextFragmentURL != nil
        case .searchSelection:
            return selectedTextSearchURL != nil
        case .printPage:
            return true
        }
    }

    @objc func goBack(_: Any?) {
        guard let webView, webView.canGoBack else { return }
        SumiWebViewNavigator.goBack(on: webView)
    }

    @objc func goForward(_: Any?) {
        guard let webView, webView.canGoForward else { return }
        SumiWebViewNavigator.goForward(on: webView)
    }

    @objc func reloadPage(_: Any?) {
        if let tab = webView?.owningTab {
            tab.refresh()
        } else {
            webView?.reload()
        }
    }

    @objc func stopLoading(_: Any?) {
        guard let webView else { return }
        if let tab = webView.owningTab {
            tab.stopLoading(on: webView)
        } else {
            webView.stopLoading()
        }
    }

    @objc func bookmarkPage(_: Any?) {
        guard let webView else { return }
        _ = webView.owningTab?.webPageMenuCommands.requestBookmarkEditor(
            from: webView
        )
    }

    @objc func copyPageAddress(_: Any?) {
        guard let url = pageURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    @objc func copySelection(_: Any?) {
        guard let selectedText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
    }

    @objc func copyLinkToSelectedText(_: Any?) {
        guard let url = selectedTextFragmentURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    @objc func searchSelection(_: Any?) {
        guard let url = selectedTextSearchURL else { return }
        openInNewTab(url)
    }

    @objc func printPage(_: Any?) {
        guard let webView else { return }
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        let operation = webView.printOperation(with: printInfo)

        if let printView = operation.view {
            printView.frame = CGRect(origin: .zero, size: nonZeroPrintSize(for: webView))
            printView.layoutSubtreeIfNeeded()
        }

        DispatchQueue.main.async { [weak webView] in
            if let window = webView?.window {
                operation.runModal(
                    for: window,
                    delegate: nil,
                    didRun: nil,
                    contextInfo: nil
                )
            } else {
                operation.run()
            }
        }
    }

    /// Safari places extension-provided items in their own group at the end
    /// of the page menu. WebKit builds the items (targets included); Sumi only
    /// hosts them, fetched fresh on every presentation.
    private func appendExtensionMenuItems(
        to menu: NSMenu,
        for webView: FocusableWKWebView
    ) {
        guard let tab = webView.owningTab else { return }
        let extensionItems = tab.navigationRuntime.normalWebViewExtensionRuntime
            .pageContextMenuItems(tab)
        guard extensionItems.isEmpty == false else { return }

        if menu.items.isEmpty == false {
            menu.addItem(.separator())
        }
        for item in extensionItems {
            menu.addItem(item)
        }
    }

    private var pageURL: URL? {
        guard let url = webView?.url ?? webView?.owningTab?.url,
              !url.absoluteString.isEmpty
        else { return nil }
        return url
    }

    private var selectedText: String? {
        preparedSelectedText
    }

    private var selectedTextFragmentURL: URL? {
        guard let text = selectedText,
              let pageURL,
              var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased())
        else { return nil }

        components.fragment = ":~:text=\(SumiWebPageMenuTextFormatter.textFragmentComponent(for: text))"
        return components.url
    }

    private var selectedTextSearchURL: URL? {
        guard let text = selectedText else { return nil }
        let template = webView?.owningTab?.sumiSettings?.resolvedSearchEngineTemplate
            ?? SearchProvider.duckDuckGo.queryTemplate
        return URL(string: normalizeURL(text, queryTemplate: template))
    }

    private func updateOwnedItemState(in menu: NSMenu) {
        for item in menu.items {
            if SumiWebPageMenuCommand(item.identifier) != nil {
                item.isEnabled = validateMenuItem(item)
            }
            if let submenu = item.submenu {
                updateOwnedItemState(in: submenu)
            }
        }
    }

    private func openInNewTab(_ url: URL) {
        guard let webView else { return }
        webView.owningTab?.linkPresentationCommands.open(
            url,
            from: webView,
            disposition: .newTab(selected: true)
        )
    }

    private func nonZeroPrintSize(for webView: WKWebView) -> CGSize {
        let boundsSize = webView.bounds.size
        if boundsSize.width > 0, boundsSize.height > 0 {
            return boundsSize
        }

        return CGSize(width: 800, height: 1_000)
    }
}

@MainActor
extension NSMenu {
    func sumiNormalizeSeparators() {
        while items.first?.isSeparatorItem == true {
            removeItem(at: 0)
        }
        while items.last?.isSeparatorItem == true {
            removeItem(at: numberOfItems - 1)
        }

        var previousWasSeparator = false
        for index in items.indices.reversed() {
            let item = items[index]
            if item.isSeparatorItem, previousWasSeparator {
                removeItem(at: index)
                continue
            }
            previousWasSeparator = item.isSeparatorItem
        }
    }
}
