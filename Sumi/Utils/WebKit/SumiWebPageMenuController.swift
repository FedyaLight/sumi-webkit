import AppKit
import WebKit
import SwiftUI

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
        updateOwnedItemState(in: menu)

        if let tab = webView.owningTab,
           let browserManager = tab.browserManager,
           let windowState = browserManager.windowState(containing: tab),
           let settings = browserManager.sumiSettings {
            let globalScheme: ColorScheme = webView.window?.effectiveAppearance.name == .darkAqua ? .dark : .light
            let themeContext = windowState.resolvedThemeContext(global: globalScheme, settings: settings)
            let colorScheme = themeContext.nativeSurfaceColorScheme
            let appearance = NSAppearance.sumiChromeAppearance(for: colorScheme, fallback: webView.window?.effectiveAppearance)
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
            guard let tab = webView.owningTab,
                  let browserManager = tab.browserManager
            else { return false }
            return browserManager.bookmarkManager.canBookmark(tab)
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
        webView.goBack()
    }

    @objc func goForward(_: Any?) {
        guard let webView, webView.canGoForward else { return }
        webView.goForward()
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
        webView?.owningTab?.browserManager?.requestBookmarkEditorForActiveWindowFromMenu()
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

        components.fragment = ":~:text=\(text.sumiTextFragmentEncoded)"
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
        webView?.owningTab?.browserManager?.downloadManager != nil
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
              let popupHandling = tab.navigationDelegateBundle(for: webView)?.popupHandling
        else {
            return false
        }

        return popupHandling.consumeNativeContextMenuRequest(
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
        guard let tab = webView?.owningTab,
              let browserManager = tab.browserManager,
              let windowState = browserManager.windowState(containing: tab)
                ?? browserManager.windowRegistry?.activeWindow
        else { return }

        _ = browserManager.openNewTab(
            url: url.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: tab.spaceId
            )
        )
    }

    private func openInNewWindow(_ url: URL) {
        webView?.owningTab?.browserManager?.openURLsInNewWindow([url])
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
              let url = request.url,
              let downloadManager = webView.owningTab?.browserManager?.downloadManager
        else { return }

        let callback: @MainActor @Sendable (WKDownload) -> Void = { download in
            _ = downloadManager.addDownload(
                download,
                originalURL: url,
                suggestedFilename: DownloadFileUtilities.suggestedFilename(
                    response: nil,
                    requestURL: url,
                    fallback: "download"
                )
            )
        }
        webView.startDownload(using: request, completionHandler: callback)
    }
}

@MainActor
private struct SumiWebPageMenuComposer {
    let menu: NSMenu
    let webView: FocusableWKWebView
    let actionTarget: SumiWebPageMenuController
    let targetHint: SumiWebPageContextMenuTargetKind?
    let selectedText: String?

    func compose() {
        let targetSnapshot = webView.owningTab?.recentWebPageContextMenuTarget()
        let snapshot = SumiWebPageMenuSnapshot(menu: menu)
        let context = SumiWebPageMenuContext(
            menu: menu,
            targetHint: targetHint ?? targetSnapshot?.kind,
            selectedText: selectedText ?? targetSnapshot?.selectedText,
            searchProviderName: searchProviderName
        )
        removeOwnedPageItems()
        removeSuppressedWebKitItems(in: menu)
        removeContextuallyRedundantItems(for: context)
        decorateNativeInspectElement(using: snapshot)

        if context.isPageBackground {
            removeWebKitPageNavigation()
            insertPageBackgroundCommands()
        } else {
            replaceAmbiguousWebKitItems(using: snapshot, context: context)
        }

        insertSelectionFallbackCommands(ifNeededFor: context)
        decorateWebKitItems(in: menu)
        menu.sumiNormalizeSeparators()
    }

    private func removeOwnedPageItems() {
        for item in menu.items.reversed()
            where SumiWebPageMenuCommand(item.identifier)?.isPageBackgroundCommand == true
        {
            menu.removeItem(item)
        }
        menu.sumiNormalizeSeparators()
    }

