import CoreGraphics

/// The two rounded-corner shapes supported by the browser content viewport.
///
/// Callers can select a uniform or top-only shape. Keeping arbitrary per-corner
/// values out of the interface prevents renderers from promising geometry that
/// Core Animation's single `cornerRadius` cannot reproduce.
struct ChromeCornerRadii: Equatable, Sendable {
    private enum RoundedCorners: Equatable, Sendable {
        case all
        case top
    }

    private let radius: CGFloat
    private let roundedCorners: RoundedCorners

    private init(radius: CGFloat, roundedCorners: RoundedCorners) {
        self.radius = max(0, radius)
        self.roundedCorners = roundedCorners
    }

    /// Uniform radius applied to all four corners.
    static func uniform(_ radius: CGFloat) -> Self {
        ChromeCornerRadii(radius: radius, roundedCorners: .all)
    }

    /// Radius applied to the top corners only; bottom corners are square.
    static func topOnly(_ radius: CGFloat) -> Self {
        ChromeCornerRadii(radius: radius, roundedCorners: .top)
    }

    var topLeading: CGFloat { radius }
    var topTrailing: CGFloat { radius }
    var bottomLeading: CGFloat { roundedCorners == .all ? radius : 0 }
    var bottomTrailing: CGFloat { roundedCorners == .all ? radius : 0 }

    var isUniform: Bool {
        roundedCorners == .all || radius == 0
    }

    var maxRadius: CGFloat {
        radius
    }

    func clamped(to size: CGSize) -> Self {
        let maximum = max(0, min(size.width, size.height) / 2)
        return ChromeCornerRadii(
            radius: min(radius, maximum),
            roundedCorners: roundedCorners
        )
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
        self.contentEdgeInsets = settings.framelessChrome
            ? .topOnly(elementSeparation)
            : .uniform(elementSeparation)
        self.contentCornerRadii = settings.framelessChrome
            ? .topOnly(contentRadius)
            : .uniform(contentRadius)
    }
}
