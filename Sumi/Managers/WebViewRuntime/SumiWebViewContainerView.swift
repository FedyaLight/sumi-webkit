import AppKit
import WebKit
import SumiWebRuntime

@MainActor
final class HostedWebViewPresentationObservation {
    private var cancellation: (() -> Void)?

    init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation?()
        cancellation = nil
    }

    isolated deinit {
        cancellation?()
    }
}

@MainActor
final class SumiWebViewContainerView: NSView, WebRuntimePromotedHost {
    let tabID: UUID
    let webView: WKWebView

    private var viewportCornerRadii: ChromeCornerRadii = .uniform(0)
    private var preservesDisplayedContentOnNextRemoval = false
    private let overlayScrollChrome = WebContentOverlayScrollChrome()
    private var readerPresentationSession: ReaderPresentationSession?
    private var presentationObservers: [UUID: (WKWebView) -> Void] = [:]

    override var constraints: [NSLayoutConstraint] { [] }

    init(tabID: UUID, webView: WKWebView) {
        self.tabID = tabID
        self.webView = webView
        super.init(frame: .zero)

        configure(webView: webView)
    }

    private func configure(webView: WKWebView) {
        let transferredReaderPresentation = webView.sumiReaderPresentationHost?
            .takeReaderPresentationForTransfer()

        autoresizingMask = [.width, .height]
        wantsLayer = true
        // Clips AppKit subviews (WKWebView) to the tab viewport. In-page extension overlays
        // render inside WKWebView's compositor and are not clipped by this AppKit flag.
        clipsToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]

