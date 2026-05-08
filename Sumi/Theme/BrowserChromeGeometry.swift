import CoreGraphics

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
    let contentRadius: CGFloat

    init(
        outerRadius: CGFloat = Self.defaultOuterRadius,
        elementSeparation: CGFloat = Self.elementSeparation,
        cornerMetrics: CornerMetrics = .default
    ) {
        self.outerRadius = max(0, outerRadius)
        self.elementSeparation = max(0, elementSeparation)
        self.contentRadius = cornerMetrics.contentRadius(
            outerRadius: self.outerRadius,
            elementSeparation: self.elementSeparation
        )
    }

    @MainActor
    init(settings: SumiSettingsService) {
        let cornerMetrics = CornerMetrics.default
        self.init(
            outerRadius: cornerMetrics.outerRadius(themeBorderRadius: settings.themeBorderRadius),
            elementSeparation: cornerMetrics.elementSeparation,
            cornerMetrics: cornerMetrics
        )
    }
}
