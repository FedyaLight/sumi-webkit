import AppKit
@preconcurrency import UserNotifications
import WebKit
import UniformTypeIdentifiers
import ObjectiveC.runtime

private var focusableWKWebViewContextMenuLifecycleAssociationKey: UInt8 = 0

@MainActor
private final class FocusableWKWebViewContextMenuLifecycleDelegate: NSObject, NSMenuDelegate {
    weak var webView: FocusableWKWebView?
    weak var windowState: BrowserWindowState?
    weak var previousDelegate: NSMenuDelegate?

    private var token: SidebarTransientSessionToken?
    private weak var tokenCoordinator: SidebarTransientSessionCoordinator?
    private weak var observedMenu: NSMenu?
    private var endTrackingObserver: NSObjectProtocol?
    private var didOpen = false

    init(
        webView: FocusableWKWebView,
        windowState: BrowserWindowState,
        previousDelegate: NSMenuDelegate?
    ) {
        self.webView = webView
        self.windowState = windowState
        self.previousDelegate = previousDelegate
        super.init()
    }

    deinit {
        if let endTrackingObserver {
            NotificationCenter.default.removeObserver(endTrackingObserver)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                tokenCoordinator?.endSession(token)
            }
        }
    }

    func update(webView: FocusableWKWebView, windowState: BrowserWindowState) {
        self.webView = webView
        self.windowState = windowState
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard !didOpen else { return }
        didOpen = true
        observeEndTracking(for: menu)
        previousDelegate?.menuWillOpen?(menu)
        guard let webView,
              let windowState
        else { return }

        let coordinator = windowState.sidebarTransientSessionCoordinator
        coordinator.prepareMenuPresentationSource(ownerView: webView)
        let source = coordinator.preparedPresentationSource(
            window: webView.window ?? windowState.window,
            ownerView: webView
        )
        tokenCoordinator = coordinator
        token = coordinator.beginSession(
            kind: .contextMenu,
            source: source,
            path: "FocusableWKWebView.contextMenu",
            preservePendingSource: true
        )
    }

    func menuDidClose(_ menu: NSMenu) {
        if didOpen {
            previousDelegate?.menuDidClose?(menu)
        }
        finish(menu)
    }

    private func finish(_ menu: NSMenu) {
        removeEndTrackingObserver()

        let tokenToEnd = token
        token = nil
        tokenCoordinator?.endSession(tokenToEnd)
        tokenCoordinator = nil
        didOpen = false

        if menu.delegate === self {
            menu.delegate = previousDelegate
        }
        objc_setAssociatedObject(
            menu,
            &focusableWKWebViewContextMenuLifecycleAssociationKey,
            nil,
            .OBJC_ASSOCIATION_ASSIGN
        )
    }

    private func observeEndTracking(for menu: NSMenu) {
        removeEndTrackingObserver()
        observedMenu = menu
        endTrackingObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: menu,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let menu = notification.object as? NSMenu
            else { return }
            MainActor.assumeIsolated {
                self.finish(menu)
            }
        }
    }

    private func removeEndTrackingObserver() {
        if let endTrackingObserver {
            NotificationCenter.default.removeObserver(endTrackingObserver)
            self.endTrackingObserver = nil
        }
        observedMenu = nil
    }
}

// Simple subclass to ensure clicking a webview focuses its tab in the app state
@MainActor
final class FocusableWKWebView: WKWebView {
    weak var owningTab: Tab?
    var contextMenuBridge: WebContextMenuBridge?
    nonisolated private static let imageContentTypes: [UTType] = [
        .jpeg, .png, .gif, .bmp, .tiff, .webP, .heic, .heif
    ]

    deinit {
        // MEMORY LEAK FIX: Detach bridge deterministically. The primary cleanup now
        // happens in Tab.cleanupCloneWebView(), but this is a safety net.
        if let bridge = contextMenuBridge {
            let bridge = bridge
            Task { @MainActor in
                bridge.detach()
            }
        }
        contextMenuBridge = nil
    }

