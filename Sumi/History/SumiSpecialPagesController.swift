import AppKit
import Foundation
import WebKit

final class SumiSpecialPagesController: NSObject, WKURLSchemeHandler, WKScriptMessageHandlerWithReply {
    static let shared = SumiSpecialPagesController()

    weak var browserManager: BrowserManager?

    private let historyWebViews = NSHashTable<WKWebView>.weakObjects()
    private let actionsHandler = SumiHistoryViewActionsHandler()
    private lazy var historyAssetRootURL: URL? = locateHistoryAssetRoot()

    private override init() {
        super.init()
    }

    func prepare(_ userContentController: WKUserContentController) {
        userContentController.removeScriptMessageHandler(forName: "specialPages")
        userContentController.addScriptMessageHandler(
            self,
            contentWorld: .page,
            name: "specialPages"
        )
    }

    func registerHistoryWebView(_ webView: WKWebView) {
        guard historyWebViews.allObjects.contains(where: { $0 === webView }) == false else {
            return
        }
        historyWebViews.add(webView)
        pushThemeUpdate(to: webView)
    }

    func unregisterWebView(_ webView: WKWebView) {
        historyWebViews.remove(webView)
    }

    func historyDidChange() {
        for webView in historyWebViews.allObjects {
            guard let currentURL = webView.url, SumiSurface.isHistorySurfaceURL(currentURL) else {
                continue
            }
            webView.reload()
        }
    }