    private func removeSuppressedWebKitItems(in menu: NSMenu) {
        for item in menu.items.reversed() {
            if let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
               identifier.isSuppressedBySumi
            {
                menu.removeItem(item)
                continue
            }

            if let submenu = item.submenu {
                removeSuppressedWebKitItems(in: submenu)
                submenu.sumiNormalizeSeparators()
            }
        }
    }

    private func removeWebKitPageNavigation() {
        for item in menu.items.reversed() {
            guard SumiWebKitMenuItemIdentifier(item.identifier)?.isPageNavigation == true
                    || item.sumiIsWebKitStopItem
            else { continue }
            menu.removeItem(item)
        }
        menu.sumiNormalizeSeparators()
    }

    private func removeContextuallyRedundantItems(for context: SumiWebPageMenuContext) {
        guard context.hasElementContext else { return }

        for item in menu.items.reversed() {
            guard let identifier = SumiWebKitMenuItemIdentifier(item.identifier) else {
                continue
            }

            let shouldRemove: Bool = switch identifier {
            case .openLink:
                true
            case .downloadLinkedFile:
                context.hasImageContext
            case .shareMenu:
                true
            case .lookUp:
                !item.isEnabled
            default:
                false
            }

            if shouldRemove {
                menu.removeItem(item)
            }
        }
        menu.sumiNormalizeSeparators()
    }

    private func replaceAmbiguousWebKitItems(
        using snapshot: SumiWebPageMenuSnapshot,
        context: SumiWebPageMenuContext
    ) {
        for (index, item) in menu.items.enumerated().reversed() {
            guard let identifier = SumiWebKitMenuItemIdentifier(item.identifier) else {
                continue
            }

            switch identifier {
            case .openLinkInNewWindow:
                replaceOpenItem(
                    at: index,
                    originalItem: item,
                    newTabTitle: "Open Link in New Tab",
                    tabCommand: .openLinkInNewTab,
                    windowCommand: .openLinkInNewWindow,
                    symbolName: "link"
                )
            case .openImageInNewWindow:
                replaceOpenItem(
                    at: index,
                    originalItem: item,
                    newTabTitle: "Open Image in New Tab",
                    tabCommand: .openImageInNewTab,
                    windowCommand: context.hasLinkContext ? nil : .openImageInNewWindow,
                    symbolName: "photo"
                )
                menu.insertItem(
                    makeNativeItem(
                        title: "Copy Image Address",
                        command: .copyImageAddress,
                        action: #selector(SumiWebPageMenuController.copyNativeImageAddress(_:)),
                        symbolName: "link",
                        primaryItem: item
                    ),
                    at: context.hasLinkContext ? index + 1 : index + 2
                )
            case .openMediaInNewWindow:
                replaceOpenItem(
                    at: index,
                    originalItem: item,
                    newTabTitle: item.title.sumiReplacingNewWindowWithNewTab(
                        fallback: "Open Media in New Tab"
                    ),
                    tabCommand: .openMediaInNewTab,
                    windowCommand: context.hasLinkContext ? nil : .openMediaInNewWindow,
                    symbolName: "play.rectangle"
                )
            case .openFrameInNewWindow:
                menu.removeItem(at: index)
                menu.insertItem(
                    makeNativeItem(
                        title: item.title,
                        command: .openFrameInNewWindow,
                        action: #selector(SumiWebPageMenuController.openNativeContextItemInNewWindow(_:)),
                        symbolName: "macwindow",
                        primaryItem: item
                    ),
                    at: index
                )
            case .downloadLinkedFile:
                replaceDownloadItem(
                    at: index,
                    originalItem: item,
                    command: .downloadLinkedFile,
                    requestItem: snapshot.item(for: .openLinkInNewWindow),
                    symbolName: "arrow.down.circle"
                )
            case .downloadImage:
                replaceDownloadItem(
                    at: index,
                    originalItem: item,
                    command: .downloadImage,
                    requestItem: snapshot.item(for: .openImageInNewWindow),
                    symbolName: "arrow.down.circle"
                )
            case .downloadMedia:
                replaceDownloadItem(
                    at: index,
                    originalItem: item,
                    command: .downloadMedia,
                    requestItem: snapshot.item(for: .openMediaInNewWindow),
                    symbolName: "arrow.down.circle"
                )
            default:
                continue
            }
        }
    }

