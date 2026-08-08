import AppKit
import SumiWebRuntime
import WebKit

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
    private var retainedWebView: WKWebView?

    var webView: WKWebView {
        guard let retainedWebView else {
            preconditionFailure("An evicted WebView host has no presentation target")
        }
        return retainedWebView
    }

    private let overlayScrollChrome = WebContentOverlayScrollChrome()
    private var readerPresentationSession: ReaderPresentationSession?
    private var certificateTrustWarningView: CertificateTrustWarningView?
    private var presentationObservers: [UUID: (WKWebView) -> Void] = [:]
    private var runtimeEvictionHandler: ((SumiWebViewContainerView) -> Void)?

    override var constraints: [NSLayoutConstraint] { [] }

    override func keyDown(with event: NSEvent) {
        let commandModifiers = event.modifierFlags.intersection([
            .command, .control, .option,
        ])
        guard commandModifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }
        // WebKit and its page responders have already declined this ordinary
        // key. End the page-local responder path without a system beep.
    }

    init(tabID: UUID, webView: WKWebView) {
        self.tabID = tabID
        retainedWebView = webView
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
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]

        addDisplayedContent(webView)
        overlayScrollChrome.install(in: self, webView: webView)
        if let focusable = webView as? FocusableWKWebView {
            focusable.overlayScrollChrome = overlayScrollChrome
        }
        if let transferredReaderPresentation {
            installReaderPresentation(transferredReaderPresentation)
        }
        recordInlineUIContainerClippingIfNeeded()
    }

    func attachDisplayedContentIfNeeded() {
        if webView.superview === self {
            frameDisplayedContent(webView)
        } else if webView.superview == nil {
            addDisplayedContent(webView)
        }
        overlayScrollChrome.ensureIndicatorAboveContent()
        ensureReaderPresentationAboveContent()
        ensureCertificateTrustWarningAboveContent()
    }

    @discardableResult
    func presentCertificateTrustWarning(
        _ session: CertificateTrustWarningSession
    ) -> Bool {
        guard certificateTrustWarningView == nil else { return false }
        let warningView = CertificateTrustWarningView(session: session) { [weak self] warningView in
            guard self?.certificateTrustWarningView === warningView else { return }
            self?.certificateTrustWarningView = nil
        }
        warningView.translatesAutoresizingMaskIntoConstraints = false
        certificateTrustWarningView = warningView
        addSubview(warningView, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            warningView.leadingAnchor.constraint(equalTo: leadingAnchor),
            warningView.trailingAnchor.constraint(equalTo: trailingAnchor),
            warningView.topAnchor.constraint(equalTo: topAnchor),
            warningView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        return true
    }

    func dismissCertificateTrustWarning() {
        guard let warningView = certificateTrustWarningView else { return }
        certificateTrustWarningView = nil
        warningView.removeFromSuperview()
        warningView.session.cancel()
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
        let ownsCanonicalContent = webView.superview === self
        readerPresentationSession.webView.removeFromSuperview()
        readerPresentationSession.detach(from: self)
        self.readerPresentationSession = nil
        if ownsCanonicalContent {
            webView.pageZoom = readerPresentationSession.webView.pageZoom
            webView.isHidden = false
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

    func setRuntimeEvictionHandler(
        _ handler: @escaping (SumiWebViewContainerView) -> Void
    ) {
        runtimeEvictionHandler = handler
    }

    func evictFromRuntime() {
        runtimeEvictionHandler?(self)
        runtimeEvictionHandler = nil
        dismissCertificateTrustWarning()
        dismissReader()
        removeFromSuperview()
        if let retainedWebView, retainedWebView.superview === self {
            retainedWebView.removeFromSuperview()
        }
        if let focusable = retainedWebView as? FocusableWKWebView,
           focusable.overlayScrollChrome === overlayScrollChrome {
            focusable.overlayScrollChrome = nil
        }
        overlayScrollChrome.uninstall()
        retainedWebView = nil
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
        webView.isHidden = true
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
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard let webView = retainedWebView else { return }
        if webView.superview === self {
            webView.frame = bounds
        }
        readerPresentationSession?.webView.frame = bounds
        overlayScrollChrome.layoutIndicator()
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
            dismissCertificateTrustWarning()
            dismissReader()
            if let focusable = retainedWebView as? FocusableWKWebView,
               focusable.overlayScrollChrome === overlayScrollChrome {
                focusable.overlayScrollChrome = nil
            }
            overlayScrollChrome.uninstall()
        }
    }

    private func recordInlineUIContainerClippingIfNeeded() {
        SafariExtensionAutofillFillDiagnostics.recordAppKitContainerClipping(
            clipsToBounds: clipsToBounds,
            masksToBounds: layer?.masksToBounds == true
        )
    }

    private func ensureReaderPresentationAboveContent() {
        guard let readerWebView = readerPresentationSession?.webView,
              readerWebView.superview === self else { return }
        addSubview(readerWebView, positioned: .above, relativeTo: nil)
    }

    private func ensureCertificateTrustWarningAboveContent() {
        guard let certificateTrustWarningView,
              certificateTrustWarningView.superview === self else { return }
        addSubview(certificateTrustWarningView, positioned: .above, relativeTo: nil)
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