    func notifyThemeChanged() {
        for webView in historyWebViews.allObjects {
            pushThemeUpdate(to: webView)
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            return
        }

        if requestURL.host?.lowercased() == SumiSurface.historyURLHost {
            registerHistoryWebView(webView)
            serveHistoryAsset(for: requestURL, urlSchemeTask: urlSchemeTask)
            return
        }

        if requestURL.host?.lowercased() == SumiHistoryFaviconURL.host {
            serveFavicon(for: requestURL, urlSchemeTask: urlSchemeTask)
            return
        }

        serveEmptyHTML(for: requestURL, urlSchemeTask: urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        _ = webView
        _ = urlSchemeTask
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        _ = userContentController

        guard let payload = SpecialPagesMessage(message.body) else {
            replyHandler(Self.jsonString(for: EmptyPayload()), nil)
            return
        }

        guard payload.context == "specialPages", payload.featureName == SumiSurface.historyURLHost else {
            replyHandler(Self.jsonString(for: EmptyPayload()), nil)
            return
        }

        registerHistoryWebViewIfNeeded(for: message.webView)

        Task { @MainActor [weak self] in
            guard let self else {
                replyHandler(Self.jsonString(for: EmptyPayload()), nil)
                return
            }

            do {
                let result = try await self.handleHistoryMessage(payload, webView: message.webView)
                replyHandler(result, nil)
            } catch {
                let response = self.errorResponse(
                    id: payload.id,
                    message: error.localizedDescription
                )
                replyHandler(Self.jsonString(for: response), nil)
            }
        }
    }

    private func handleHistoryMessage(
        _ payload: SpecialPagesMessage,
        webView: WKWebView?
    ) async throws -> String {
        guard let historyManager = browserManager?.historyManager else {
            return Self.jsonString(for: EmptyPayload())
        }

        switch payload.method {
        case "initialSetup":
            await historyManager.refresh()
            let result = DataModel.Configuration(
                env: "production",
                locale: Bundle.main.preferredLocalizations.first ?? "en",
                platform: .init(name: "macos"),
                theme: currentThemeName,
                themeVariant: "sumi"
            )
            return responseString(id: payload.id, result: result)
        case "getRanges":
            let result = DataModel.GetRangesResponse(ranges: historyManager.ranges())
            return responseString(id: payload.id, result: result)
        case "query":
            guard let query = decode(DataModel.HistoryQuery.self, from: payload.params) else {
                throw SpecialPagesError.invalidParameters
            }
            let batch = await historyManager.dataProvider.visitsBatch(
                for: query.query,
                source: query.source,
                limit: query.limit,
                offset: query.offset
            )
            let result = DataModel.HistoryQueryResponse(
                info: .init(finished: batch.finished, query: query.query),
                value: batch.visits
            )
            return responseString(id: payload.id, result: result)
        case "deleteDomain":
            guard let request = decode(DataModel.DeleteDomainRequest.self, from: payload.params) else {
                throw SpecialPagesError.invalidParameters
            }
            let action = await actionsHandler.showDeleteDialog(
                for: .domainFilter([request.domain]),
                in: webView?.window,
                browserManager: browserManager
            )
            return responseString(id: payload.id, result: DataModel.DeleteRangeResponse(action: action))
        case "deleteRange":
            guard let request = decode(DataModel.DeleteRangeRequest.self, from: payload.params) else {
                throw SpecialPagesError.invalidParameters
            }
            let action = await actionsHandler.showDeleteDialog(
                for: .rangeFilter(request.range),
                in: webView?.window,
                browserManager: browserManager
            )
            return responseString(id: payload.id, result: DataModel.DeleteRangeResponse(action: action))
        case "deleteTerm":
            guard let request = decode(DataModel.DeleteTermRequest.self, from: payload.params) else {
                throw SpecialPagesError.invalidParameters
            }
            let action = await actionsHandler.showDeleteDialog(
                for: .searchTerm(request.term),
                in: webView?.window,
                browserManager: browserManager
            )
            return responseString(id: payload.id, result: DataModel.DeleteRangeResponse(action: action))
        case "entries_menu":
            guard let request = decode(DataModel.EntriesMenuRequest.self, from: payload.params) else {
                throw SpecialPagesError.invalidParameters
            }
            let action = await actionsHandler.showContextMenu(
                for: request.ids,
                in: webView?.window,
                browserManager: browserManager
            )
            return responseString(id: payload.id, result: DataModel.DeleteRangeResponse(action: action))
        case "entries_delete":
            guard let request = decode(DataModel.EntriesMenuRequest.self, from: payload.params) else {
                throw SpecialPagesError.invalidParameters
            }
            let action = await actionsHandler.showDeleteDialog(
                forEntries: request.ids,
                in: webView?.window,
                browserManager: browserManager
            )
            return responseString(id: payload.id, result: DataModel.DeleteRangeResponse(action: action))
        case "open":
            guard let action = decode(DataModel.HistoryOpenAction.self, from: payload.params),
                  let url = URL(string: action.url)
            else {
                throw SpecialPagesError.invalidParameters
            }
            await actionsHandler.open(url, window: webView?.window, browserManager: browserManager)
            return responseString(id: payload.id, result: EmptyPayload())
        case "reportInitException", "reportPageException":
            if let exception = decode(DataModel.Exception.self, from: payload.params) {
                RuntimeDiagnostics.emit("History special page exception: \(exception.message)")
            }
            return responseString(id: payload.id, result: EmptyPayload())
        default:
            throw SpecialPagesError.unsupportedMethod(payload.method)
        }
    }

    private func registerHistoryWebViewIfNeeded(for webView: WKWebView?) {
        guard let webView,
              let url = webView.url,
              SumiSurface.isHistorySurfaceURL(url)
        else {
            return
        }
        registerHistoryWebView(webView)
    }

    private func serveHistoryAsset(
        for requestURL: URL,
        urlSchemeTask: WKURLSchemeTask
    ) {
        guard let assetRoot = historyAssetRootURL else {
            serveMissingResource(for: requestURL, urlSchemeTask: urlSchemeTask)
            return
        }

        let relativePath = requestURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetURL: URL
        if relativePath.isEmpty {
            targetURL = assetRoot.appendingPathComponent("index.html")
        } else {
            targetURL = assetRoot.appendingPathComponent(relativePath)
        }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            serveMissingResource(for: requestURL, urlSchemeTask: urlSchemeTask)
            return
        }

        do {
            let data: Data
            if targetURL.pathExtension.lowercased() == "html" {
                let html = try String(contentsOf: targetURL, encoding: .utf8)
                    .replacingOccurrences(of: "$LOADING_COLOR$", with: loadingColorHex)
                data = Data(html.utf8)
            } else {
                data = try Data(contentsOf: targetURL)
            }

            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType(for: targetURL),
                expectedContentLength: data.count,
                textEncodingName: textEncodingName(for: targetURL)
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            serveMissingResource(for: requestURL, urlSchemeTask: urlSchemeTask)
        }
    }

