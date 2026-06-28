import AppKit
import WebKit

@MainActor
final class SumiWebViewContainerView: NSView {
    let tabID: UUID
    let webView: WKWebView

    private var viewportCornerRadii: ChromeCornerRadii = .uniform(0)
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
        guard viewportCornerRadii != geometry.contentCornerRadii else { return }

        viewportCornerRadii = geometry.contentCornerRadii

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

    private func recordInlineUIContainerClippingIfNeeded() {
        SafariExtensionAutofillFillDiagnostics.recordAppKitContainerClipping(
            clipsToBounds: clipsToBounds,
            masksToBounds: layer?.masksToBounds == true,
            inRoundedViewportContainer: clampedViewportCornerRadii.maxRadius > 0
        )
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
