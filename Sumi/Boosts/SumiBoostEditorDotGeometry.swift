import Foundation

enum SumiBoostEditorDotGeometry {
    static func primaryDotData(
        for position: SumiBoostDotPosition,
        secondaryDelta: Double
    ) -> (
        angle: Double,
        distance: Double,
        primary: SumiBoostDotPosition,
        secondary: SumiBoostDotPosition
    ) {
        let center = SumiBoostDotPosition(x: 0.5, y: 0.5)
        let dx = position.x - center.x
        let dy = position.y - center.y
        let rawDistance = sqrt(dx * dx + dy * dy) / 0.42
        let distance = max(0, min(1, rawDistance))
        let angle = normalizedDegrees((atan2(dy, dx) * 180 / .pi) + 100)
        let primary = Self.position(angle: angle, distance: distance)
        let secondary = Self.position(angle: angle + secondaryDelta, distance: distance)
        return (angle, distance, primary, secondary)
    }

    static func secondaryDotData(
        for position: SumiBoostDotPosition,
        primaryAngle: Double,
        dotDistance: Double
    ) -> (delta: Double, position: SumiBoostDotPosition) {
        let dx = position.x - 0.5
        let dy = position.y - 0.5
        let rawAngle = (atan2(dy, dx) * 180 / .pi) + 100
        let delta = normalizedDegrees(rawAngle - primaryAngle)
        return (delta, Self.position(angle: primaryAngle + delta, distance: dotDistance))
    }

    static func position(angle: Double, distance: Double) -> SumiBoostDotPosition {
        let radians = (normalizedDegrees(angle) - 100) * .pi / 180
        let radius = max(0, min(1, distance)) * 0.42
        return SumiBoostDotPosition(
            x: max(0.08, min(0.92, 0.5 + cos(radians) * radius)),
            y: max(0.08, min(0.92, 0.5 + sin(radians) * radius))
        )
    }

    static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
