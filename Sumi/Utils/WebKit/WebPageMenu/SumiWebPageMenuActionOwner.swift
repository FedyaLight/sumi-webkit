import AppKit
import WebKit
import SumiDomain

/// Owns every Sumi command action in the web page context menu and their
/// enablement. URL-bearing commands validate their scheme at action time;
/// link and window routing goes through the owning tab's
/// `linkPresentationCommands`, never through WebKit's new-window path.
@MainActor
final class SumiWebPageMenuActionOwner: NSObject, NSMenuItemValidation {
    private weak var webView: FocusableWKWebView?
    private var context: SumiWebPageMenuContext?

    func prepare(webView: FocusableWKWebView, context: SumiWebPageMenuContext) {
        self.webView = webView
        self.context = context
    }

    static func action(for command: SumiWebPageMenuCommand) -> Selector {
        switch command {
        case .back:
            return #selector(SumiWebPageMenuActionOwner.goBack(_:))
        case .forward:
            return #selector(SumiWebPageMenuActionOwner.goForward(_:))
        case .reload:
            return #selector(SumiWebPageMenuActionOwner.reloadPage(_:))
        case .stop:
            return #selector(SumiWebPageMenuActionOwner.stopLoading(_:))
        case .bookmarkPage:
            return #selector(SumiWebPageMenuActionOwner.bookmarkPage(_:))
        case .copyPageAddress:
            return #selector(SumiWebPageMenuActionOwner.copyPageAddress(_:))
        case .printPage:
            return #selector(SumiWebPageMenuActionOwner.printPage(_:))
        case .copySelection:
            return #selector(SumiWebPageMenuActionOwner.copySelection(_:))
        case .copyLinkToSelectedText:
            return #selector(SumiWebPageMenuActionOwner.copyLinkToSelectedText(_:))
        case .searchSelection:
            return #selector(SumiWebPageMenuActionOwner.searchSelection(_:))
        case .openLinkInNewTab:
            return #selector(SumiWebPageMenuActionOwner.openLinkInNewTab(_:))
        case .openLinkInNewWindow:
            return #selector(SumiWebPageMenuActionOwner.openLinkInNewWindow(_:))
        case .addLinkToBookmarks:
            return #selector(SumiWebPageMenuActionOwner.addLinkToBookmarks(_:))
        case .copyLink:
            return #selector(SumiWebPageMenuActionOwner.copyLink(_:))
        case .copyEmailAddress:
            return #selector(SumiWebPageMenuActionOwner.copyEmailAddress(_:))
        case .openImageInNewTab:
            return #selector(SumiWebPageMenuActionOwner.openImageInNewTab(_:))
        case .openImageInNewWindow:
            return #selector(SumiWebPageMenuActionOwner.openImageInNewWindow(_:))
        case .copyImageAddress:
            return #selector(SumiWebPageMenuActionOwner.copyImageAddress(_:))
        }
    }

    // MARK: - Validation

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
        case .openLinkInNewTab, .openLinkInNewWindow, .addLinkToBookmarks:
            return routableLinkURL != nil && webView.owningTab != nil
        case .copyLink:
            return context?.linkURL != nil
        case .copyEmailAddress:
            return context?.mailtoAddresses.isEmpty == false
        case .openImageInNewTab, .openImageInNewWindow:
            return routableImageURL != nil && webView.owningTab != nil
        case .copyImageAddress:
            return context?.imageURL != nil
        }
    }

    func updateOwnedItemState(in menu: NSMenu) {
        for item in menu.items {
            if SumiWebPageMenuCommand(item.identifier) != nil {
                item.isEnabled = validateMenuItem(item)
            }
            if let submenu = item.submenu {
                updateOwnedItemState(in: submenu)
            }
        }
    }

    // MARK: - Page actions

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
        copyString(pageURL?.absoluteString)
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

    // MARK: - Selection actions

    @objc func copySelection(_: Any?) {
        copyString(selectedText)
    }

    @objc func copyLinkToSelectedText(_: Any?) {
        copyString(selectedTextFragmentURL?.absoluteString)
    }

    @objc func searchSelection(_: Any?) {
        guard let url = selectedTextSearchURL else { return }
        open(url, disposition: .newTab(selected: true))
    }

    // MARK: - Link actions

    @objc func openLinkInNewTab(_: Any?) {
        guard let url = routableLinkURL else { return }
        open(url, disposition: .newTab(selected: true))
    }

    @objc func openLinkInNewWindow(_: Any?) {
        guard let url = routableLinkURL else { return }
        open(url, disposition: .newWindow(selected: true))
    }

    @objc func addLinkToBookmarks(_: Any?) {
        guard let webView, let url = routableLinkURL else { return }
        _ = webView.owningTab?.webPageMenuCommands.bookmarkLink(
            from: webView,
            url: url,
            title: context?.linkText ?? context?.selectedText
        )
    }

    @objc func copyLink(_: Any?) {
        copyString(context?.linkURL?.absoluteString)
    }

    @objc func copyEmailAddress(_: Any?) {
        guard let addresses = context?.mailtoAddresses, !addresses.isEmpty else {
            return
        }
        copyString(addresses.joined(separator: ", "))
    }

    // MARK: - Image actions

    @objc func openImageInNewTab(_: Any?) {
        guard let url = routableImageURL else { return }
        open(url, disposition: .newTab(selected: true))
    }

    @objc func openImageInNewWindow(_: Any?) {
        guard let url = routableImageURL else { return }
        open(url, disposition: .newWindow(selected: true))
    }

    @objc func copyImageAddress(_: Any?) {
        copyString(context?.imageURL?.absoluteString)
    }

    // MARK: - Derived state

    private var pageURL: URL? {
        guard let url = webView?.url ?? webView?.owningTab?.url,
              !url.absoluteString.isEmpty
        else { return nil }
        return url
    }

    private var selectedText: String? {
        context?.selectedText
    }

    private var routableLinkURL: URL? {
        guard let context, context.isWebSchemeLink else { return nil }
        return context.linkURL
    }

    private var routableImageURL: URL? {
        guard let context, context.isWebSchemeImage else { return nil }
        return context.imageURL
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

    // MARK: - Helpers

    private func open(_ url: URL, disposition: TabLinkDisposition) {
        guard let webView else { return }
        webView.owningTab?.linkPresentationCommands.open(
            url,
            from: webView,
            disposition: disposition
        )
    }

    private func copyString(_ string: String?) {
        guard let string else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func nonZeroPrintSize(for webView: WKWebView) -> CGSize {
        let boundsSize = webView.bounds.size
        if boundsSize.width > 0, boundsSize.height > 0 {
            return boundsSize
        }

        return CGSize(width: 800, height: 1_000)
    }
}