    private func decorateNativeInspectElement(using snapshot: SumiWebPageMenuSnapshot) {
        guard let nativeInspectItem = snapshot.item(for: .inspectElement),
              menu.items.contains(where: { $0 === nativeInspectItem })
        else {
            return
        }

        nativeInspectItem.title = "Inspect Element"
        nativeInspectItem.image = SumiWebPageMenuIcon.make("hammer", title: nativeInspectItem.title)
    }

    private func replaceOpenItem(
        at index: Int,
        originalItem: NSMenuItem,
        newTabTitle: String,
        tabCommand: SumiWebPageMenuCommand,
        windowCommand: SumiWebPageMenuCommand?,
        symbolName: String
    ) {
        menu.removeItem(at: index)
        menu.insertItem(
            makeNativeItem(
                title: newTabTitle,
                command: tabCommand,
                action: #selector(SumiWebPageMenuController.openNativeContextItemInNewTab(_:)),
                symbolName: symbolName,
                primaryItem: originalItem
            ),
            at: index
        )
        guard let windowCommand else { return }
        menu.insertItem(
            makeNativeItem(
                title: originalItem.title,
                command: windowCommand,
                action: #selector(SumiWebPageMenuController.openNativeContextItemInNewWindow(_:)),
                symbolName: "macwindow",
                primaryItem: originalItem
            ),
            at: index + 1
        )
    }

    private func replaceDownloadItem(
        at index: Int,
        originalItem: NSMenuItem,
        command: SumiWebPageMenuCommand,
        requestItem: NSMenuItem?,
        symbolName: String
    ) {
        menu.removeItem(at: index)
        menu.insertItem(
            makeNativeItem(
                title: originalItem.title,
                command: command,
                action: #selector(SumiWebPageMenuController.downloadNativeContextResource(_:)),
                symbolName: symbolName,
                primaryItem: originalItem,
                requestItem: requestItem,
                fallbackItem: originalItem
            ),
            at: index
        )
    }

    private func insertSelectionFallbackCommands(ifNeededFor context: SumiWebPageMenuContext) {
        guard let selectedText = context.selectedText else { return }

        var items: [NSMenuItem] = []
        if !context.identifiers.contains(.copy) {
            items.append(makeItem(
                title: "Copy",
                command: .copySelection,
                action: #selector(SumiWebPageMenuController.copySelection(_:)),
                symbolName: "doc.on.doc"
            ))
        }
        if context.canCopyLinkToSelectedText,
           !context.identifiers.contains(.copyLinkWithHighlight)
        {
            items.append(makeItem(
                title: "Copy Link to Selected Text",
                command: .copyLinkToSelectedText,
                action: #selector(SumiWebPageMenuController.copyLinkToSelectedText(_:)),
                symbolName: "quote.bubble"
            ))
        }
        if !context.identifiers.contains(.searchWeb) {
            items.append(makeItem(
                title: "Search \(context.searchProviderName) for \"\(selectedText.sumiMenuSnippet)\"",
                command: .searchSelection,
                action: #selector(SumiWebPageMenuController.searchSelection(_:)),
                symbolName: "magnifyingglass"
            ))
        }

        if !context.hasPrintCommand(in: menu) {
            items.append(makeItem(
                title: "Print Page...",
                command: .printPage,
                action: #selector(SumiWebPageMenuController.printPage(_:)),
                symbolName: "printer"
            ))
        }

        guard !items.isEmpty else { return }
        var insertionIndex = context.selectionFallbackInsertionIndex(in: menu)
        if insertionIndex > 0, menu.items[insertionIndex - 1].isSeparatorItem == false {
            menu.insertItem(.separator(), at: insertionIndex)
            insertionIndex += 1
        }
        for item in items {
            menu.insertItem(item, at: insertionIndex)
            insertionIndex += 1
        }
        if insertionIndex < menu.items.count, menu.items[insertionIndex].isSeparatorItem == false {
            menu.insertItem(.separator(), at: insertionIndex)
        }
    }

