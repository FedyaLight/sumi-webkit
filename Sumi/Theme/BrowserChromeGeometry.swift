import CoreGraphics

struct BrowserChromeGeometry: Equatable {
    static let elementSeparation: CGFloat = 8
    static let defaultOuterRadius: CGFloat = 7
    static let minimumContentRadius: CGFloat = 5

    let outerRadius: CGFloat
    let elementSeparation: CGFloat
    let contentRadius: CGFloat

    init(
        outerRadius: CGFloat = Self.defaultOuterRadius,
        elementSeparation: CGFloat = Self.elementSeparation
    ) {
        self.outerRadius = max(0, outerRadius)
        self.elementSeparation = max(0, elementSeparation)
        self.contentRadius = max(
            Self.minimumContentRadius,
            self.outerRadius - self.elementSeparation / 2
        )
    }

    @MainActor
    init(settings: SumiSettingsService) {
        self.init(
            outerRadius: settings.resolvedCornerRadius(Self.defaultOuterRadius),
            elementSeparation: Self.elementSeparation
        )
    }
}