        addDisplayedContent(webView.sumiFullscreenPresentation.tabContentView)
        overlayScrollChrome.install(in: self, webView: webView)
        if let focusable = webView as? FocusableWKWebView {
            focusable.overlayScrollChrome = overlayScrollChrome
        }
        if let transferredReaderPresentation {
            installReaderPresentation(transferredReaderPresentation)
        }
        updateViewportMask()
        recordInlineUIContainerClippingIfNeeded()
    }

    func setBrowserContentViewport(geometry: BrowserChromeGeometry) {
        guard viewportCornerRadii != geometry.contentCornerRadii else { return }

        viewportCornerRadii = geometry.contentCornerRadii

        updateViewportMask()
        needsLayout = true
    }

    func attachDisplayedContentIfNeeded() {
        let displayedView = webView.sumiFullscreenPresentation.tabContentView
        frameDisplayedContent(displayedView)
        for subview in subviews where subview !== displayedView {
            // Keep the AppKit overlay scroll indicator; only strip stray hosts.
            if subview === overlayScrollChrome.indicatorHostingView {
                continue
            }
            if subview === readerPresentationSession?.webView {
                continue
            }
            subview.removeFromSuperview()
        }
        if displayedView.superview !== self {
            addDisplayedContent(displayedView)
        }
        overlayScrollChrome.ensureIndicatorAboveContent()
        ensureReaderPresentationAboveContent()
        recenterFullscreenPlaceholderLabelIfNeeded(displayedView)
    }

    @discardableResult
    func presentReader(
        html: String,
        sourceDocument: SumiReaderSourceDocument
    ) -> Bool {
        guard sourceDocument.webView === webView,
              sourceDocument.isCurrent else {
            return false
        }

        dismissReader()
        guard let session = ReaderPresentationSession(
            sourceDocument: sourceDocument
        ) else { return false }
        session.webView.pageZoom = webView.pageZoom
        installReaderPresentation(session)
        session.load(html)
        return true
    }

    func dismissReader() {
        guard let readerPresentationSession else { return }
        let readerHadFocus = firstResponderIsInside(
            readerPresentationSession.webView
        )
        let presentationWindow = readerPresentationSession.webView.window
        readerPresentationSession.invalidate()
        (webView as? FocusableWKWebView)?.resetPageInteractionState()
        let ownsCanonicalContent = webView.sumiFullscreenPresentation
            .tabContentView.superview === self
        readerPresentationSession.webView.removeFromSuperview()
        readerPresentationSession.detach(from: self)
        self.readerPresentationSession = nil
        if ownsCanonicalContent {
            webView.pageZoom = readerPresentationSession.webView.pageZoom
            webView.sumiFullscreenPresentation.tabContentView.isHidden = false
        }
        overlayScrollChrome.refreshGeometry(revealIfChanged: false)
        notifyActivePresentationChanged()
        if readerHadFocus,
           let presentationWindow,
           webView.window === presentationWindow,
           !webView.isHidden {
            presentationWindow.makeFirstResponder(webView)
        }
    }

    /// The WebView that owns presentation-scoped interaction in this host.
    /// Navigation, lifecycle, permissions and history continue to use `webView`.
    var activePresentationWebView: WKWebView {
        readerPresentationSession?.webView ?? webView
    }

    func observeActivePresentationWebView(
        _ observer: @escaping (WKWebView) -> Void
    ) -> HostedWebViewPresentationObservation {
        let id = UUID()
        presentationObservers[id] = observer
        observer(activePresentationWebView)
        return HostedWebViewPresentationObservation { [weak self] in
            self?.presentationObservers.removeValue(forKey: id)
        }
    }

    func hasReaderPresentation(
        matching documentLease: TabMainFrameDocumentLease? = nil
    ) -> Bool {
        guard let readerPresentationSession else { return false }
        return documentLease.map {
            $0 == readerPresentationSession.sourceDocumentLease
        } ?? true
    }

    func invalidateReaderPresentation(
        unless documentLease: TabMainFrameDocumentLease?
    ) {
        guard let readerPresentationSession,
              documentLease != readerPresentationSession.sourceDocumentLease else {
            return
        }
        dismissReader()
    }

    /// WebKit centres the "exit full screen" label for the fullscreen screen's
    /// dimensions and never re-centres it once the placeholder is hosted at the
    /// tab's (smaller) content size, stranding the label in a corner. The label's
    /// autoresizing mask keeps whatever margins it currently has, so a one-time
    /// re-centre against the live bounds makes it stay centred on later resizes.
    private func recenterFullscreenPlaceholderLabelIfNeeded(_ displayedView: NSView) {
        guard displayedView !== webView,
              let label = displayedView.sumiFirstDescendant(ofType: NSTextField.self),
              let container = label.superview
        else {
            return
        }
        let centeredX = ((container.bounds.width - label.frame.width) / 2).rounded()
        let centeredY = ((container.bounds.height - label.frame.height) / 2).rounded()
        guard abs(label.frame.origin.x - centeredX) > 1
            || abs(label.frame.origin.y - centeredY) > 1
        else {
            return
        }
        label.setFrameOrigin(NSPoint(x: centeredX, y: centeredY))
    }

    func prepareForSuperviewTransferPreservingDisplayedContent() {
        preservesDisplayedContentOnNextRemoval = true
    }

    private func addDisplayedContent(_ displayedView: NSView) {
        frameDisplayedContent(displayedView)
        addSubview(displayedView)
    }

    private func installReaderPresentation(_ session: ReaderPresentationSession) {
        let canonicalHadFocus = firstResponderIsInside(webView)
        let presentationWindow = webView.window
        (webView as? FocusableWKWebView)?.resetPageInteractionState()
        readerPresentationSession = session
        session.attach(to: self)
        session.webView.frame = bounds
        session.webView.autoresizingMask = [.width, .height]
        webView.sumiFullscreenPresentation.tabContentView.isHidden = true
        addSubview(session.webView)
        overlayScrollChrome.hideImmediately()
        notifyActivePresentationChanged()
        if canonicalHadFocus,
           let presentationWindow,
           session.webView.window === presentationWindow {
            presentationWindow.makeFirstResponder(session.webView)
        }
    }

    private func takeReaderPresentationForTransfer() -> ReaderPresentationSession? {
        guard let session = readerPresentationSession else { return nil }
        (webView as? FocusableWKWebView)?.resetPageInteractionState()
        session.webView.removeFromSuperview()
        session.detach(from: self)
        readerPresentationSession = nil
        return session
    }

    private func notifyActivePresentationChanged() {
        let activeWebView = activePresentationWebView
        for observer in presentationObservers.values {
            observer(activeWebView)
        }
    }

    private func firstResponderIsInside(_ view: NSView) -> Bool {
        guard let firstResponder = view.window?.firstResponder else {
            return false
        }
        if firstResponder === view { return true }
        guard let responderView = firstResponder as? NSView else {
            return false
        }
        return responderView.isDescendant(of: view)
    }

    private func frameDisplayedContent(_ displayedView: NSView) {
        displayedView.frame = bounds
        displayedView.autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let displayedView = webView.sumiFullscreenPresentation.tabContentView
        displayedView.frame = bounds
        readerPresentationSession?.webView.frame = bounds
        recenterFullscreenPlaceholderLabelIfNeeded(displayedView)
        overlayScrollChrome.layoutIndicator()
        updateViewportMask()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            overlayScrollChrome.hideImmediately()
        } else {
            overlayScrollChrome.refreshGeometry(revealIfChanged: false)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            dismissReader()
            if let focusable = webView as? FocusableWKWebView,
               focusable.overlayScrollChrome === overlayScrollChrome {
                focusable.overlayScrollChrome = nil
            }
            overlayScrollChrome.uninstall()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsPointInsideRoundedViewport(point) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func removeFromSuperview() {
        if preservesDisplayedContentOnNextRemoval {
            preservesDisplayedContentOnNextRemoval = false
        } else {
            let displayedContent = webView.sumiFullscreenPresentation.tabContentView
            if displayedContent.superview === self {
                dismissReader()
                displayedContent.removeFromSuperview()
            }
        }
        super.removeFromSuperview()
    }

    private func recordInlineUIContainerClippingIfNeeded() {
        SafariExtensionAutofillFillDiagnostics.recordAppKitContainerClipping(
            clipsToBounds: clipsToBounds,
            masksToBounds: layer?.masksToBounds == true,
            inRoundedViewportContainer: clampedViewportCornerRadii.maxRadius > 0
        )
    }

    private func ensureReaderPresentationAboveContent() {
        guard let readerWebView = readerPresentationSession?.webView,
              readerWebView.superview === self else { return }
        addSubview(readerWebView, positioned: .above, relativeTo: nil)
    }

    private func updateViewportMask() {
        guard let layer else { return }

        let radii = clampedViewportCornerRadii
        let maxRadius = radii.maxRadius
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsScale = scale
        layer.masksToBounds = maxRadius > 0
        layer.cornerRadius = maxRadius
        layer.maskedCorners = radii.caCornerMask
        if #available(macOS 10.15, *) {
            layer.cornerCurve = .continuous
        }
        CATransaction.commit()
    }

    private func containsPointInsideRoundedViewport(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }

        let radii = clampedViewportCornerRadii
        guard radii.maxRadius > 0 else { return true }

        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY

        // AppKit content layers default to isFlipped == false → Core Animation
        // y-up, so visually-top corners live at maxY. A point outside every
        // corner zone is inside the viewport; a point inside a corner zone must
        // also lie within that corner's quarter-circle. A zero-radius corner
        // never enters its zone (the bound check is strict against the edge),
        // so square corners never clip pointer hits.
        func insideQuarterCircle(centerX: CGFloat, centerY: CGFloat, radius: CGFloat) -> Bool {
            let dx = point.x - centerX
            let dy = point.y - centerY
            return dx * dx + dy * dy <= radius * radius
        }

        if point.x < minX + radii.topLeading && point.y > maxY - radii.topLeading {
            return insideQuarterCircle(
                centerX: minX + radii.topLeading,
                centerY: maxY - radii.topLeading,
                radius: radii.topLeading
            )
        }
        if point.x > maxX - radii.topTrailing && point.y > maxY - radii.topTrailing {
            return insideQuarterCircle(
                centerX: maxX - radii.topTrailing,
                centerY: maxY - radii.topTrailing,
                radius: radii.topTrailing
            )
        }
        if point.x < minX + radii.bottomLeading && point.y < minY + radii.bottomLeading {
            return insideQuarterCircle(
                centerX: minX + radii.bottomLeading,
                centerY: minY + radii.bottomLeading,
                radius: radii.bottomLeading
            )
        }
        if point.x > maxX - radii.bottomTrailing && point.y < minY + radii.bottomTrailing {
            return insideQuarterCircle(
                centerX: maxX - radii.bottomTrailing,
                centerY: minY + radii.bottomTrailing,
                radius: radii.bottomTrailing
            )
        }

        return true
    }

    /// `viewportCornerRadii` clamped so no radius exceeds the viewport's
    /// half-extents (matches the prior uniform clamping in `effectiveViewportCornerRadius`).
    private var clampedViewportCornerRadii: ChromeCornerRadii {
        let maxHorizontal = max(0, bounds.width / 2)
        let maxVertical = max(0, bounds.height / 2)
        func clamp(_ value: CGFloat) -> CGFloat {
            min(max(0, value), maxHorizontal, maxVertical)
        }
        return ChromeCornerRadii(
            topLeading: clamp(viewportCornerRadii.topLeading),
            topTrailing: clamp(viewportCornerRadii.topTrailing),
            bottomLeading: clamp(viewportCornerRadii.bottomLeading),
            bottomTrailing: clamp(viewportCornerRadii.bottomTrailing)
        )
    }
}

private extension NSView {
    /// Depth-first search for the first descendant of the given type.
    func sumiFirstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }
            if let match = subview.sumiFirstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}

@MainActor
extension WKWebView {
    var sumiReaderPresentationHost: SumiWebViewContainerView? {
        var candidate = superview
        while let view = candidate {
            if let host = view as? SumiWebViewContainerView,
               host.webView === self {
                return host
            }
            candidate = view.superview
        }
        return nil
    }

    /// Presentation-only command target. It intentionally does not participate
    /// in Tab navigation or WebKit lifecycle authority.
    var sumiActivePresentationWebView: WKWebView {
        sumiReaderPresentationHost?.activePresentationWebView ?? self
    }
}
