import AppKit
import Carbon
import WebKit
import SumiWebRuntime

@MainActor
@objc(Sumi_FocusableWKWebView)
final class FocusableWKWebView: WKWebView {
    enum FindResult: Error, Equatable, Sendable {
        case found(matches: UInt?)
        case notFound
        case cancelled
    }

    /// Local kill switch for the DDG-style control-click workaround (not user-facing).
    static var isControlClickFixEnabled: Bool = true

    /// Mirrors `features.macOSBrowserConfig.features.controlClickFix.settings.domains` in DuckDuckGo’s bundled `macos-config.json` (`drive.google.com` only).
    private static let controlClickFixAllowlistedHosts: Set<String> = ["drive.google.com"]

    private var webKitMouseTrackingLoadSheddingOwner: WebKitMouseTrackingLoadSheddingOwner?
    private let webKitClientMediaControlsOwner = WebKitClientMediaControlsOwner()
    private lazy var webPageMenuPresenter = SumiWebPageMenuPresenter()
    private var transientChromeInteractionShieldOwner: WebKitTransientChromeInteractionShieldOwner?
    private var glanceCursorStabilizationOwner: WebKitGlanceCursorStabilizationOwner?

    weak var owningTab: Tab?
    let gestures = WebViewGestureState()
    let hoveredLink = WebViewHoveredLinkState()
    let contextMenu = WebViewContextMenuState()
    let popupUserActivation = SumiPopupUserActivationTracker()
    /// AppKit overlay scroll chrome owned by `SumiWebViewContainerView`.
    weak var overlayScrollChrome: WebContentOverlayScrollChrome?
    private var findInPageCompletionHandler: ((FindResult) -> Void)?
    private var primaryMouseDownReceipt: WebViewGestureReceipt?
    var isTransientChromeMouseTrackingSuppressionExempt = false {
        didSet {
            guard isTransientChromeMouseTrackingSuppressionExempt != oldValue else { return }
            if isTransientChromeMouseTrackingSuppressionExempt {
                setTransientChromeMouseTrackingSuppressed(false)
            } else {
                WebContentMouseTrackingShield.applyCurrentShieldState(to: self)
            }
            webKitMouseTrackingLoadSheddingOwner?.refresh()
        }
    }
    var keepsWebKitMouseTrackingDuringLoad = false {
        didSet {
            guard keepsWebKitMouseTrackingDuringLoad != oldValue else { return }
            webKitMouseTrackingLoadSheddingOwner?.refresh()
        }
    }
    var stabilizesCursorDuringGlancePresentation = false {
        didSet {
            guard stabilizesCursorDuringGlancePresentation != oldValue else { return }
            if stabilizesCursorDuringGlancePresentation {
                refreshMouseTrackingForGlancePresentation()
            } else {
                glanceCursorStabilizationOwner?.reset()
            }
        }
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        _ = Self.swizzleImmediateActionAnimationControllerOnce
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        _ = Self.swizzleImmediateActionAnimationControllerOnce
        super.init(coder: coder)
    }

    override func addTrackingArea(_ trackingArea: NSTrackingArea) {
        guard WebKitMouseTrackingLoadSheddingOwner.canHandle(trackingArea) else {
            superAddTrackingArea(trackingArea)
            return
        }

        webKitMouseTrackingOwner().installTrackingArea(trackingArea)
    }

    private func superAddTrackingArea(_ trackingArea: NSTrackingArea) {
        super.addTrackingArea(trackingArea)
    }

    private func webKitMouseTrackingOwner() -> WebKitMouseTrackingLoadSheddingOwner {
        if let webKitMouseTrackingLoadSheddingOwner {
            return webKitMouseTrackingLoadSheddingOwner
        }
        let owner = WebKitMouseTrackingLoadSheddingOwner(
            webView: self,
            addTrackingArea: { [weak self] trackingArea in
                self?.superAddTrackingArea(trackingArea)
            },
            removeTrackingArea: { [weak self] trackingArea in
                self?.removeTrackingArea(trackingArea)
            },
            containsTrackingArea: { [weak self] trackingArea in
                self?.trackingAreas.contains(trackingArea) == true
            },
            keepsMouseTrackingDuringLoad: { [weak self] in
                self?.keepsWebKitMouseTrackingDuringLoad == true
            },
            isTransientChromeMouseTrackingSuppressed: { [weak self] in
                self?.isTransientChromeMouseTrackingSuppressed == true
            }
        )
        webKitMouseTrackingLoadSheddingOwner = owner
        return owner
    }

    private var isTransientChromeMouseTrackingSuppressed: Bool {
        transientChromeInteractionShieldOwner?.isMouseTrackingSuppressed == true
    }

