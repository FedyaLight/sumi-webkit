import CoreGraphics
import QuartzCore

/// Per-corner radii for the browser content viewport.
///
/// Corners are named in screen space (`topLeading` is the visually top-left
/// corner), independent of any view's `isFlipped` state. Consumers map to the
/// appropriate coordinate convention (SwiftUI's y-down `RectangleCornerRadii`
/// or AppKit/Core Animation's y-up `CACornerMask`).
struct ChromeCornerRadii: Equatable, Sendable {
    var topLeading: CGFloat
    var topTrailing: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat

    /// Uniform radius applied to all four corners.
    static func uniform(_ radius: CGFloat) -> Self {
        ChromeCornerRadii(
            topLeading: radius,
            topTrailing: radius,
            bottomLeading: radius,
            bottomTrailing: radius
        )
    }

    /// Radius applied to the top corners only; bottom corners are square.
    static func topOnly(_ radius: CGFloat) -> Self {
        ChromeCornerRadii(
            topLeading: radius,
            topTrailing: radius,
            bottomLeading: 0,
            bottomTrailing: 0
        )
    }

    /// `true` when all four corners share the same radius.
    var isUniform: Bool {
        topLeading == topTrailing
            && topTrailing == bottomLeading
            && bottomLeading == bottomTrailing
    }

    /// The largest radius across the four corners.
    var maxRadius: CGFloat {
        max(topLeading, max(topTrailing, max(bottomLeading, bottomTrailing)))
    }

    /// Maps the radii to a `CACornerMask` for an AppKit-backed layer.
    ///
    /// Only corners with a non-zero radius are included. AppKit content layers
    /// default to `isFlipped == false` (Core Animation y-up, origin bottom-left),
    /// so visually-top corners correspond to the `MaxY` mask constants.
    var caCornerMask: CACornerMask {
        var mask: CACornerMask = []
        if topLeading > 0    { mask.insert(.layerMinXMaxYCorner) }
        if topTrailing > 0   { mask.insert(.layerMaxXMaxYCorner) }
        if bottomLeading > 0 { mask.insert(.layerMinXMinYCorner) }
        if bottomTrailing > 0 { mask.insert(.layerMaxXMinYCorner) }
        return mask
    }
}

/// Per-edge insets surrounding the browser content viewport.
struct ChromeEdgeInsets: Equatable, Sendable {
    var top: CGFloat
    var bottom: CGFloat
    var leading: CGFloat
    var trailing: CGFloat

    /// Uniform inset applied to all four edges.
    static func uniform(_ inset: CGFloat) -> Self {
        ChromeEdgeInsets(top: inset, bottom: inset, leading: inset, trailing: inset)
    }

    /// Inset applied to the top edge only; the other edges are flush (zero).
    static func topOnly(_ inset: CGFloat) -> Self {
        ChromeEdgeInsets(top: inset, bottom: 0, leading: 0, trailing: 0)
    }
}

struct BrowserChromeGeometry: Equatable {
    /// Central seam for manually calibrated browser viewport radii.
    ///
    /// No private API is used here: platform values are conservative calibrated
    /// fallbacks, not claimed system window radii. Future visual tuning belongs
    /// in this metrics seam so viewport/cutout consumers stay unchanged.
    struct CornerMetrics: Equatable {
        static var `default`: CornerMetrics {
            platformDefault(isMacOSTahoeOrNewer: isMacOSTahoeOrNewer)
        }

        static let sequoiaFallback = CornerMetrics()
        // macOS 26 Tahoe: conservative visual preset, not a probed system radius.
        static let tahoeFallback = CornerMetrics(defaultOuterRadius: 14)

        let elementSeparation: CGFloat
        let defaultOuterRadius: CGFloat
        let minimumContentRadius: CGFloat

        init(
            elementSeparation: CGFloat = 8,
            defaultOuterRadius: CGFloat = 7,
            minimumContentRadius: CGFloat = 5
        ) {
            self.elementSeparation = elementSeparation
            self.defaultOuterRadius = defaultOuterRadius
            self.minimumContentRadius = minimumContentRadius
        }

        static func platformDefault(isMacOSTahoeOrNewer: Bool) -> CornerMetrics {
            isMacOSTahoeOrNewer ? tahoeFallback : sequoiaFallback
        }

        func outerRadius(themeBorderRadius: Int) -> CGFloat {
            themeBorderRadius == -1 ? defaultOuterRadius : CGFloat(themeBorderRadius)
        }

        func contentRadius(outerRadius: CGFloat, elementSeparation: CGFloat) -> CGFloat {
            max(
                minimumContentRadius,
                outerRadius - elementSeparation / 2
            )
        }

        private static var isMacOSTahoeOrNewer: Bool {
            if #available(macOS 26.0, *) {
                return true
            } else {
                return false
            }
        }
    }

    static let elementSeparation: CGFloat = CornerMetrics.default.elementSeparation
    static let defaultOuterRadius: CGFloat = CornerMetrics.default.defaultOuterRadius
    static let minimumContentRadius: CGFloat = CornerMetrics.default.minimumContentRadius

    let outerRadius: CGFloat
    let elementSeparation: CGFloat
    /// Uniform content corner radius.
    ///
    /// Kept as the canonical single-radius value for legacy consumers (e.g.
    /// Glance overlay) and existing tests. Per-corner rounding is expressed via
    /// `contentCornerRadii`; in the uniform case this equals `maxRadius`.
    let contentRadius: CGFloat
    let contentEdgeInsets: ChromeEdgeInsets
    let contentCornerRadii: ChromeCornerRadii

    init(
        outerRadius: CGFloat = Self.defaultOuterRadius,
        elementSeparation: CGFloat = Self.elementSeparation,
        cornerMetrics: CornerMetrics = .default
    ) {
        self.outerRadius = max(0, outerRadius)
        self.elementSeparation = max(0, elementSeparation)
        let resolvedContentRadius = cornerMetrics.contentRadius(
            outerRadius: self.outerRadius,
            elementSeparation: self.elementSeparation
        )
        self.contentRadius = resolvedContentRadius
        self.contentEdgeInsets = .uniform(self.elementSeparation)
        self.contentCornerRadii = .uniform(resolvedContentRadius)
    }

    @MainActor
    init(settings: SumiSettingsService) {
        let cornerMetrics = CornerMetrics.default
        let outerRadius = cornerMetrics.outerRadius(themeBorderRadius: settings.themeBorderRadius)
        let elementSeparation = cornerMetrics.elementSeparation
        let contentRadius = cornerMetrics.contentRadius(
            outerRadius: outerRadius,
            elementSeparation: elementSeparation
        )
        self.outerRadius = max(0, outerRadius)
        self.elementSeparation = max(0, elementSeparation)
        self.contentRadius = contentRadius
        self.contentEdgeInsets = settings.framelessChrome
            ? .topOnly(elementSeparation)
            : .uniform(elementSeparation)
        self.contentCornerRadii = settings.framelessChrome
            ? .topOnly(contentRadius)
            : .uniform(contentRadius)
    }
}
