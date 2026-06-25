import Foundation
import SwiftUI

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
        let start = components(for: stops[0])
        let end = components(for: stops[1])
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
            blend(start, end, amount: (projection - minProjection) / span).color
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
        let first = components(for: stops[0])
        let second = components(for: stops[1])
        let third = components(for: stops[2])

        return [
            first.color,
            blend(first, second, amount: 0.5).color,
            second.color,
            blend(first, third, amount: 0.45).color,
            blend(blend(first, second, amount: 0.5), third, amount: 0.35).color,
            blend(second, third, amount: 0.45).color,
            third.color,
            blend(third, first, amount: 0.25).color,
            blend(third, second, amount: 0.35).color
        ]
    }

    private static func color(for stop: WorkspaceGradientStop?) -> Color {
        components(for: stop).color
    }

    private static func components(for stop: WorkspaceGradientStop?) -> SRGBColorComponents {
        SRGBColorComponents(hex: stop?.hex ?? WorkspaceResolvedGradient.default.primaryColorHex)
    }

    private static func blend(
        _ first: SRGBColorComponents,
        _ second: SRGBColorComponents,
        amount: Double
    ) -> SRGBColorComponents {
        let clampedAmount = min(max(amount, 0), 1)
        return SRGBColorComponents(
            red: first.red + (second.red - first.red) * clampedAmount,
            green: first.green + (second.green - first.green) * clampedAmount,
            blue: first.blue + (second.blue - first.blue) * clampedAmount,
            alpha: first.alpha + (second.alpha - first.alpha) * clampedAmount
        )
    }
}

private struct SRGBColorComponents {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (
                255,
                (int >> 8) * 17,
                (int >> 4 & 0xF) * 17,
                (int & 0xF) * 17
            )
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (
                int >> 24,
                int >> 16 & 0xFF,
                int >> 8 & 0xFF,
                int & 0xFF
            )
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