    private func insertPageBackgroundCommands() {
        let navigationItems = [
            makeItem(
                title: "Back",
                command: .back,
                action: #selector(SumiWebPageMenuController.goBack(_:)),
                symbolName: "chevron.left"
            ),
            makeItem(
                title: "Forward",
                command: .forward,
                action: #selector(SumiWebPageMenuController.goForward(_:)),
                symbolName: "chevron.right"
            ),
            loadingItem(),
        ]

        let pageItems = [
            makeItem(
                title: "Bookmark This Page...",
                command: .bookmarkPage,
                action: #selector(SumiWebPageMenuController.bookmarkPage(_:)),
                symbolName: "bookmark"
            ),
            makeItem(
                title: "Copy Page Address",
                command: .copyPageAddress,
                action: #selector(SumiWebPageMenuController.copyPageAddress(_:)),
                symbolName: "link"
            ),
            makeItem(
                title: "Print Page...",
                command: .printPage,
                action: #selector(SumiWebPageMenuController.printPage(_:)),
                symbolName: "printer"
            ),
        ]

        var insertionIndex = 0
        for item in navigationItems {
            menu.insertItem(item, at: insertionIndex)
            insertionIndex += 1
        }
        menu.insertItem(.separator(), at: insertionIndex)
        insertionIndex += 1
        for item in pageItems {
            menu.insertItem(item, at: insertionIndex)
            insertionIndex += 1
        }
        if insertionIndex < menu.items.count {
            menu.insertItem(.separator(), at: insertionIndex)
        }
    }

    private func loadingItem() -> NSMenuItem {
        if webView.isLoading {
            return makeItem(
                title: "Stop Loading",
                command: .stop,
                action: #selector(SumiWebPageMenuController.stopLoading(_:)),
                symbolName: "xmark"
            )
        }

        return makeItem(
            title: "Reload Page",
            command: .reload,
            action: #selector(SumiWebPageMenuController.reloadPage(_:)),
            symbolName: "arrow.clockwise"
        )
    }

    private var searchProviderName: String {
        guard let settings = webView.owningTab?.sumiSettings else {
            return SearchProvider.duckDuckGo.displayName
        }
        return settings.resolvedSearchEngineDisplayName
    }

    private func decorateWebKitItems(in menu: NSMenu) {
        for item in menu.items {
            if let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
               item.image == nil,
               let symbolName = identifier.symbolName
            {
                item.image = SumiWebPageMenuIcon.make(symbolName, title: item.title)
            }

            if let submenu = item.submenu {
                decorateWebKitItems(in: submenu)
            }
        }
    }

    private func makeItem(
        title: String,
        command: SumiWebPageMenuCommand,
        action: Selector,
        symbolName: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = actionTarget
        item.identifier = command.itemIdentifier
        item.image = SumiWebPageMenuIcon.make(symbolName, title: title)
        return item
    }

    private func makeNativeItem(
        title: String,
        command: SumiWebPageMenuCommand,
        action: Selector,
        symbolName: String,
        primaryItem: NSMenuItem,
        requestItem: NSMenuItem? = nil,
        fallbackItem: NSMenuItem? = nil
    ) -> NSMenuItem {
        let item = makeItem(
            title: title,
            command: command,
            action: action,
            symbolName: symbolName
        )
        item.isEnabled = primaryItem.isEnabled
        item.representedObject = SumiWebPageMenuNativeReference(
            primaryItem: primaryItem,
            requestItem: requestItem,
            fallbackItem: fallbackItem ?? primaryItem
        )
        return item
    }
}

private struct SumiWebPageMenuSnapshot {
    private let webKitItems: [SumiWebKitMenuItemIdentifier: NSMenuItem]

    init(menu: NSMenu) {
        webKitItems = menu.items.reduce(into: [:]) { items, item in
            guard let identifier = SumiWebKitMenuItemIdentifier(item.identifier) else {
                return
            }
            items[identifier] = item
        }
    }

