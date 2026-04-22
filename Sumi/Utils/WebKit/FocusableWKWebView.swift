import AppKit
import WebKit
import ObjectiveC.runtime

private var focusableWKWebViewContextMenuLifecycleAssociationKey: UInt8 = 0

@MainActor
private final class FocusableWKWebViewContextMenuLifecycleDelegate: NSObject, NSMenuDelegate {
    weak var webView: FocusableWKWebView?
    weak var windowState: BrowserWindowState?
    weak var previousDelegate: NSMenuDelegate?

    private var token: SidebarTransientSessionToken?
    private weak var tokenCoordinator: SidebarTransientSessionCoordinator?
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
    }
}

// Simple subclass to ensure clicking a webview focuses its tab in the app state
@MainActor
final class FocusableWKWebView: WKWebView {
    weak var owningTab: Tab?

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

    override var isInFullScreenMode: Bool {
        sumiIsInFullscreenElementPresentation
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let owningTab = owningTab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            owningTab?.setClickModifierFlags([])
        }
    }
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

    private func contextMenuWindowState() -> BrowserWindowState? {
        guard let owningTab else { return nil }
        return owningTab.browserManager?.windowState(containing: owningTab)
            ?? owningTab.browserManager?.windowRegistry?.activeWindow
    }

}

@MainActor
extension WKWebView {
    private enum SumiFullscreenSelector {
        static let fullScreenPlaceholderView = NSSelectorFromString("_fullScreenPlaceholderView")
    }

    var sumiFullScreenPlaceholderView: NSView? {
        guard responds(to: SumiFullscreenSelector.fullScreenPlaceholderView) else { return nil }
        return value(
            forKey: NSStringFromSelector(SumiFullscreenSelector.fullScreenPlaceholderView)
        ) as? NSView
    }

    var sumiTabContentView: NSView {
        sumiFullScreenPlaceholderView ?? self
    }

    var sumiIsInFullscreenElementPresentation: Bool {
        fullscreenState != .notInFullscreen
    }

    var sumiFullscreenTabContentViewForHost: NSView? {
        if sumiIsInFullscreenElementPresentation {
            return sumiFullScreenPlaceholderView
        }

        return self
    }
}

// MARK: - Find In Page
struct _WKFindOptions: OptionSet {
    let rawValue: UInt

    static let caseInsensitive = Self(rawValue: 1 << 0)
    static let backwards = Self(rawValue: 1 << 3)
    static let wrapAround = Self(rawValue: 1 << 4)
    static let showOverlay = Self(rawValue: 1 << 5)
    static let showFindIndicator = Self(rawValue: 1 << 6)
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
    @objc dynamic private func find(_ _: String, with _: UInt, maxCount _: UInt) {}

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
