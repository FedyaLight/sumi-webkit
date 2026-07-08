import AppKit
import Carbon
import Combine
import WebKit

enum SumiWebViewInteractionEvent {
    case mouseDown(NSEvent)
    case middleMouseDown(NSEvent)
    case keyDown(NSEvent)
    case scrollWheel(NSEvent)
}

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
    private lazy var webPageMenuController = SumiWebPageMenuController()
    private var transientChromeInteractionShieldOwner: WebKitTransientChromeInteractionShieldOwner?
    private var glanceCursorStabilizationOwner: WebKitGlanceCursorStabilizationOwner?

    weak var owningTab: Tab?
    /// AppKit overlay scroll chrome owned by `SumiWebViewContainerView`.
    weak var overlayScrollChrome: WebContentOverlayScrollChrome?
    let interactionEventsPublisher = PassthroughSubject<SumiWebViewInteractionEvent, Never>()
    private var findInPageCompletionHandler: ((FindResult) -> Void)?
    private var shouldSwallowNextMouseUpAfterDynamicGlance = false
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
            dependencies: WebKitMouseTrackingLoadSheddingOwner.Dependencies(
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
            dependencies: WebKitTransientChromeInteractionShieldOwner.Dependencies(
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
                    self?.owningTab?.updateHoveredLink(nil)
                }
            )
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
        owningTab?.setClickModifierFlags(event.modifierFlags)
        owningTab?.recordPopupUserActivation(event, kind: "mouseDown")

        if routeDynamicGlanceIfNeeded(with: event) {
            return
        }

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

    private func routeDynamicGlanceIfNeeded(with event: NSEvent) -> Bool {
        guard let tab = owningTab,
              let targetURL = tab.dynamicGlanceURLForWebViewMouseDown(event)
        else { return false }

        shouldSwallowNextMouseUpAfterDynamicGlance = true
        tab.openURLInGlanceFromLinkGesture(targetURL)
        tab.activate()
        tab.setClickModifierFlags([])
        return true
    }

    private func performDefaultMouseDownBehavior(with event: NSEvent) {
        super.mouseDown(with: event)
        owningTab?.activate()
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
        owningTab?.setClickModifierFlags(event.modifierFlags)
        owningTab?.recordPopupUserActivation(event, kind: "middleMouseDown")
        super.otherMouseDown(with: event)
        if event.buttonNumber == 2 {
            interactionEventsPublisher.send(.middleMouseDown(event))
        }
    }

    override func keyDown(with event: NSEvent) {
        owningTab?.recordPopupUserActivation(event, kind: "keyDown")
        super.keyDown(with: event)
        interactionEventsPublisher.send(.keyDown(event))
        if Self.isPageScrollKey(event) {
            overlayScrollChrome?.handleScrollWheel()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        interactionEventsPublisher.send(.scrollWheel(event))
        overlayScrollChrome?.handleScrollWheel()
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
        owningTab?.activate()
        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            isInspectable = true
        }
        super.rightMouseDown(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        webPageMenuController.prepare(menu, for: self)
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
        if shouldSwallowNextMouseUpAfterDynamicGlance {
            shouldSwallowNextMouseUpAfterDynamicGlance = false
            owningTab?.setClickModifierFlags([])
            owningTab?.clearWebViewInteractionEvent()
            return
        }

        super.mouseUp(with: event)
        let owningTab = owningTab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            owningTab?.setClickModifierFlags([])
            owningTab?.clearWebViewInteractionEvent()
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