    func item(for identifier: SumiWebKitMenuItemIdentifier) -> NSMenuItem? {
        webKitItems[identifier]
    }
}

private final class SumiWebPageMenuNativeReference: NSObject {
    let primaryItem: NSMenuItem
    let requestItem: NSMenuItem?
    let fallbackItem: NSMenuItem

    init(primaryItem: NSMenuItem, requestItem: NSMenuItem?, fallbackItem: NSMenuItem) {
        self.primaryItem = primaryItem
        self.requestItem = requestItem
        self.fallbackItem = fallbackItem
    }

    convenience init?(_ item: NSMenuItem) {
        guard let reference = item.representedObject as? SumiWebPageMenuNativeReference else {
            return nil
        }
        self.init(
            primaryItem: reference.primaryItem,
            requestItem: reference.requestItem,
            fallbackItem: reference.fallbackItem
        )
    }
}

private struct SumiWebPageMenuContext {
    let identifiers: Set<SumiWebKitMenuItemIdentifier>
    let hasOwnedPageCommands: Bool
    let hasOwnedElementCommands: Bool
    let targetHint: SumiWebPageContextMenuTargetKind?
    let selectedText: String?
    let hasLinkContext: Bool
    let hasImageContext: Bool
    let hasMediaContext: Bool
    let searchProviderName: String

    init(
        menu: NSMenu,
        targetHint: SumiWebPageContextMenuTargetKind?,
        selectedText: String?,
        searchProviderName: String
    ) {
        identifiers = Set(menu.items.compactMap {
            SumiWebKitMenuItemIdentifier($0.identifier)
        })
        self.targetHint = targetHint
        self.selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        hasOwnedPageCommands = menu.items.contains {
            SumiWebPageMenuCommand($0.identifier)?.isPageBackgroundCommand == true
        }
        hasOwnedElementCommands = menu.items.contains {
            SumiWebPageMenuCommand($0.identifier)?.belongsToElementContext == true
        }
        hasLinkContext = identifiers.contains(where: \.belongsToLinkContext)
        hasImageContext = identifiers.contains(where: \.belongsToImageContext)
        hasMediaContext = identifiers.contains(where: \.belongsToMediaContext)
        self.searchProviderName = searchProviderName
    }

    var hasElementContext: Bool {
        hasOwnedElementCommands
            || identifiers.contains(where: \.belongsToElementContext)
            || targetHint?.isWebPageElement == true
            || selectedText != nil
    }

    var isPageBackground: Bool {
        if targetHint == .interactiveElement || targetHint == .editable {
            return false
        }
        if selectedText != nil {
            return false
        }

        return hasOwnedPageCommands
            || (
                !hasOwnedElementCommands
                && identifiers.contains(where: \.isPageBackgroundSignal)
                && !identifiers.contains(where: \.belongsToElementContext)
            )
    }

    var canCopyLinkToSelectedText: Bool {
        targetHint != .editable
    }

    func selectionFallbackInsertionIndex(in menu: NSMenu) -> Int {
        let elementIdentifiers = Set(identifiers.filter(\.belongsToElementContext))
        guard !elementIdentifiers.isEmpty else { return 0 }

        var lastElementIndex = -1
        for (index, item) in menu.items.enumerated() {
            if let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
               identifier.belongsToElementContext
            {
                lastElementIndex = index
            }
            if SumiWebPageMenuCommand(item.identifier)?.belongsToElementContext == true {
                lastElementIndex = index
            }
        }
        return lastElementIndex >= 0 ? lastElementIndex + 1 : 0
    }

    func hasPrintCommand(in menu: NSMenu) -> Bool {
        menu.items.contains {
            SumiWebPageMenuCommand($0.identifier) == .printPage
                || $0.title.localizedCaseInsensitiveContains("Print")
                || $0.title.localizedCaseInsensitiveContains("Печать")
        }
    }
}

private extension SumiWebPageContextMenuTargetKind {
    var isWebPageElement: Bool {
        switch self {
        case .editable, .interactiveElement, .link, .image, .media:
            return true
        case .page, .otherElement:
            return false
        }
    }
}