    private func serveFavicon(
        for requestURL: URL,
        urlSchemeTask: WKURLSchemeTask
    ) {
        guard let faviconURL = SumiHistoryFaviconURL.decode(from: requestURL) else {
            serveMissingResource(for: requestURL, urlSchemeTask: urlSchemeTask)
            return
        }

        Task { @MainActor in
            let image = await SumiFaviconResolver.shared.image(for: faviconURL)
            guard let image,
                  let pngData = image.pngData()
            else {
                self.serveMissingResource(for: requestURL, urlSchemeTask: urlSchemeTask)
                return
            }

            let response = URLResponse(
                url: requestURL,
                mimeType: "image/png",
                expectedContentLength: pngData.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(pngData)
            urlSchemeTask.didFinish()
        }
    }

    private func serveEmptyHTML(
        for requestURL: URL,
        urlSchemeTask: WKURLSchemeTask
    ) {
        let html = """
        <html>
          <head>
            <style>
              body {
                background: \(loadingColorHex);
                display: flex;
                height: 100vh;
              }
            </style>
          </head>
          <body></body>
        </html>
        """
        let data = Data(html.utf8)
        let response = URLResponse(
            url: requestURL,
            mimeType: "text/html",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    private func serveMissingResource(
        for requestURL: URL,
        urlSchemeTask: WKURLSchemeTask
    ) {
        guard let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 404,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ) else {
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data())
        urlSchemeTask.didFinish()
    }

    private func pushThemeUpdate(to webView: WKWebView) {
        let payload = SubscriptionPayload(
            context: "specialPages",
            featureName: SumiSurface.historyURLHost,
            subscriptionName: "onThemeUpdate",
            params: DataModel.ThemeUpdate(theme: currentThemeName, themeVariant: "sumi")
        )

        guard let json = try? encodeJSONString(payload) else {
            return
        }
        let script = """
        if (navigator.duckduckgo?.messageHandlers?.onThemeUpdate) {
            navigator.duckduckgo.messageHandlers.onThemeUpdate(\(json));
        }
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private var currentThemeName: String {
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return appearance == .darkAqua ? "dark" : "light"
    }

    private var loadingColorHex: String {
        currentThemeName == "dark" ? "#333333" : "#fafafa"
    }

    private func responseString<Result: Encodable>(
        id: String?,
        result: Result
    ) -> String {
        if let id {
            return Self.jsonString(for: SuccessPayload(id: id, result: result))
        }
        return Self.jsonString(for: result)
    }

    private func errorResponse(id: String?, message: String) -> some Encodable {
        ErrorPayload(id: id ?? UUID().uuidString, error: .init(message: message))
    }

    private func decode<T: Decodable>(_ type: T.Type, from body: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func locateHistoryAssetRoot() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }
        let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let candidate = enumerator?.nextObject() as? URL {
            guard candidate.lastPathComponent == "index.html",
                  candidate.deletingLastPathComponent().lastPathComponent == "history"
            else {
                continue
            }
            return candidate.deletingLastPathComponent()
        }

        return nil
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html":
            return "text/html"
        case "js":
            return "text/javascript"
        case "css":
            return "text/css"
        case "json":
            return "application/json"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        default:
            return "application/octet-stream"
        }
    }

    private func textEncodingName(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "html", "js", "css", "json", "svg":
            return "utf-8"
        default:
            return nil
        }
    }

    private func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func jsonString<T: Encodable>(for value: T) -> String {
        (try? String(decoding: JSONEncoder().encode(value), as: UTF8.self)) ?? "{}"
    }
}

private enum SpecialPagesError: LocalizedError {
    case invalidParameters
    case unsupportedMethod(String)

    var errorDescription: String? {
        switch self {
        case .invalidParameters:
            return "Invalid special page parameters"
        case .unsupportedMethod(let method):
            return "Unsupported special page method: \(method)"
        }
    }
}

private struct SpecialPagesMessage {
    let context: String
    let featureName: String
    let method: String
    let params: Any
    let id: String?

    init?(_ body: Any) {
        guard let dictionary = body as? [String: Any],
              let context = dictionary["context"] as? String,
              let featureName = dictionary["featureName"] as? String,
              let method = dictionary["method"] as? String
        else {
            return nil
        }

        self.context = context
        self.featureName = featureName
        self.method = method
        self.params = dictionary["params"] ?? [:]
        self.id = dictionary["id"] as? String
    }
}

private struct SuccessPayload<Result: Encodable>: Encodable {
    let context = "specialPages"
    let featureName = SumiSurface.historyURLHost
    let id: String
    let result: Result
}

private struct SubscriptionPayload<Params: Encodable>: Encodable {
    let context: String
    let featureName: String
    let subscriptionName: String
    let params: Params
}

private struct ErrorPayload: Encodable {
    struct Message: Encodable {
        let message: String
    }

    let context = "specialPages"
    let featureName = SumiSurface.historyURLHost
    let id: String
    let error: Message
}

private struct EmptyPayload: Encodable {}

@MainActor
private final class SumiHistoryViewActionsHandler: NSObject {
    private enum Constants {
        static let openManyTabsThreshold = 20
    }

    private struct ContextSelection {
        let identifiers: [VisitIdentifier]
        let siteDomains: [String]
        let urls: [URL]
        let window: NSWindow?

        var isSiteSelection: Bool {
            identifiers.isEmpty && !siteDomains.isEmpty
        }
    }

    private var contextSelection: ContextSelection?
    private var contextMenuResponse: DataModel.DeleteDialogResponse = .noAction
    private var deleteDialogTask: Task<DataModel.DeleteDialogResponse, Never>?

    func open(_ url: URL, window: NSWindow?, browserManager: BrowserManager?) async {
        guard let browserManager else { return }
        if let windowState = windowState(for: window, browserManager: browserManager) {
            browserManager.openHistoryURL(url, in: windowState, preferredOpenMode: .currentTab)
            return
        }
        browserManager.openHistoryURLsInNewWindow([url])
    }

    func showDeleteDialog(
        for query: DataModel.HistoryQueryKind,
        in window: NSWindow?,
        browserManager: BrowserManager?
    ) async -> DataModel.DeleteDialogResponse {
        guard let browserManager else {
            return .noAction
        }

        let visits = await browserManager.historyManager.dataProvider.visits(matching: query)
        guard !visits.isEmpty else {
            return .noAction
        }

        if case .visits(let identifiers) = query, identifiers.count == 1 {
            await browserManager.historyManager.delete(query: query)
            return .delete
        }

        let alert = NSAlert()
        alert.messageText = deleteDialogTitle(for: query)
        alert.informativeText = "This will permanently remove the selected browsing history."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if let window {
            let response = await alert.sumiBeginSheetModal(for: window)
            guard response == .alertFirstButtonReturn else {
                return .noAction
            }
        } else if alert.runModal() != .alertFirstButtonReturn {
            return .noAction
        }

        await browserManager.historyManager.delete(query: query)
        return .delete
    }

    func showDeleteDialog(
        forEntries entries: [String],
        in window: NSWindow?,
        browserManager: BrowserManager?
    ) async -> DataModel.DeleteDialogResponse {
        let siteDomains = entries.compactMap { entry in
            entry.hasPrefix("site:") ? String(entry.dropFirst(5)) : nil
        }
        if !siteDomains.isEmpty {
            return await showDeleteDialog(
                for: .domainFilter(Set(siteDomains)),
                in: window,
                browserManager: browserManager
            )
        }

        let identifiers = entries.compactMap(VisitIdentifier.init)
        guard !identifiers.isEmpty else {
            return .noAction
        }
        return await showDeleteDialog(
            for: .visits(identifiers),
            in: window,
            browserManager: browserManager
        )
    }

    func showContextMenu(
        for entries: [String],
        in window: NSWindow?,
        browserManager: BrowserManager?
    ) async -> DataModel.DeleteDialogResponse {
        guard let browserManager else {
            return .noAction
        }

        contextMenuResponse = .noAction
        deleteDialogTask = nil

        let identifiers = entries.compactMap(VisitIdentifier.init)
        let siteDomains = entries.compactMap { entry in
            entry.hasPrefix("site:") ? String(entry.dropFirst(5)) : nil
        }

        let urls: [URL]
        if !siteDomains.isEmpty {
            urls = siteDomains.compactMap {
                browserManager.historyManager.dataProvider.preferredURL(forSiteDomain: $0)
            }
        } else {
            urls = identifiers.compactMap { URL(string: $0.url) }
        }

        contextSelection = ContextSelection(
            identifiers: identifiers,
            siteDomains: siteDomains,
            urls: Array(NSOrderedSet(array: urls)).compactMap { $0 as? URL },
            window: window
        )

        let menu = NSMenu(title: "History")
        menu.autoenablesItems = false

        let openTabsTitle = urls.count == 1 ? "Open in New Tab" : "Open All in New Tabs"
        menu.addItem(makeMenuItem(title: openTabsTitle, action: #selector(openInNewTab(_:))))

        let openWindowsTitle = urls.count == 1 ? "Open in New Window" : "Open All in New Window"
        menu.addItem(makeMenuItem(title: openWindowsTitle, action: #selector(openInNewWindow(_:))))

        if identifiers.count <= 1 || !siteDomains.isEmpty {
            menu.addItem(.separator())
            menu.addItem(
                makeMenuItem(
                    title: "Show All History From This Site",
                    action: #selector(showAllHistoryFromThisSite(_:))
                )
            )
        }

        if urls.count == 1 {
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(title: "Copy Link", action: #selector(copyLink(_:))))
        }

        menu.addItem(.separator())
        let deleteTitle = siteDomains.isEmpty ? "Delete" : "Delete History and Browsing Data"
        menu.addItem(makeMenuItem(title: deleteTitle, action: #selector(deleteSelection(_:))))

        if !menu.items.isEmpty {
            let view = window?.contentView
            let mouseLocation = window.flatMap { view?.convert($0.mouseLocationOutsideOfEventStream, from: nil) }
                ?? NSEvent.mouseLocation
            menu.popUp(positioning: nil, at: mouseLocation, in: view)
        }

        if let deleteDialogTask {
            contextMenuResponse = await deleteDialogTask.value
            self.deleteDialogTask = nil
        }
        contextSelection = nil
        return contextMenuResponse
    }

    @objc private func openInNewTab(_ sender: NSMenuItem) {
        _ = sender
        guard let browserManager = SumiSpecialPagesController.shared.browserManager,
              let contextSelection
        else {
            return
        }
        Task { @MainActor in
            guard await confirmOpeningMultipleTabsIfNeeded(
                count: contextSelection.urls.count,
                in: contextSelection.window
            ) else {
                return
            }

            if let windowState = windowState(for: contextSelection.window, browserManager: browserManager)
                ?? browserManager.windowRegistry?.activeWindow
            {
                browserManager.openHistoryURLsInNewTabs(contextSelection.urls, in: windowState)
            } else {
                browserManager.openHistoryURLsInNewWindow(contextSelection.urls)
            }
        }
    }

    @objc private func openInNewWindow(_ sender: NSMenuItem) {
        _ = sender
        guard let browserManager = SumiSpecialPagesController.shared.browserManager,
              let contextSelection
        else {
            return
        }
        Task { @MainActor in
            guard await confirmOpeningMultipleTabsIfNeeded(
                count: contextSelection.urls.count,
                in: contextSelection.window
            ) else {
                return
            }
            browserManager.openHistoryURLsInNewWindow(contextSelection.urls)
        }
    }

    @objc private func showAllHistoryFromThisSite(_ sender: NSMenuItem) {
        _ = sender
        contextMenuResponse = .domainSearch
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        _ = sender
        guard let url = contextSelection?.urls.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc private func deleteSelection(_ sender: NSMenuItem) {
        _ = sender
        guard let browserManager = SumiSpecialPagesController.shared.browserManager,
              let contextSelection
        else {
            return
        }

        let query: DataModel.HistoryQueryKind
        if contextSelection.isSiteSelection {
            query = .domainFilter(Set(contextSelection.siteDomains))
        } else {
            query = .visits(contextSelection.identifiers)
        }

        deleteDialogTask = Task { @MainActor [weak self] in
            guard let self else { return .noAction }
            return await self.showDeleteDialog(
                for: query,
                in: contextSelection.window,
                browserManager: browserManager
            )
        }
    }

    private func windowState(
        for window: NSWindow?,
        browserManager: BrowserManager
    ) -> BrowserWindowState? {
        guard let window else { return nil }
        return browserManager.windowRegistry?.windows.values.first(where: { $0.window === window })
    }

    private func confirmOpeningMultipleTabsIfNeeded(
        count: Int,
        in window: NSWindow?
    ) async -> Bool {
        guard count >= Constants.openManyTabsThreshold else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Open Multiple Tabs"
        alert.informativeText = "Open \(count) tabs from history?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        if let window {
            return await alert.sumiBeginSheetModal(for: window) == .alertFirstButtonReturn
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func deleteDialogTitle(for query: DataModel.HistoryQueryKind) -> String {
        switch query {
        case .rangeFilter(.all):
            return "Clear All History"
        case .rangeFilter:
            return "Delete History Range"
        case .searchTerm:
            return "Delete Search Results"
        case .domainFilter:
            return "Delete Site History"
        case .dateFilter:
            return "Delete History Day"
        case .visits(let visits):
            return visits.count == 1 ? "Delete History Entry" : "Delete History Entries"
        }
    }

    private func makeMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }
}

private extension NSImage {
    func pngData() -> Data? {
        var proposedRect = NSRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              let representation = NSBitmapImageRep(cgImage: cgImage).representation(
                using: .png,
                properties: [:]
              )
        else {
            return nil
        }
        return representation
    }
}

private extension NSAlert {
    @MainActor
    func sumiBeginSheetModal(for window: NSWindow) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }
}
