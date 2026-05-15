import AppKit
import Carbon
import Combine
import WebKit
import ObjectiveC.runtime

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

    private static let webKitMouseTrackingLoadSheddingEnabled = true
    private static let webKitMouseTrackingObserverClassName = "WKMouseTrackingObserver"
    private var webKitMouseTrackingLoadSheddingObserver: NSKeyValueObservation?
    private var webKitMouseTrackingArea: NSTrackingArea?
    private var isWebKitMouseTrackingLoadSheddingActive = false
    private var isTransientChromeMouseTrackingSuppressed = false
    private var isTransientChromeInteractionShieldApplied = false
    private var transientChromeInteractionShieldRects: [SumiTransientChromeInteractionShieldRect] = []
    private var webKitClientMediaControlsView: NSView?
    private var webKitClientMediaControlsTouchBar: NSTouchBar?
    private var webKitClientMediaControlsProvider: NSObject?

    weak var owningTab: Tab?
    let interactionEventsPublisher = PassthroughSubject<SumiWebViewInteractionEvent, Never>()
    private var findInPageCompletionHandler: ((FindResult) -> Void)?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        _ = Self.swizzleImmediateActionAnimationControllerOnce
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        _ = Self.swizzleImmediateActionAnimationControllerOnce
        super.init(coder: coder)
    }

    deinit {
        webKitMouseTrackingLoadSheddingObserver?.invalidate()
    }

    override func addTrackingArea(_ trackingArea: NSTrackingArea) {
        guard Self.webKitMouseTrackingLoadSheddingEnabled,
              trackingArea.owner?.className == Self.webKitMouseTrackingObserverClassName
        else {
            super.addTrackingArea(trackingArea)
            return
        }

        installWebKitMouseTrackingLoadShedding(for: trackingArea)
        if !shouldSuspendWebKitMouseTracking, !trackingAreas.contains(trackingArea) {
            super.addTrackingArea(trackingArea)
        }
        scheduleWebKitMouseTrackingRefresh(for: trackingArea)
    }

    private func installWebKitMouseTrackingLoadShedding(for trackingArea: NSTrackingArea) {
        guard webKitMouseTrackingArea !== trackingArea ||
              webKitMouseTrackingLoadSheddingObserver == nil
        else { return }

        webKitMouseTrackingLoadSheddingObserver?.invalidate()
        webKitMouseTrackingArea = trackingArea
        let trackingAreaID = ObjectIdentifier(trackingArea)
        webKitMouseTrackingLoadSheddingObserver = observe(\.isLoading, options: [.new]) { [weak self, trackingAreaID] _, change in
            guard let isLoading = change.newValue else { return }
            Task { @MainActor [weak self, trackingAreaID] in
                guard let self,
                      let trackingArea = self.webKitMouseTrackingArea,
                      ObjectIdentifier(trackingArea) == trackingAreaID
                else { return }
                self.isWebKitMouseTrackingLoadSheddingActive = isLoading
                self.updateWebKitMouseTrackingArea(trackingArea)
            }
        }
    }

    private func scheduleWebKitMouseTrackingRefresh(for trackingArea: NSTrackingArea) {
        let trackingAreaID = ObjectIdentifier(trackingArea)
        Task { @MainActor [weak self, trackingAreaID] in
            guard let self,
                  let trackingArea = self.webKitMouseTrackingArea,
                  ObjectIdentifier(trackingArea) == trackingAreaID
            else { return }
            self.updateWebKitMouseTrackingArea(trackingArea)
        }
    }

    private func updateWebKitMouseTrackingArea(_ trackingArea: NSTrackingArea) {
        if shouldSuspendWebKitMouseTracking {
            guard trackingAreas.contains(trackingArea) else { return }
            removeTrackingArea(trackingArea)
        } else {
            guard !trackingAreas.contains(trackingArea) else { return }
            superAddTrackingArea(trackingArea)
        }
    }

    private var shouldSuspendWebKitMouseTracking: Bool {
        isWebKitMouseTrackingLoadSheddingActive || isTransientChromeMouseTrackingSuppressed
    }

    private func superAddTrackingArea(_ trackingArea: NSTrackingArea) {
        super.addTrackingArea(trackingArea)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let shouldSuppress = window.map(WebContentMouseTrackingShield.isActive(in:)) ?? false
        setTransientChromeMouseTrackingSuppressed(shouldSuppress)
    }

    func setTransientChromeMouseTrackingSuppressed(
        _ isSuppressed: Bool,
        shieldRects: [SumiTransientChromeInteractionShieldRect] = []
    ) {
        setTransientChromeInteractionShieldApplied(isSuppressed, shieldRects: shieldRects)

        guard isTransientChromeMouseTrackingSuppressed != isSuppressed else { return }

        isTransientChromeMouseTrackingSuppressed = isSuppressed
        if let trackingArea = webKitMouseTrackingArea {
            updateWebKitMouseTrackingArea(trackingArea)
        }

        if isSuppressed {
            owningTab?.onLinkHover?(nil)
        }
    }

    private func setTransientChromeInteractionShieldApplied(
        _ isApplied: Bool,
        shieldRects: [SumiTransientChromeInteractionShieldRect]
    ) {
        let activeShieldRects = isApplied ? shieldRects : []
        guard isTransientChromeInteractionShieldApplied != isApplied ||
              transientChromeInteractionShieldRects != activeShieldRects
        else { return }

        isTransientChromeInteractionShieldApplied = isApplied
        transientChromeInteractionShieldRects = activeShieldRects
        let script = SumiTransientChromeInteractionShieldUserScript.makeSetActiveSource(
            isApplied,
            clientPoint: currentClientPointForPageInteractionShield(),
            rects: activeShieldRects
        )
        evaluateJavaScript(script, completionHandler: nil)
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
        owningTab?.activate()
        interactionEventsPublisher.send(.mouseDown(event))
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isTransientChromeMouseTrackingSuppressed else {
            return
        }
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
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        interactionEventsPublisher.send(.scrollWheel(event))
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
        owningTab?.activate()
    }

    override var isInFullScreenMode: Bool {
        // WebKit element fullscreen is owned by WKWebView.fullscreenState, not by
        // AppKit's NSView fullscreen mode flag.
        sumiIsInFullscreenElementPresentation
    }

    override func makeTouchBar() -> NSTouchBar? {
        super.makeTouchBar() ?? makeClientMediaControlsTouchBarIfNeeded()
    }

    @objc(_addMediaPlaybackControlsView:)
    func addMediaPlaybackControlsView(_ mediaControlsView: AnyObject) {
        guard let controlsView = mediaControlsView as? NSView else { return }
        webKitClientMediaControlsView = controlsView
        clearClientMediaControlsCache()
        touchBar = makeClientMediaControlsTouchBarIfNeeded()
    }

    @objc(_removeMediaPlaybackControlsView)
    func removeMediaPlaybackControlsView() {
        webKitClientMediaControlsView = nil
        clearClientMediaControlsCache()
        touchBar = nil
    }

    private func clearClientMediaControlsCache() {
        webKitClientMediaControlsTouchBar = nil
        webKitClientMediaControlsProvider = nil
    }

    private func makeClientMediaControlsTouchBarIfNeeded() -> NSTouchBar? {
        guard let controlsView = webKitClientMediaControlsView else { return nil }
        if let touchBar = webKitClientMediaControlsTouchBar {
            return touchBar
        }

        // After element fullscreen WebKit asks the client to host its media controls view.
        // Prefer rebuilding AVKit's normal provider so the post-fullscreen bar matches
        // the pre-fullscreen WebKit-owned layout exactly.
        guard let touchBar = makeProviderMediaControlsTouchBarIfPossible(from: controlsView) else {
            return nil
        }
        webKitClientMediaControlsTouchBar = touchBar
        return touchBar
    }

    private func makeProviderMediaControlsTouchBarIfPossible(from controlsView: NSView) -> NSTouchBar? {
        guard let providerClass = NSClassFromString("AVTouchBarPlaybackControlsProvider") as? NSObject.Type,
              let playbackControlsController = controlsView.value(forKey: "playbackControlsController")
        else {
            return nil
        }

        let provider = providerClass.init()
        provider.setValue(playbackControlsController, forKey: "playbackControlsController")
        guard let touchBar = provider.value(forKey: "touchBar") as? NSTouchBar else {
            return nil
        }

        webKitClientMediaControlsProvider = provider
        return touchBar
    }

    override func mouseUp(with event: NSEvent) {
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

@MainActor
extension WKWebView {
    private enum SumiFullscreenSelector {
        static let fullScreenPlaceholderView = NSSelectorFromString("_fullScreenPlaceholderView")
    }

    var sumiIsInFullscreenElementPresentation: Bool {
        fullscreenState != .notInFullscreen
    }

    var sumiFullscreenPlaceholderView: NSView? {
        guard responds(to: SumiFullscreenSelector.fullScreenPlaceholderView) else {
            return nil
        }
        return value(forKey: NSStringFromSelector(SumiFullscreenSelector.fullScreenPlaceholderView)) as? NSView
    }

    var sumiTabContentView: NSView {
        sumiFullscreenPlaceholderView ?? self
    }

    var sumiFullscreenWindowController: NSWindowController? {
        guard let windowController = window?.windowController,
              windowController.className.contains("FullScreen")
        else {
            return nil
        }
        return windowController
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