private extension Tab {
    func recentWebPageContextMenuTarget() -> SumiWebPageContextMenuTargetSnapshot? {
        guard let lastWebPageContextMenuTarget,
              lastWebPageContextMenuTarget.isRecent()
        else { return nil }
        return lastWebPageContextMenuTarget
    }
}

enum SumiWebPageMenuCommand: String, CaseIterable {
    case back = "SumiWebPageMenu.Back"
    case forward = "SumiWebPageMenu.Forward"
    case reload = "SumiWebPageMenu.Reload"
    case stop = "SumiWebPageMenu.Stop"
    case bookmarkPage = "SumiWebPageMenu.BookmarkPage"
    case copyPageAddress = "SumiWebPageMenu.CopyPageAddress"
    case printPage = "SumiWebPageMenu.PrintPage"
    case copySelection = "SumiWebPageMenu.CopySelection"
    case copyLinkToSelectedText = "SumiWebPageMenu.CopyLinkToSelectedText"
    case searchSelection = "SumiWebPageMenu.SearchSelection"
    case openLinkInNewTab = "SumiWebPageMenu.OpenLinkInNewTab"
    case openLinkInNewWindow = "SumiWebPageMenu.OpenLinkInNewWindow"
    case openImageInNewTab = "SumiWebPageMenu.OpenImageInNewTab"
    case openImageInNewWindow = "SumiWebPageMenu.OpenImageInNewWindow"
    case openMediaInNewTab = "SumiWebPageMenu.OpenMediaInNewTab"
    case openMediaInNewWindow = "SumiWebPageMenu.OpenMediaInNewWindow"
    case openFrameInNewWindow = "SumiWebPageMenu.OpenFrameInNewWindow"
    case downloadLinkedFile = "SumiWebPageMenu.DownloadLinkedFile"
    case downloadImage = "SumiWebPageMenu.DownloadImage"
    case downloadMedia = "SumiWebPageMenu.DownloadMedia"
    case copyImageAddress = "SumiWebPageMenu.CopyImageAddress"

    init?(_ identifier: NSUserInterfaceItemIdentifier?) {
        guard let identifier else { return nil }
        self.init(rawValue: identifier.rawValue)
    }

    var itemIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }

    var isPageBackgroundCommand: Bool {
        switch self {
        case .back,
             .forward,
             .reload,
             .stop,
             .bookmarkPage,
             .copyPageAddress,
             .printPage:
            return true
        default:
            return false
        }
    }

    var belongsToElementContext: Bool {
        switch self {
        case .copySelection, .copyLinkToSelectedText, .searchSelection:
            return true
        default:
            return !isPageBackgroundCommand
        }
    }
}

