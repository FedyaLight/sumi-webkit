//
//  SumiFolderGlyphView.swift
//  Sumi
//
//

import SwiftUI

struct SumiFolderGlyphPalette {
    let backFill: Color
    let frontFill: Color
    let stroke: Color
    let iconForeground: Color
    let backOverlayTop: Color
    let backOverlayBottom: Color
    let frontOverlayTop: Color
    let frontOverlayBottom: Color
}

enum SumiFolderGlyphShellState: Equatable {
    case closed
    case open
}

struct SumiFolderGlyphPresentationState: Equatable {
    let shellState: SumiFolderGlyphShellState
    let isActive: Bool
    let bundledIconName: String?

    init(iconValue: String?, isOpen: Bool, hasActiveProjection: Bool) {
        shellState = isOpen ? .open : .closed
        isActive = !isOpen && hasActiveProjection

        switch SumiZenFolderIconCatalog.resolveFolderIcon(iconValue) {
        case .bundled(let name):
            bundledIconName = name
        case .none:
            bundledIconName = nil
        }
    }

    var isOpen: Bool {
        shellState == .open
    }

    var showsDots: Bool {
        isActive
    }

    var showsCustomIcon: Bool {
        bundledIconName != nil && !showsDots
    }
}

struct SumiFolderGlyphView: View {
    private static let shellAnimation = Animation.easeInOut(duration: 0.16)

    let presentation: SumiFolderGlyphPresentationState
    let palette: SumiFolderGlyphPalette

    @State private var renderedShellIsOpen: Bool?

    var body: some View {
        GeometryReader { geometry in
            let shellIsOpen = renderedShellIsOpen ?? presentation.isOpen
            let unitScale = min(
                geometry.size.width / SumiFolderGlyphMetrics.canvasDimension,
                geometry.size.height / SumiFolderGlyphMetrics.canvasDimension
            )
            let canvasSize = SumiFolderGlyphMetrics.canvasDimension * unitScale
            let originX = ((geometry.size.width - canvasSize) / 2) + (SumiFolderGlyphMetrics.baseOffset.width * unitScale)
            let originY = ((geometry.size.height - canvasSize) / 2) + (SumiFolderGlyphMetrics.baseOffset.height * unitScale)

            ZStack(alignment: .topLeading) {
                canvasLayer(scale: unitScale) {
                    backLayer(scale: unitScale)
                }
                .modifier(backTransform(scale: unitScale, isOpen: shellIsOpen))

                canvasLayer(scale: unitScale) {
                    frontLayer(scale: unitScale)
                }
                .modifier(frontTransform(scale: unitScale, isOpen: shellIsOpen))

                if presentation.showsCustomIcon {
                    canvasLayer(scale: unitScale) {
                        iconLayer(scale: unitScale)
                    }
                    .modifier(frontTransform(scale: unitScale, isOpen: shellIsOpen))
                    .transition(.identity)
                }

                if presentation.showsDots {
                    canvasLayer(scale: unitScale) {
                        dotsLayer(scale: unitScale)
                    }
                    .modifier(frontTransform(scale: unitScale, isOpen: shellIsOpen))
                    .transition(.identity)
                }
            }
            .frame(width: canvasSize, height: canvasSize, alignment: .topLeading)
            .offset(x: originX, y: originY)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contrast(1.25)
        .onAppear {
            renderedShellIsOpen = presentation.isOpen
        }
        .onChange(of: presentation.isOpen) { _, isOpen in
            updateRenderedShellState(isOpen)
        }
    }

    private func canvasLayer<Content: View>(
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topLeading) {
            content()
        }
        .frame(
            width: SumiFolderGlyphMetrics.canvasDimension * scale,
            height: SumiFolderGlyphMetrics.canvasDimension * scale,
            alignment: .topLeading
        )
    }