    private func ensureTransientChromeInteractionShieldOwner() -> WebKitTransientChromeInteractionShieldOwner {
        if let transientChromeInteractionShieldOwner {
            return transientChromeInteractionShieldOwner
        }

        let owner = WebKitTransientChromeInteractionShieldOwner(
            isSuppressionExempt: { [weak self] in
                self?.isTransientChromeMouseTrackingSuppressionExempt == true
            },
            currentClientPoint: { [weak self] in
                self?.currentClientPointForPageInteractionShield()
            },
            evaluateJavaScript: { [weak self] script in
                self?.evaluateJavaScript(script, completionHandler: nil)
            },
            refreshMouseTracking: { [weak self] in
                self?.webKitMouseTrackingLoadSheddingOwner?.refresh()
            },
            clearHoveredLink: { [weak self] in
                self?.hoveredLink.update(nil)
            }
        )
        transientChromeInteractionShieldOwner = owner
        return owner
    }

    private func ensureGlanceCursorStabilizationOwner() -> WebKitGlanceCursorStabilizationOwner {
        if let glanceCursorStabilizationOwner {
            return glanceCursorStabilizationOwner
        }

        let owner = WebKitGlanceCursorStabilizationOwner(
            dependencies: WebKitGlanceCursorStabilizationOwner.Dependencies(
                isEnabled: { [weak self] in
                    self?.stabilizesCursorDuringGlancePresentation == true
                },
                pointInView: { [weak self] event in
                    self?.convert(event.locationInWindow, from: nil)
                },
                currentMousePointInView: { [weak self] in
                    guard let self,
                          let window = self.window
                    else { return nil }
                    return self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                },
                containsPoint: { [weak self] point in
                    self?.bounds.contains(point) == true
                },
                currentCursor: {
                    NSCursor.current
                },
                setCursor: { cursor in
                    cursor.set()
                },
                performDefaultMouseMoved: { [weak self] event in
                    self?.performDefaultMouseMovedBehavior(with: event)
                },
                scheduleSettleCapture: { workItem in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
                },
                currentTimestamp: {
                    ProcessInfo.processInfo.systemUptime
                }
            )
        )
        glanceCursorStabilizationOwner = owner
        return owner
    }

    func refreshMouseTrackingForGlancePresentation() {
        updateTrackingAreas()
        webKitMouseTrackingLoadSheddingOwner?.refresh()
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        WebContentMouseTrackingShield.applyCurrentShieldState(to: self)
    }

    func setTransientChromeMouseTrackingSuppressed(
        _ isSuppressed: Bool,
        shieldRects: [SumiTransientChromeInteractionShieldRect] = []
    ) {
        guard isSuppressed || transientChromeInteractionShieldOwner != nil else { return }

        ensureTransientChromeInteractionShieldOwner().setMouseTrackingSuppressed(
            isSuppressed,
            shieldRects: shieldRects
        )
    }

    private func currentClientPointForPageInteractionShield() -> CGPoint? {
        guard let window else { return nil }

        let locationInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(locationInView) else { return nil }

        let clientY = isFlipped ? locationInView.y : bounds.height - locationInView.y
        return CGPoint(x: locationInView.x, y: clientY)
    }