enum SumiWebKitMenuItemIdentifier: String, CaseIterable {
    case addHighlightToCurrentQuickNote = "WKMenuItemIdentifierAddHighlightToCurrentQuickNote"
    case addHighlightToNewQuickNote = "WKMenuItemIdentifierAddHighlightToNewQuickNote"
    case checkGrammarWithSpelling = "WKMenuItemIdentifierCheckGrammarWithSpelling"
    case checkSpelling = "WKMenuItemIdentifierCheckSpelling"
    case checkSpellingWhileTyping = "WKMenuItemIdentifierCheckSpellingWhileTyping"
    case copy = "WKMenuItemIdentifierCopy"
    case copyImage = "WKMenuItemIdentifierCopyImage"
    case copyLink = "WKMenuItemIdentifierCopyLink"
    case copyLinkWithHighlight = "WKMenuItemIdentifierCopyLinkWithHighlight"
    case copyMediaLink = "WKMenuItemIdentifierCopyMediaLink"
    case copySubject = "WKMenuItemIdentifierCopySubject"
    case downloadImage = "WKMenuItemIdentifierDownloadImage"
    case downloadLinkedFile = "WKMenuItemIdentifierDownloadLinkedFile"
    case downloadMedia = "WKMenuItemIdentifierDownloadMedia"
    case goBack = "WKMenuItemIdentifierGoBack"
    case goForward = "WKMenuItemIdentifierGoForward"
    case inspectElement = "WKMenuItemIdentifierInspectElement"
    case lookUp = "WKMenuItemIdentifierLookUp"
    case openFrameInNewWindow = "WKMenuItemIdentifierOpenFrameInNewWindow"
    case openImageInNewWindow = "WKMenuItemIdentifierOpenImageInNewWindow"
    case openLink = "WKMenuItemIdentifierOpenLink"
    case openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
    case openMediaInNewWindow = "WKMenuItemIdentifierOpenMediaInNewWindow"
    case paste = "WKMenuItemIdentifierPaste"
    case pauseAllAnimations = "WKMenuItemIdentifierPauseAllAnimations"
    case pauseAnimation = "WKMenuItemIdentifierPauseAnimation"
    case playAllAnimations = "WKMenuItemIdentifierPlayAllAnimations"
    case playAnimation = "WKMenuItemIdentifierPlayAnimation"
    case proofread = "WKMenuItemIdentifierProofread"
    case reload = "WKMenuItemIdentifierReload"
    case revealImage = "WKMenuItemIdentifierRevealImage"
    case rewrite = "WKMenuItemIdentifierRewrite"
    case searchWeb = "WKMenuItemIdentifierSearchWeb"
    case shareMenu = "WKMenuItemIdentifierShareMenu"
    case showHideMediaControls = "WKMenuItemIdentifierShowHideMediaControls"
    case showHideMediaStats = "WKMenuItemIdentifierShowHideMediaStats"
    case showSpellingPanel = "WKMenuItemIdentifierShowSpellingPanel"
    case speechMenu = "WKMenuItemIdentifierSpeechMenu"
    case spellingMenu = "WKMenuItemIdentifierSpellingMenu"
    case summarize = "WKMenuItemIdentifierSummarize"
    case toggleEnhancedFullScreen = "WKMenuItemIdentifierToggleEnhancedFullScreen"
    case toggleFullScreen = "WKMenuItemIdentifierToggleFullScreen"
    case togglePictureInPicture = "WKMenuItemIdentifierTogglePictureInPicture"
    case toggleVideoViewer = "WKMenuItemIdentifierToggleVideoViewer"
    case translate = "WKMenuItemIdentifierTranslate"
    case writingTools = "WKMenuItemIdentifierWritingTools"

    init?(_ identifier: NSUserInterfaceItemIdentifier?) {
        guard let identifier else { return nil }
        self.init(rawValue: identifier.rawValue)
    }

    var isPageNavigation: Bool {
        switch self {
        case .goBack, .goForward, .reload:
            return true
        default:
            return false
        }
    }

    var isPageBackgroundSignal: Bool {
        switch self {
        case .goBack, .goForward, .inspectElement, .reload, .shareMenu:
            return true
        default:
            return false
        }
    }

    var belongsToLinkContext: Bool {
        switch self {
        case .copyLink,
             .copyLinkWithHighlight,
             .downloadLinkedFile,
             .openLink,
             .openLinkInNewWindow:
            return true
        default:
            return false
        }
    }

    var belongsToImageContext: Bool {
        switch self {
        case .copyImage,
             .copySubject,
             .downloadImage,
             .openImageInNewWindow,
             .revealImage:
            return true
        default:
            return false
        }
    }

    var belongsToMediaContext: Bool {
        switch self {
        case .copyMediaLink,
             .downloadMedia,
             .openMediaInNewWindow,
             .showHideMediaControls,
             .showHideMediaStats,
             .toggleEnhancedFullScreen,
             .toggleFullScreen,
             .togglePictureInPicture,
             .toggleVideoViewer:
            return true
        default:
            return false
        }
    }