    override func mouseDown(with event: NSEvent) {
        owningTab?.setClickModifierFlags(event.modifierFlags)

        if owningTab?.isFreezingNavigationStateDuringBackForwardGesture != true {
            owningTab?.activate()
        }
        // Ensure this webview becomes first responder so it can receive menu events
        if owningTab?.isFreezingNavigationStateDuringBackForwardGesture != true,
           window?.firstResponder != self {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if owningTab?.isFreezingNavigationStateDuringBackForwardGesture != true {
            owningTab?.activate()
        }
        // Ensure this webview becomes first responder so willOpenMenu gets called
        if owningTab?.isFreezingNavigationStateDuringBackForwardGesture != true,
           window?.firstResponder != self {
            RuntimeDiagnostics.debug("Promoting FocusableWKWebView to first responder before context menu.", category: "FocusableWKWebView")
            window?.makeFirstResponder(self)
        }
        super.rightMouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let owningTab = owningTab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            owningTab?.setClickModifierFlags([])
        }
    }
    private weak var pendingMenu: NSMenu?
    private var pendingCapture: WebContextMenuCapture?
    private var contextMenuFallbackWorkItem: DispatchWorkItem?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else {
            return nil
        }
        prepareMenu(menu, isOpening: false)
        return menu
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        prepareMenu(menu, isOpening: true)
    }

    private func prepareMenu(_ menu: NSMenu, isOpening: Bool) {
        let lifecycleDelegate = installContextMenuLifecycle(on: menu)
        if isOpening {
            lifecycleDelegate?.menuWillOpen(menu)
        }

        pendingMenu = menu
        pendingCapture = owningTab?.pendingContextMenuCapture

        contextMenuFallbackWorkItem?.cancel()
        let fallback = DispatchWorkItem { [weak self, weak menu] in
            guard let self, let menu, self.pendingMenu === menu else {
                return
            }
            RuntimeDiagnostics.debug("Applying fallback sanitization for pending WKWebView context menu.", category: "FocusableWKWebView")
            self.sanitizeDefaultMenu(menu)
            self.pendingMenu = nil
            self.pendingCapture = nil
            self.contextMenuFallbackWorkItem = nil
            self.owningTab?.pendingContextMenuCapture = nil
        }
        contextMenuFallbackWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: fallback)

        _ = applyPendingContextMenuIfPossible()
    }

    private func installContextMenuLifecycle(
        on menu: NSMenu,
        windowState explicitWindowState: BrowserWindowState? = nil
    ) -> FocusableWKWebViewContextMenuLifecycleDelegate? {
        guard let windowState = explicitWindowState ?? contextMenuWindowState() else { return nil }

        if let lifecycleDelegate = objc_getAssociatedObject(
            menu,
            &focusableWKWebViewContextMenuLifecycleAssociationKey
        ) as? FocusableWKWebViewContextMenuLifecycleDelegate {
            lifecycleDelegate.update(webView: self, windowState: windowState)
            if menu.delegate !== lifecycleDelegate {
                lifecycleDelegate.previousDelegate = menu.delegate
                menu.delegate = lifecycleDelegate
            }
            return lifecycleDelegate
        }

        let lifecycleDelegate = FocusableWKWebViewContextMenuLifecycleDelegate(
            webView: self,
            windowState: windowState,
            previousDelegate: menu.delegate
        )
        menu.delegate = lifecycleDelegate
        objc_setAssociatedObject(
            menu,
            &focusableWKWebViewContextMenuLifecycleAssociationKey,
            lifecycleDelegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return lifecycleDelegate
    }

#if DEBUG
    func beginContextMenuLifecycleForTesting(on menu: NSMenu, windowState: BrowserWindowState) {
        installContextMenuLifecycle(on: menu, windowState: windowState)?.menuWillOpen(menu)
    }
#endif

    private func contextMenuWindowState() -> BrowserWindowState? {
        guard let owningTab else { return nil }
        return owningTab.browserManager?.windowState(containing: owningTab)
            ?? owningTab.browserManager?.windowRegistry?.activeWindow
    }

    func handleImageDownload(identifier: String, promptForLocation: Bool = false) {
        let destinationPreference: Download.DestinationPreference = promptForLocation ? .askUser : .automaticDownloadsFolder

        if identifier.hasPrefix("data:") {
            handleDataURL(identifier, destinationPreference: destinationPreference)
            return
        }

        guard let url = resolveImageURL(from: identifier) else {
            RuntimeDiagnostics.debug("Unable to resolve image URL from context-menu identifier.", category: "FocusableWKWebView")
            return
        }

        prepareRequest(for: url) { [weak self] request in
            DispatchQueue.main.async {
                self?.initiateDownload(using: request, originalURL: url, destinationPreference: destinationPreference)
            }
        }
    }

    private func showSaveDialog(
        for localURL: URL,
        suggestedFilename: String,
        allowedContentTypes: [UTType] = FocusableWKWebView.imageContentTypes
    ) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename

        savePanel.directoryURL = SumiDownloadsDirectoryResolver.resolvedDownloadsDirectory()

        // Set allowed file types for images
        savePanel.allowedContentTypes = allowedContentTypes

        // Set the title and message
        savePanel.title = "Save Image"
        savePanel.message = "Choose where to save the image"

        // Show the save dialog
        savePanel.begin { [weak self] result in
            if result == .OK, let destinationURL = savePanel.url {
                do {
                    // Move the downloaded file to the chosen location
                    try FileManager.default.moveItem(at: localURL, to: destinationURL)
                    RuntimeDiagnostics.debug("Saved image to \(destinationURL.path).", category: "FocusableWKWebView")

                    // Show a success notification
                    self?.showSaveSuccessNotification(for: destinationURL)
                } catch {
                    RuntimeDiagnostics.debug("Failed to save image: \(error.localizedDescription)", category: "FocusableWKWebView")
                    self?.showSaveErrorNotification(error: error)
                }
            } else {
                // User cancelled, clean up the temporary file
                try? FileManager.default.removeItem(at: localURL)
            }
        }
    }

    private func showSaveSuccessNotification(for url: URL) {
        postUserNotification(
            title: "Image Saved",
            message: "Saved to \(url.lastPathComponent)"
        )
    }

    private func showSaveErrorNotification(error: Error) {
        postUserNotification(
            title: "Save Failed",
            message: error.localizedDescription
        )
    }

    private func postUserNotification(title: String, message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "focusable-webview-\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

    private func resolveImageURL(from rawValue: String) -> URL? {
        if let absoluteURL = URL(string: rawValue),
           let scheme = absoluteURL.scheme,
           !scheme.isEmpty {
            return absoluteURL
        }

        if rawValue.hasPrefix("//"),
           let scheme = owningTab?.url.scheme {
            return URL(string: "\(scheme):\(rawValue)")
        }

        if let base = owningTab?.url,
           let resolved = URL(string: rawValue, relativeTo: base)?.absoluteURL {
            return resolved
        }

        return nil
    }

    private func prepareRequest(for url: URL, completion: @escaping (URLRequest) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var decoratedRequest = request
            let filteredCookies = Self.relevantCookies(for: url, from: cookies)
            if !filteredCookies.isEmpty {
                let headers = HTTPCookie.requestHeaderFields(with: filteredCookies)
                headers.forEach { key, value in
                    decoratedRequest.setValue(value, forHTTPHeaderField: key)
                }
            }
            completion(decoratedRequest)
        }
    }

    private func initiateDownload(
        using request: URLRequest,
        originalURL: URL,
        destinationPreference: Download.DestinationPreference
    ) {
        guard let tab = owningTab else {
            RuntimeDiagnostics.debug("No owning tab available for download.", category: "FocusableWKWebView")
            return
        }

        var enrichedRequest = request
        if enrichedRequest.value(forHTTPHeaderField: "Referer") == nil {
            enrichedRequest.setValue(tab.url.absoluteString, forHTTPHeaderField: "Referer")
        }

        RuntimeDiagnostics.debug("Starting download for \(originalURL.absoluteString).", category: "FocusableWKWebView")
        // Call WKWebView's startDownload method (inherited from WKWebView)
        self.startDownload(using: enrichedRequest) { [weak self] wkDownload in
            guard let self else { return }
            RuntimeDiagnostics.debug("Download started; registering with DownloadManager.", category: "FocusableWKWebView")
            DispatchQueue.main.async {
                self.registerDownload(wkDownload, originalURL: originalURL, destinationPreference: destinationPreference)
            }
        }
    }

    private func registerDownload(
        _ download: WKDownload,
        originalURL: URL,
        destinationPreference: Download.DestinationPreference
    ) {
        guard let tab = owningTab,
              let manager = tab.browserManager?.downloadManager else { return }

        let proposedName = originalURL.lastPathComponent.isEmpty ? "image" : originalURL.lastPathComponent
        _ = manager.addDownload(
            download,
            originalURL: originalURL,
            suggestedFilename: proposedName,
            destinationPreference: destinationPreference,
            allowedContentTypes: Self.imageContentTypes
        )
    }

    private static func relevantCookies(for url: URL, from cookies: [HTTPCookie]) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let requestPath = url.path.isEmpty ? "/" : url.path

        return cookies.filter { cookie in
            var cookieDomain = cookie.domain.lowercased()
            if cookieDomain.hasPrefix(".") {
                cookieDomain.removeFirst()
            }

            guard !cookieDomain.isEmpty else { return false }
            let domainMatches = host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
            guard domainMatches else { return false }

            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            guard requestPath.hasPrefix(cookiePath) else { return false }

            if cookie.isSecure && url.scheme != "https" {
                return false
            }

            return true
        }
    }

    private func handleDataURL(
        _ dataURLString: String,
        destinationPreference: Download.DestinationPreference
    ) {
        guard let commaIndex = dataURLString.firstIndex(of: ",") else {
            RuntimeDiagnostics.debug("Malformed data URL encountered during download.", category: "FocusableWKWebView")
            return
        }

        let metadata = dataURLString[..<commaIndex]
        let payload = String(dataURLString[dataURLString.index(after: commaIndex)...])
        let isBase64 = metadata.contains(";base64")

        let mimeType = metadata
            .replacingOccurrences(of: "data:", with: "")
            .components(separatedBy: ";")
            .first?
            .lowercased()

        let fileExtension = mimeType.flatMap { mimeTypeToExtension($0) } ?? "img"
        let suggestedFilename = "image.\(fileExtension)"

        let imageData: Data?
        if isBase64 {
            imageData = Data(base64Encoded: payload)
        } else {
            imageData = payload.removingPercentEncoding?.data(using: .utf8)
        }

        guard let data = imageData else {
            RuntimeDiagnostics.debug("Unable to decode data URL contents.", category: "FocusableWKWebView")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        do {
            try data.write(to: tempURL, options: .atomic)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch destinationPreference {
                case .askUser:
                    self.showSaveDialog(
                        for: tempURL,
                        suggestedFilename: suggestedFilename
                    )
                case .automaticDownloadsFolder:
                    self.saveTempFileToDownloads(tempURL, suggestedName: suggestedFilename)
                }
            }
        } catch {
            RuntimeDiagnostics.debug("Failed to materialize data URL: \(error.localizedDescription)", category: "FocusableWKWebView")
        }
    }

    private func saveTempFileToDownloads(_ tempURL: URL, suggestedName: String) {
        let downloads = SumiDownloadsDirectoryResolver.resolvedDownloadsDirectory()

        var destination = downloads.appendingPathComponent(suggestedName)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            let newName = "\(base)-\(counter)" + (ext.isEmpty ? "" : ".\(ext)")
            destination = downloads.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
            showSaveSuccessNotification(for: destination)
        } catch {
            RuntimeDiagnostics.debug("Failed to move data URL temp file: \(error.localizedDescription)", category: "FocusableWKWebView")
        }
    }

    private func mimeTypeToExtension(_ mimeType: String) -> String {
        if let type = UTType(mimeType: mimeType),
           let ext = type.preferredFilenameExtension {
            return ext
        }

        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        default: return "img"
        }
    }

    func contextMenuCaptureDidUpdate(_ capture: WebContextMenuCapture?) {
        pendingCapture = capture
        _ = applyPendingContextMenuIfPossible()
    }

    private func applyPendingContextMenuIfPossible() -> Bool {
        false
    }

    private func sanitizeDefaultMenu(_ menu: NSMenu) {
        _ = menu
        owningTab?.pendingContextMenuCapture = nil
    }
}