    override func mouseDown(with event: NSEvent) {
        primaryMouseDownReceipt = recordUserGesture(event, kind: .primaryMouseDown)

        if Self.shouldApplyControlClickFix(
            event: event,
            pageHost: url?.host,
            isFixEnabled: Self.isControlClickFixEnabled
        ),
           let modifierReleased = NSEvent.keyEvent(
            with: .flagsChanged,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags.subtracting(.control),
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_Control)
           ) {
            NSApp.sendEvent(modifierReleased)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                self.performDefaultMouseDownBehavior(with: event)
            }
            return
        }

        performDefaultMouseDownBehavior(with: event)
    }

    private func performDefaultMouseDownBehavior(with event: NSEvent) {
        super.mouseDown(with: event)
        owningTab?.linkPresentationCommands.activateSource(of: self)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isTransientChromeMouseTrackingSuppressed else {
            return
        }
        guard stabilizesCursorDuringGlancePresentation else {
            performDefaultMouseMovedBehavior(with: event)
            return
        }
        ensureGlanceCursorStabilizationOwner().mouseMoved(with: event)
    }

    private func performDefaultMouseMovedBehavior(with event: NSEvent) {
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isTransientChromeMouseTrackingSuppressed else {
            return
        }
        super.mouseEntered(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !isTransientChromeMouseTrackingSuppressed else {
            return
        }
        super.cursorUpdate(with: event)
        if stabilizesCursorDuringGlancePresentation {
            ensureGlanceCursorStabilizationOwner().cursorUpdated(with: event)
        }
    }

    /// DDG-style gate: left primary click + control + allowlisted host + kill switch.
    static func shouldApplyControlClickFix(
        event: NSEvent,
        pageHost: String?,
        isFixEnabled: Bool
    ) -> Bool {
        guard isFixEnabled else { return false }
        guard event.type == .leftMouseDown, event.modifierFlags.contains(.control) else { return false }
        guard let host = pageHost?.lowercased(), controlClickFixAllowlistedHosts.contains(host) else {
            return false
        }
        return true
    }

    override func otherMouseDown(with event: NSEvent) {
        recordUserGesture(event, kind: .auxiliaryMouseDown)
        super.otherMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        recordUserGesture(event, kind: .keyDown)
        super.keyDown(with: event)
        if Self.isPageScrollKey(event) {
            overlayScrollChrome?.handleScrollWheel()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        overlayScrollChrome?.handleScrollWheel()
    }

    @discardableResult
    func recordUserGesture(
        _ event: NSEvent,
        kind: WebViewGestureKind
    ) -> WebViewGestureReceipt {
        let receipt = gestures.record(event, kind: kind)
        popupUserActivation.record(event: event, kind: kind.popupActivationKind)
        guard let tab = owningTab else { return receipt }
        tab.navigationRuntime.normalWebViewExtensionRuntime.reconcileOnUserGesture(
            tab,
            "FocusableWKWebView.recordUserGesture"
        )
        return receipt
    }

    func resetPageInteractionState() {
        resetPageInteractionState(preservingRecentPrimaryMouseDown: false)
    }

    func resetPageInteractionStateForNavigation() {
        resetPageInteractionState(preservingRecentPrimaryMouseDown: true)
    }

    private func resetPageInteractionState(
        preservingRecentPrimaryMouseDown: Bool
    ) {
        primaryMouseDownReceipt = nil
        if preservingRecentPrimaryMouseDown {
            gestures.clearCurrentGesture()
        } else {
            gestures.clear()
        }
        hoveredLink.update(nil)
        contextMenu.clear()
        popupUserActivation.clear()
    }

    func consumeGestureForBrowserCommand() {
        gestures.clear()
        popupUserActivation.spendCurrentActivation()
    }

    private static func isPageScrollKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125, 126, 115, 119, 116, 121, 49: // down/up/home/end/pageUp/pageDown/space
            return true
        default:
            return false
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        owningTab?.linkPresentationCommands.activateSource(of: self)
        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            isInspectable = true
        }
        super.rightMouseDown(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        webPageMenuPresenter.menuWillOpen(menu, for: self)
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        webPageMenuPresenter.menuDidClose(menu)
    }

    override var isInFullScreenMode: Bool {
        // WebKit element fullscreen is owned by WKWebView.fullscreenState, not by
        // AppKit's NSView fullscreen mode flag.
        sumiIsInFullscreenElementPresentation
    }

    override func makeTouchBar() -> NSTouchBar? {
        super.makeTouchBar() ?? webKitClientMediaControlsOwner.makeTouchBar()
    }

    @objc(_addMediaPlaybackControlsView:)
    func addMediaPlaybackControlsView(_ mediaControlsView: AnyObject) {
        guard let controlsView = mediaControlsView as? NSView else { return }
        touchBar = webKitClientMediaControlsOwner.addMediaPlaybackControlsView(controlsView)
    }

    @objc(_removeMediaPlaybackControlsView)
    func removeMediaPlaybackControlsView() {
        webKitClientMediaControlsOwner.removeMediaPlaybackControlsView()
        touchBar = nil
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let gestureReceipt = primaryMouseDownReceipt
        primaryMouseDownReceipt = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.gestures.clear(ifCurrent: gestureReceipt)
        }
    }

    @objc dynamic func swizzled_immediateActionAnimationController(
        forHitTestResult hitTestResult: AnyObject,
        withType type: UInt,
        userData: AnyObject?
    ) -> AnyObject? {
        if type == SumiImmediateActionType.linkPreview.rawValue {
            return NSNull()
        }
        return nil
    }

    private static let swizzleImmediateActionAnimationControllerOnce: Void = {
        let selector = NSSelectorFromString(
            "_immediateActionAnimationControllerForHitTestResult:withType:userData:"
        )
        let swizzledSelector = #selector(
            swizzled_immediateActionAnimationController(
                forHitTestResult:withType:userData:
            )
        )

        guard let originalMethod = class_getInstanceMethod(FocusableWKWebView.self, selector),
              let swizzledMethod = class_getInstanceMethod(FocusableWKWebView.self, swizzledSelector)
        else {
            assertionFailure("WKWebView immediate action selector is unavailable")
            return
        }

        let didAddOriginalMethod = class_addMethod(
            FocusableWKWebView.self,
            selector,
            method_getImplementation(originalMethod),
            method_getTypeEncoding(originalMethod)
        )
        guard didAddOriginalMethod,
              let webViewOriginalMethod = class_getInstanceMethod(FocusableWKWebView.self, selector)
        else {
            assertionFailure("Failed to add immediate action selector to FocusableWKWebView")
            return
        }

        method_exchangeImplementations(webViewOriginalMethod, swizzledMethod)
    }()

    private enum SumiImmediateActionType: UInt {
        case linkPreview = 1
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

        _ = Self.swizzleFindStringOnce

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
