import CoreGraphics

struct BrowserChromeGeometry: Equatable {
    /// Central seam for future manually calibrated adaptive browser viewport radii.
    /// This intentionally uses no system/private API and adds no macOS 26 numeric fallback yet.
    struct CornerMetrics: Equatable {
        static let `default` = CornerMetrics()

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

        func contentRadius(outerRadius: CGFloat, elementSeparation: CGFloat) -> CGFloat {
            max(
                minimumContentRadius,
                outerRadius - elementSeparation / 2
            )
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
            outerRadius: settings.resolvedCornerRadius(cornerMetrics.defaultOuterRadius),
            elementSeparation: cornerMetrics.elementSeparation,
            cornerMetrics: cornerMetrics
        )
    }
}