// MARK: - Find In Page
struct _WKFindOptions: OptionSet {
    let rawValue: UInt

    static let caseInsensitive = Self(rawValue: 1 << 0)
    static let atWordStarts = Self(rawValue: 1 << 1)
    static let treatMedialCapitalAsWordStart = Self(rawValue: 1 << 2)
    static let backwards = Self(rawValue: 1 << 3)
    static let wrapAround = Self(rawValue: 1 << 4)
    static let showOverlay = Self(rawValue: 1 << 5)
    static let showFindIndicator = Self(rawValue: 1 << 6)
    static let showHighlight = Self(rawValue: 1 << 7)
    static let noIndexChange = Self(rawValue: 1 << 8)
    static let determineMatchIndex = Self(rawValue: 1 << 9)
}

extension FocusableWKWebView {
    enum FindResult: Error, Equatable, Sendable {
        case found(matches: UInt?)
        case notFound
        case cancelled
    }

    private struct AssociatedKeys {
        static var findCompletionHandler: UInt8 = 0
    }

    private var findInPageCompletionHandler: ((FindResult) -> Void)? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.findCompletionHandler) as? ((FindResult) -> Void)
        }
        set {
            objc_setAssociatedObject(
                self,
                &AssociatedKeys.findCompletionHandler,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    @MainActor
    var mimeType: String? {
        get async {
            let value = try? await evaluateJavaScript("document.contentType")
            return value as? String
        }
    }

    @MainActor
    func collapseSelectionToStart() async throws {
        let _: Any? = try await evaluateJavaScript("""
            try {
                window.getSelection().collapseToStart()
            } catch {}
        """)
    }

    @MainActor
    func deselectAll() async throws {
        let _: Any? = try await evaluateJavaScript("""
            try {
                window.getSelection().removeAllRanges()
            } catch {}
        """)
    }

    @MainActor
    func find(_ string: String, with options: _WKFindOptions, maxCount: UInt) async -> FindResult {
        assert(!string.isEmpty)

        // native WKWebView find
        guard self.responds(to: Selector.findString) else {
            // fallback to official `findSting:`
            let config = WKFindConfiguration()
            config.backwards = options.contains(.backwards)
            config.caseSensitive = !options.contains(.caseInsensitive)
            config.wraps = options.contains(.wrapAround)

            return await withCheckedContinuation { continuation in
                self.find(string, configuration: config) { result in
                    continuation.resume(returning: result.matchFound ? .found(matches: nil) : .notFound)
                }
            }
        }

        _=Self.swizzleFindStringOnce

        // receive _WKFindDelegate calls and call completion handler
        NSException.try {
            self.setValue(self, forKey: "findDelegate")
        }
        if let findInPageCompletionHandler {
            self.findInPageCompletionHandler = nil
            findInPageCompletionHandler(.cancelled)
        }

        return await withCheckedContinuation { continuation in
            self.findInPageCompletionHandler = { result in
                continuation.resume(returning: result)
            }
            self.find(string, with: options.rawValue, maxCount: maxCount)
        }
    }

    func clearFindInPageState() {
        guard self.responds(to: Selector.hideFindUI) else {
            assertionFailure("_hideFindUI not available")
            return
        }
        self.perform(Selector.hideFindUI)
    }

    static private let swizzleFindStringOnce: () = {
        guard let originalMethod = class_getInstanceMethod(FocusableWKWebView.self, Selector.findString),
              let swizzledMethod = class_getInstanceMethod(FocusableWKWebView.self, #selector(find(_:with:maxCount:)))
        else {
            assertionFailure("Methods not available")
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()
    // swizzled method to call `_findString:withOptions:maxCount:` without performSelector: usage (as there‘s 3 args)
    @objc dynamic private func find(_ string: String, with options: UInt, maxCount: UInt) {}

    private enum Selector {
        static let findString = NSSelectorFromString("_findString:options:maxCount:")
        static let hideFindUI = NSSelectorFromString("_hideFindUI")
    }
}

extension FocusableWKWebView /* _WKFindDelegate */ {
    @objc(_webView:didFindMatches:forString:withMatchIndex:)
    func webView(_ webView: WKWebView, didFind matchesFound: UInt, for string: String, withMatchIndex _: Int) {
        if let findInPageCompletionHandler {
            self.findInPageCompletionHandler = nil
            findInPageCompletionHandler(.found(matches: matchesFound)) // matchIndex is broken in WebKit
        }
    }

    @objc(_webView:didFailToFindString:)
    func webView(_ webView: WKWebView, didFailToFind string: String) {
        if let findInPageCompletionHandler {
            self.findInPageCompletionHandler = nil
            findInPageCompletionHandler(.notFound)
        }
    }
}
