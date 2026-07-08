import AppKit
import WebKit

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
        let recentTarget = webView.owningTab?.recentWebPageContextMenuTarget()
        preparedSelectedText = selectedText ?? recentTarget?.selectedText
        SumiWebPageMenuComposer(
            menu: menu,
            webView: webView,
            actionTarget: self,
            targetHint: targetHint,
            selectedText: selectedText
        ).compose()
        appendExtensionMenuItems(to: menu, for: webView)
        updateOwnedItemState(in: menu)

        if let tab = webView.owningTab,
           let appearance = tab.browserActionService.webPageMenuAppearance(
               tab,
               webView.window?.effectiveAppearance
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
            return webView.owningTab.map { $0.browserActionService.canBookmark($0) } ?? false
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
        case .openLinkInNewTab,
             .openLinkInNewWindow,
             .openImageInNewTab,
             .openImageInNewWindow,
             .openMediaInNewTab,
             .openMediaInNewWindow,
             .openFrameInNewWindow,
             .downloadLinkedFile,
             .downloadImage,
             .downloadMedia,
             .copyImageAddress:
            return SumiWebPageMenuNativeReference(menuItem)?.primaryItem.isEnabled ?? false
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
        webView?.owningTab?.activate()
        webView?.owningTab?.browserActionService.requestBookmarkEditorFromMenu()
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

    @objc func openNativeContextItemInNewTab(_ sender: NSMenuItem) {
        consumeNativeContextReference(from: sender) { [weak self] navigationAction in
            guard let url = navigationAction.request.url else { return }
            self?.openInNewTab(url)
        }
    }

    @objc func openNativeContextItemInNewWindow(_ sender: NSMenuItem) {
        consumeNativeContextReference(from: sender) { [weak self] navigationAction in
            guard let url = navigationAction.request.url else { return }
            self?.openInNewWindow(url)
        }
    }

    @objc func downloadNativeContextResource(_ sender: NSMenuItem) {
        guard canStartSumiDownload,
              let reference = SumiWebPageMenuNativeReference(sender),
              let requestItem = reference.requestItem
        else {
            replayNativeItem(from: sender)
            return
        }

        let isCapturingRequest = consumeNativeContextRequest(from: requestItem) { [weak self] navigationAction in
            self?.startDownload(using: navigationAction.request)
        }
        if !isCapturingRequest {
            replayNativeItem(from: sender)
        }
    }

    @objc func copyNativeImageAddress(_ sender: NSMenuItem) {
        consumeNativeContextReference(from: sender) { navigationAction in
            guard let url = navigationAction.request.url else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .string)
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
        let extensionItems = tab.normalWebViewExtensionRuntime
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

    private var canStartSumiDownload: Bool {
        webView?.owningTab?.browserActionService.canStartContextMenuDownload() ?? false
    }

    private func consumeNativeContextReference(
        from sender: NSMenuItem,
        perform handler: @escaping @MainActor (WKNavigationAction) -> Void
    ) {
        guard let originalItem = SumiWebPageMenuNativeReference(sender)?.primaryItem,
              consumeNativeContextRequest(from: originalItem, perform: handler)
        else {
            return
        }
    }

    @discardableResult
    private func consumeNativeContextRequest(
        from originalItem: NSMenuItem,
        perform handler: @escaping @MainActor (WKNavigationAction) -> Void
    ) -> Bool {
        guard let webView,
              let tab = webView.owningTab,
              let navigationAdapter = tab.navigationDelegateBundle(for: webView)
        else {
            return false
        }

        return navigationAdapter.consumeNativeContextMenuRequest(
            from: originalItem,
            perform: handler
        )
    }

    @discardableResult
    private func replayNativeItem(from sender: NSMenuItem) -> Bool {
        guard let item = SumiWebPageMenuNativeReference(sender)?.fallbackItem,
              let action = item.action
        else { return false }
        return NSApp.sendAction(action, to: item.target, from: item)
    }

    private func openInNewTab(_ url: URL) {
        if let tab = webView?.owningTab {
            tab.browserActionService.openURLInForegroundTab(url, tab)
        }
    }

    private func openInNewWindow(_ url: URL) {
        webView?.owningTab?.browserActionService.openURLsInNewWindow([url])
    }

    private func nonZeroPrintSize(for webView: WKWebView) -> CGSize {
        let boundsSize = webView.bounds.size
        if boundsSize.width > 0, boundsSize.height > 0 {
            return boundsSize
        }

        return CGSize(width: 800, height: 1_000)
    }

    private func startDownload(using request: URLRequest) {
        guard let webView,
              request.url != nil,
              let tab = webView.owningTab
        else { return }

        tab.browserActionService.startContextMenuDownload(webView, request)
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
