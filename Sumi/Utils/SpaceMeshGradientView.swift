import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - SpaceMeshGradientView
// SwiftUI-native workspace gradient. This replaces the inherited stitchable
// Metal shader path with MeshGradient on the macOS 15+ deployment target.
@MainActor
struct SpaceMeshGradientView: View {
    var gradient: WorkspaceResolvedGradient
    var primaryStopID: UUID? = nil

    var body: some View {
        let stops = resolvedStops()

        if stops.count <= 1 {
            Self.color(for: stops.first)
        } else if stops.count == 2 {
            MeshGradient(
                width: 2,
                height: 2,
                points: Self.twoColorPoints(),
                colors: Self.twoColorColors(stops: stops, angle: gradient.angle)
            )
        } else {
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.threeColorPoints(angle: gradient.angle),
                colors: Self.threeColorColors(stops: stops)
            )
        }
    }

    private func resolvedStops() -> [WorkspaceGradientStop] {
        var stops = gradient.sortedStops
        if stops.isEmpty {
            stops = WorkspaceResolvedGradient.default.sortedStops
        }
        if let primaryStopID, let index = stops.firstIndex(where: { $0.id == primaryStopID }) {
            let primary = stops.remove(at: index)
            stops.insert(primary, at: 0)
        }
        return Array(stops.prefix(WorkspaceResolvedGradient.maxStops))
    }

    private static func twoColorPoints() -> [SIMD2<Float>] {
        [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 1),
            SIMD2<Float>(1, 1)
        ]
    }

    private static func twoColorColors(stops: [WorkspaceGradientStop], angle: Double) -> [Color] {
        let start = color(for: stops[0])
        let end = color(for: stops[1])
        let theta = Angle(degrees: angle).radians
        let direction = SIMD2<Double>(cos(theta), sin(theta))
        let corners = [
            SIMD2<Double>(0, 0),
            SIMD2<Double>(1, 0),
            SIMD2<Double>(0, 1),
            SIMD2<Double>(1, 1)
        ]
        let center = SIMD2<Double>(0.5, 0.5)
        let projections = corners.map { corner in
            let offset = corner - center
            return offset.x * direction.x + offset.y * direction.y
        }
        let minProjection = projections.min() ?? -1
        let maxProjection = projections.max() ?? 1
        let span = max(maxProjection - minProjection, 0.0001)

        return projections.map { projection in
            blend(start, end, amount: (projection - minProjection) / span)
        }
    }

    private static func threeColorPoints(angle: Double) -> [SIMD2<Float>] {
        let theta = Angle(degrees: angle).radians
        let driftX = Float(cos(theta) * 0.05)
        let driftY = Float(sin(theta) * 0.05)

        return [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(0.5 + driftX * 0.5, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.5 + driftY * 0.5),
            SIMD2<Float>(0.5 + driftX, 0.5 + driftY),
            SIMD2<Float>(1, 0.5 - driftY * 0.5),
            SIMD2<Float>(0, 1),
            SIMD2<Float>(0.5 - driftX * 0.5, 1),
            SIMD2<Float>(1, 1)
        ].map { point in
            SIMD2<Float>(
                min(max(point.x, 0), 1),
                min(max(point.y, 0), 1)
            )
        }
    }

    private static func threeColorColors(stops: [WorkspaceGradientStop]) -> [Color] {
        let first = color(for: stops[0])
        let second = color(for: stops[1])
        let third = color(for: stops[2])

        return [
            first,
            blend(first, second, amount: 0.5),
            second,
            blend(first, third, amount: 0.45),
            blend(blend(first, second, amount: 0.5), third, amount: 0.35),
            blend(second, third, amount: 0.45),
            third,
            blend(third, first, amount: 0.25),
            blend(third, second, amount: 0.35)
        ]
    }

    private static func color(for stop: WorkspaceGradientStop?) -> Color {
        guard let stop else {
            return Color(hex: WorkspaceResolvedGradient.default.primaryColorHex)
        }
        #if canImport(AppKit)
        return Color(nsColor: cachedSRGBColor(for: stop.hex))
        #else
        return Color(hex: stop.hex)
        #endif
    }

    private static func blend(_ first: Color, _ second: Color, amount: Double) -> Color {
        let clampedAmount = min(max(amount, 0), 1)
        #if canImport(AppKit)
        let firstColor = cachedSRGBColor(for: first)
        let secondColor = cachedSRGBColor(for: second)
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        firstColor.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        secondColor.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return Color(
            nsColor: NSColor(
                srgbRed: r1 + (r2 - r1) * clampedAmount,
                green: g1 + (g2 - g1) * clampedAmount,
                blue: b1 + (b2 - b1) * clampedAmount,
                alpha: a1 + (a2 - a1) * clampedAmount
            )
        )
        #else
        return clampedAmount < 0.5 ? first : second
        #endif
    }
}

#if canImport(AppKit)
private func cachedSRGBColor(for hex: String) -> NSColor {
    NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .black
}

private func cachedSRGBColor(for color: Color) -> NSColor {
    NSColor(color).usingColorSpace(.sRGB) ?? .black
}
#endif
