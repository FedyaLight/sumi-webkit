import AppKit
import WebKit

@MainActor
final class SumiWebViewContainerView: NSView {
    let tabID: UUID
    let webView: WKWebView

    private var viewportCornerRadius: CGFloat = 0
    private var preservesDisplayedContentOnNextRemoval = false

    override var constraints: [NSLayoutConstraint] { [] }

    init(tab: Tab, webView: WKWebView) {
        self.tabID = tab.id
        self.webView = webView
        super.init(frame: .zero)

        configure(webView: webView)
    }

    private func configure(webView: WKWebView) {
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

        addDisplayedContent(webView.sumiTabContentView)
        updateViewportMask()
        recordInlineUIContainerClippingIfNeeded()
    }

    func setBrowserContentViewport(geometry: BrowserChromeGeometry) {
        let radiusChanged = abs(viewportCornerRadius - geometry.contentRadius) > 0.000_1
        guard radiusChanged else { return }

        viewportCornerRadius = geometry.contentRadius

        updateViewportMask()
        needsLayout = true
    }

    func attachDisplayedContentIfNeeded() {
        let displayedView = webView.sumiTabContentView
        frameDisplayedContent(displayedView)
        for subview in subviews where subview !== displayedView {
            subview.removeFromSuperview()
        }
        guard displayedView.superview !== self else { return }
        addDisplayedContent(displayedView)
    }

    func prepareForSuperviewTransferPreservingDisplayedContent() {
        preservesDisplayedContentOnNextRemoval = true
    }

    private func addDisplayedContent(_ displayedView: NSView) {
        frameDisplayedContent(displayedView)
        addSubview(displayedView)
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
        webView.sumiTabContentView.frame = bounds
        updateViewportMask()
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
            webView.sumiTabContentView.removeFromSuperview()
        }
        super.removeFromSuperview()
    }

    private var effectiveViewportCornerRadius: CGFloat {
        min(
            max(0, viewportCornerRadius),
            max(0, bounds.width / 2),
            max(0, bounds.height / 2)
        )
    }

    private func recordInlineUIContainerClippingIfNeeded() {
        SafariExtensionAutofillFillDiagnostics.recordAppKitContainerClipping(
            clipsToBounds: clipsToBounds,
            masksToBounds: layer?.masksToBounds == true,
            inRoundedViewportContainer: effectiveViewportCornerRadius > 0
        )
    }

    private func updateViewportMask() {
        guard let layer else { return }

        let radius = effectiveViewportCornerRadius
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsScale = scale
        layer.masksToBounds = radius > 0
        layer.cornerRadius = radius
        if #available(macOS 10.15, *) {
            layer.cornerCurve = .continuous
        }
        CATransaction.commit()
    }

    private func containsPointInsideRoundedViewport(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }

        let radius = effectiveViewportCornerRadius
        guard radius > 0 else { return true }

        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY

        if point.x >= minX + radius && point.x <= maxX - radius {
            return true
        }

        if point.y >= minY + radius && point.y <= maxY - radius {
            return true
        }

        let center: NSPoint
        if point.x < minX + radius {
            center = point.y < minY + radius
                ? NSPoint(x: minX + radius, y: minY + radius)
                : NSPoint(x: minX + radius, y: maxY - radius)
        } else {
            center = point.y < minY + radius
                ? NSPoint(x: maxX - radius, y: minY + radius)
                : NSPoint(x: maxX - radius, y: maxY - radius)
        }

        let dx = point.x - center.x
        let dy = point.y - center.y
        return dx * dx + dy * dy <= radius * radius
    }

}