    private func backLayer(scale: CGFloat) -> some View {
        ZStack {
            SumiFolderBackShape()
                .fill(palette.backFill)

            SumiFolderBackShape()
                .fill(
                    LinearGradient(
                        colors: [palette.backOverlayTop, palette.backOverlayBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            SumiFolderBackShape()
                .stroke(palette.stroke, lineWidth: max(1, 1.5 * scale))
        }
    }

    private func frontLayer(scale: CGFloat) -> some View {
        let size = SumiFolderGlyphMetrics.frontSize.scaled(by: scale)
        let origin = SumiFolderGlyphMetrics.frontOrigin.scaled(by: scale)

        return ZStack {
            RoundedRectangle(
                cornerRadius: SumiFolderGlyphMetrics.frontCornerRadius * scale,
                style: .continuous
            )
            .fill(palette.frontFill)

            RoundedRectangle(
                cornerRadius: SumiFolderGlyphMetrics.frontCornerRadius * scale,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [palette.frontOverlayTop, palette.frontOverlayBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            RoundedRectangle(
                cornerRadius: SumiFolderGlyphMetrics.frontCornerRadius * scale,
                style: .continuous
            )
            .stroke(palette.stroke, lineWidth: max(1, 1.5 * scale))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .offset(x: origin.x, y: origin.y)
    }

    private func iconLayer(scale: CGFloat) -> some View {
        let iconSize = SumiFolderGlyphMetrics.iconDimension * scale
        let iconOrigin = SumiFolderGlyphMetrics.iconOrigin.scaled(by: scale)

        return Group {
            if let bundledIconName = presentation.bundledIconName {
                SumiZenBundledIconView(
                    image: SumiZenFolderIconCatalog.bundledFolderImage(named: bundledIconName),
                    size: iconSize,
                    tint: palette.iconForeground.opacity(0.96)
                )
                .frame(width: iconSize, height: iconSize)
                .offset(x: iconOrigin.x, y: iconOrigin.y)
            }
        }
    }

    private func dotsLayer(scale: CGFloat) -> some View {
        let dotSize = SumiFolderGlyphMetrics.dotDiameter * scale

        return ZStack(alignment: .topLeading) {
            ForEach(Array(SumiFolderGlyphMetrics.dotCenters.enumerated()), id: \.offset) { _, center in
                Circle()
                    .frame(width: dotSize, height: dotSize)
                    .offset(
                        x: (center.x - (SumiFolderGlyphMetrics.dotDiameter / 2)) * scale,
                        y: (center.y - (SumiFolderGlyphMetrics.dotDiameter / 2)) * scale
                    )
            }
        }
        .foregroundStyle(palette.iconForeground.opacity(0.94))
    }

    private func backTransform(scale: CGFloat, isOpen: Bool) -> SumiFolderElementTransform {
        elementTransform(
            xDegrees: isOpen ? SumiFolderGlyphMetrics.openSkewDegrees : 0,
            scale: isOpen ? SumiFolderGlyphMetrics.openScale : 1,
            offset: isOpen ? SumiFolderGlyphMetrics.backOpenOffset : .zero,
            unitScale: scale
        )
    }

    private func frontTransform(scale: CGFloat, isOpen: Bool) -> SumiFolderElementTransform {
        elementTransform(
            xDegrees: isOpen ? -SumiFolderGlyphMetrics.openSkewDegrees : 0,
            scale: isOpen ? SumiFolderGlyphMetrics.openScale : 1,
            offset: isOpen ? SumiFolderGlyphMetrics.frontOpenOffset : .zero,
            unitScale: scale
        )
    }

    private func updateRenderedShellState(_ isOpen: Bool) {
        let update = {
            renderedShellIsOpen = isOpen
        }

        withAnimation(Self.shellAnimation, update)
    }

    private func elementTransform(
        xDegrees: CGFloat,
        scale: CGFloat,
        offset: CGSize,
        unitScale: CGFloat
    ) -> SumiFolderElementTransform {
        SumiFolderElementTransform(
            xDegrees: xDegrees,
            scale: scale,
            offset: CGSize(width: offset.width * unitScale, height: offset.height * unitScale)
        )
    }
}

private enum SumiFolderGlyphMetrics {
    static let canvasDimension: CGFloat = 27
    static let baseOffset = CGSize(width: -1, height: -1)
    static let openSkewDegrees: CGFloat = 16
    static let openScale: CGFloat = 0.85
    static let backOpenOffset = CGSize(width: -4, height: 2)
    static let frontOpenOffset = CGSize(width: 8, height: 2)
    static let frontOrigin = CGPoint(x: 5.625, y: 9.625)
    static let frontSize = CGSize(width: 16.75, height: 12.75)
    static let frontCornerRadius: CGFloat = 2.375
    static let iconOrigin = CGPoint(x: 8.5, y: 10.5)
    static let iconDimension: CGFloat = 11
    static let dotDiameter: CGFloat = 2.5
    static let dotCenters: [CGPoint] = [
        CGPoint(x: 10, y: 16),
        CGPoint(x: 14, y: 16),
        CGPoint(x: 18, y: 16),
    ]
}

private struct SumiFolderElementTransform: ViewModifier {
    let xDegrees: CGFloat
    let scale: CGFloat
    let offset: CGSize

    func body(content: Content) -> some View {
        content
            .modifier(SkewEffect(xDegrees: xDegrees))
            .scaleEffect(scale)
            .offset(x: offset.width, y: offset.height)
    }
}

private extension CGPoint {
    func scaled(by scale: CGFloat) -> CGPoint {
        CGPoint(x: x * scale, y: y * scale)
    }
}

private extension CGSize {
    func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }
}

private struct SumiFolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 27
        let sy = rect.height / 27

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * sx, y: y * sy)
        }

        var path = Path()
        path.move(to: point(8, 5.625))
        path.addLine(to: point(11.9473, 5.625))
        path.addLine(to: point(13.4316, 6.14551))
        path.addLine(to: point(14.2881, 6.83105))
        path.addLine(to: point(16.5527, 7.625))
        path.addLine(to: point(20, 7.625))
        path.addQuadCurve(to: point(22.375, 10), control: point(22.375, 7.625))
        path.addLine(to: point(22.375, 20))
        path.addQuadCurve(to: point(20, 22.375), control: point(22.375, 22.375))
        path.addLine(to: point(8, 22.375))
        path.addQuadCurve(to: point(5.625, 20), control: point(5.625, 22.375))
        path.addLine(to: point(5.625, 8))
        path.addQuadCurve(to: point(8, 5.625), control: point(5.625, 5.625))
        path.closeSubpath()
        return path
    }
}

private struct SkewEffect: GeometryEffect {
    var xDegrees: CGFloat

    var animatableData: CGFloat {
        get { xDegrees }
        set { xDegrees = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        var transform = CGAffineTransform.identity
        transform.c = tan(xDegrees * .pi / 180)
        return ProjectionTransform(transform)
    }
}
