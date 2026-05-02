import AppKit
import Combine
import WebKit
import ObjectiveC.runtime

enum SumiWebViewInteractionEvent {
    case mouseDown(NSEvent)
    case middleMouseDown(NSEvent)
    case keyDown(NSEvent)
    case scrollWheel(NSEvent)

    var event: NSEvent {
        switch self {
        case .mouseDown(let event),
             .middleMouseDown(let event),
             .keyDown(let event),
             .scrollWheel(let event):
            return event
        }
    }
}

@MainActor
final class FocusableWKWebView: WKWebView {
    weak var owningTab: Tab?
    let interactionEventsPublisher = PassthroughSubject<SumiWebViewInteractionEvent, Never>()

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        _ = Self.swizzleImmediateActionAnimationControllerOnce
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        _ = Self.swizzleImmediateActionAnimationControllerOnce
        super.init(coder: coder)
    }

    override func mouseDown(with event: NSEvent) {
        owningTab?.setClickModifierFlags(event.modifierFlags)
        owningTab?.recordPopupUserActivation(event, kind: "mouseDown")

        super.mouseDown(with: event)
        owningTab?.activate()
        interactionEventsPublisher.send(.mouseDown(event))
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
        sumiIsInFullscreenElementPresentation
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