    var belongsToElementContext: Bool {
        switch self {
        case .addHighlightToCurrentQuickNote,
             .addHighlightToNewQuickNote,
             .checkGrammarWithSpelling,
             .checkSpelling,
             .checkSpellingWhileTyping,
             .copy,
             .copyImage,
             .copyLink,
             .copyLinkWithHighlight,
             .copyMediaLink,
             .copySubject,
             .downloadImage,
             .downloadLinkedFile,
             .downloadMedia,
             .lookUp,
             .openFrameInNewWindow,
             .openImageInNewWindow,
             .openLink,
             .openLinkInNewWindow,
             .openMediaInNewWindow,
             .paste,
             .pauseAllAnimations,
             .pauseAnimation,
             .playAllAnimations,
             .playAnimation,
             .proofread,
             .revealImage,
             .rewrite,
             .searchWeb,
             .showHideMediaControls,
             .showHideMediaStats,
             .showSpellingPanel,
             .speechMenu,
             .spellingMenu,
             .summarize,
             .toggleEnhancedFullScreen,
             .toggleFullScreen,
             .togglePictureInPicture,
             .toggleVideoViewer,
             .translate,
             .writingTools:
            return true
        case .goBack, .goForward, .inspectElement, .reload, .shareMenu:
            return false
        }
    }

    var isSuppressedBySumi: Bool {
        switch self {
        case .checkGrammarWithSpelling,
             .checkSpelling,
             .checkSpellingWhileTyping,
             .showSpellingPanel,
             .spellingMenu:
            return true
        default:
            return false
        }
    }

    var symbolName: String? {
        switch self {
        case .addHighlightToCurrentQuickNote, .addHighlightToNewQuickNote:
            return "note.text"
        case .checkGrammarWithSpelling,
             .checkSpelling,
             .checkSpellingWhileTyping,
             .showSpellingPanel,
             .spellingMenu:
            return "textformat.abc"
        case .copy, .copyImage, .copySubject:
            return "doc.on.doc"
        case .copyLink, .copyLinkWithHighlight, .copyMediaLink:
            return "link"
        case .downloadImage, .downloadLinkedFile, .downloadMedia:
            return "arrow.down.circle"
        case .goBack:
            return "chevron.left"
        case .goForward:
            return "chevron.right"
        case .inspectElement:
            return "hammer"
        case .lookUp:
            return "book.closed"
        case .openFrameInNewWindow,
             .openImageInNewWindow,
             .openLink,
             .openLinkInNewWindow,
             .openMediaInNewWindow:
            return "arrow.up.right.square"
        case .paste:
            return "clipboard"
        case .pauseAllAnimations, .pauseAnimation:
            return "pause.circle"
        case .playAllAnimations, .playAnimation:
            return "play.circle"
        case .proofread:
            return "checkmark.bubble"
        case .reload:
            return "arrow.clockwise"
        case .revealImage:
            return "viewfinder"
        case .rewrite:
            return "pencil.and.scribble"
        case .searchWeb:
            return "magnifyingglass"
        case .shareMenu:
            return "square.and.arrow.up"
        case .showHideMediaControls:
            return "play.rectangle"
        case .showHideMediaStats:
            return "chart.bar"
        case .speechMenu:
            return "waveform"
        case .summarize:
            return "text.redaction"
        case .toggleEnhancedFullScreen, .toggleFullScreen:
            return "arrow.up.left.and.arrow.down.right"
        case .togglePictureInPicture:
            return "pip"
        case .toggleVideoViewer:
            return "rectangle.inset.filled"
        case .translate:
            return "character.book.closed"
        case .writingTools:
            return "wand.and.stars"
        }
    }
}

private enum SumiWebPageMenuIcon {
    static func make(_ symbolName: String, title: String) -> NSImage? {
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        ) else {
            return nil
        }

        return image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        )
    }
}

private extension NSMenuItem {
    // WKMenuTarget keeps the legacy WebKit context action tag on action items.
    var sumiIsWebKitStopItem: Bool {
        identifier == nil && tag == 11
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var sumiMenuSnippet: String {
        let normalized = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        guard normalized.count > 40 else { return normalized }
        return "\(normalized.prefix(40))..."
    }

    var sumiTextFragmentEncoded: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    func sumiReplacingNewWindowWithNewTab(fallback: String) -> String {
        guard contains("New Window") else { return fallback }
        return replacingOccurrences(of: "New Window", with: "New Tab")
    }
}

@MainActor
private extension NSMenu {
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
