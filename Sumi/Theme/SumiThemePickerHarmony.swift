import CoreGraphics
import Foundation

struct SumiThemePickerActionState: Equatable {
    let canAdd: Bool
    let canRemove: Bool
    let canCycleHarmony: Bool
    let showsClickToAdd: Bool

    static func resolve(dotCount: Int) -> SumiThemePickerActionState {
        let resolvedDotCount = max(dotCount, 0)
        return SumiThemePickerActionState(
            canAdd: resolvedDotCount > 0
                && resolvedDotCount < SumiThemePickerHarmony.maxDots,
            canRemove: resolvedDotCount > 0,
            canCycleHarmony: resolvedDotCount >= 2,
            showsClickToAdd: resolvedDotCount == 0
        )
    }
}

struct SumiThemePickerFieldGeometry: Equatable {
    struct ResolvedColor: Equatable {
        let hex: String
        let lightness: Double
    }

    static let colorPadding: CGFloat = 30
    static let colorDotHalfSize: CGFloat = 29

    let size: CGSize

    var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    var radius: CGFloat {
        min(size.width, size.height) / 2
    }

    func clamp(_ point: CGPoint) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)

        guard distance > radius, distance > 0 else {
            return point
        }

        let scale = radius / distance
        return CGPoint(
            x: center.x + dx * scale,
            y: center.y + dy * scale
        )
    }

    func point(for position: WorkspaceThemePosition) -> CGPoint {
        CGPoint(
            x: position.x * size.width,
            y: position.y * size.height
        )
    }

    func normalizedPosition(for point: CGPoint) -> WorkspaceThemePosition {
        WorkspaceThemePosition(
            x: size.width > 0 ? point.x / size.width : 0.5,
            y: size.height > 0 ? point.y / size.height : 0.5
        )
    }

    func resolvedColor(
        for point: CGPoint,
        currentLightness: Double,
        type: WorkspaceThemeColorType
    ) -> ResolvedColor {
        let expandedWidth = size.width + Self.colorPadding * 2
        let expandedHeight = size.height + Self.colorPadding * 2
        let centerX = expandedWidth / 2
        let centerY = expandedHeight / 2
        let radius = (expandedWidth - Self.colorPadding) / 2

        let adjustedX = point.x + Self.colorDotHalfSize
        let adjustedY = point.y + Self.colorDotHalfSize
        let distance = hypot(adjustedX - centerX, adjustedY - centerY)

        var angle = atan2(adjustedY - centerY, adjustedX - centerX) * 180 / .pi
        if angle < 0 {
            angle += 360
        }

        let normalizedDistance = 1 - min(distance / radius, 1)
        var saturation = normalizedDistance
        var resolvedLightness = clampUnit(currentLightness)

        if type != .explicitLightness {
            saturation = 0.9 + (1 - normalizedDistance) * 0.1
            resolvedLightness = roundedPercent(1 - normalizedDistance)
        }

        if type == .explicitBlackWhite {
            saturation = 0
            resolvedLightness = roundedPercent(1 - normalizedDistance)
        }

        let rgb = Self.hslToRGB(
            hue: angle / 360,
            saturation: clampUnit(saturation),
            lightness: clampUnit(resolvedLightness)
        )

        return ResolvedColor(
            hex: String(
                format: "#%02X%02X%02X",
                Int(round(rgb.r * 255)),
                Int(round(rgb.g * 255)),
                Int(round(rgb.b * 255))
            ),
            lightness: clampUnit(resolvedLightness)
        )
    }

    private func roundedPercent(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func clampUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func hslToRGB(
        hue: Double,
        saturation: Double,
        lightness: Double
    ) -> (r: Double, g: Double, b: Double) {
        if saturation == 0 {
            return (lightness, lightness, lightness)
        }

        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q

        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var wrapped = t
            if wrapped < 0 { wrapped += 1 }
            if wrapped > 1 { wrapped -= 1 }
            if wrapped < 1.0 / 6.0 { return p + (q - p) * 6 * wrapped }
            if wrapped < 1.0 / 2.0 { return q }
            if wrapped < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - wrapped) * 6 }
            return p
        }

        return (
            hueToRGB(p, q, hue + 1.0 / 3.0),
            hueToRGB(p, q, hue),
            hueToRGB(p, q, hue - 1.0 / 3.0)
        )
    }
}

enum SumiThemePickerHarmony: String, CaseIterable, Identifiable {
    case complementary
    case singleAnalogous
    case splitComplementary
    case analogous
    case triadic
    case floating

    static let maxDots = 3

    var id: String { rawValue }

    var angles: [Double] {
        switch self {
        case .complementary:
            return [180]
        case .singleAnalogous:
            return [310]
        case .splitComplementary:
            return [150, 210]
        case .analogous:
            return [50, 310]
        case .triadic:
            return [120, 240]
        case .floating:
            return []
        }
    }

    var persistedAlgorithm: WorkspaceThemeColorAlgorithm {
        switch self {
        case .complementary:
            return .complementary
        case .singleAnalogous, .analogous:
            return .analogous
        case .splitComplementary:
            return .splitComplementary
        case .triadic:
            return .triadic
        case .floating:
            return .floating
        }
    }

    static func applicableHarmonies(for dotCount: Int) -> [SumiThemePickerHarmony] {
        guard dotCount > 0 else { return [] }
        let resolvedDotCount = min(dotCount, maxDots)
        return allCases.filter { $0.angles.count + 1 == resolvedDotCount }
    }

    static func next(after current: SumiThemePickerHarmony, dotCount: Int) -> SumiThemePickerHarmony {
        let harmonies = applicableHarmonies(for: dotCount)
        guard !harmonies.isEmpty else { return .floating }

        guard let currentIndex = harmonies.firstIndex(of: current) else {
            return harmonies[0]
        }

        return harmonies[(currentIndex + 1) % harmonies.count]
    }

    static func addedHarmony(
        from current: SumiThemePickerHarmony,
        currentDotCount: Int
    ) -> SumiThemePickerHarmony {
        let resultingDotCount = min(max(currentDotCount + 1, 1), maxDots)
        let expectedAngleCount = current.angles.count + 1
        return applicableHarmonies(for: resultingDotCount).first(where: {
            $0.angles.count == expectedAngleCount
        }) ?? applicableHarmonies(for: resultingDotCount).first ?? .floating
    }

    static func removedHarmony(resultingDotCount: Int) -> SumiThemePickerHarmony {
        guard resultingDotCount >= 2 else { return .floating }
        return applicableHarmonies(for: resultingDotCount).first ?? .floating
    }

    static func infer(from colors: [WorkspaceThemeColor]) -> SumiThemePickerHarmony {
        let resolvedColors = Array(colors.prefix(maxDots))
        let dotCount = resolvedColors.count
        let harmonies = applicableHarmonies(for: dotCount)

        guard dotCount > 1, let primary = resolvedColors.first else {
            return .floating
        }

        let storedAlgorithm = primary.algorithm
        if dotCount == 2 {
            switch storedAlgorithm {
            case .complementary:
                return .complementary
            case .analogous:
                return .singleAnalogous
            default:
                break
            }
        } else if let exact = harmonies.first(where: { $0.persistedAlgorithm == storedAlgorithm }) {
            return exact
        }

        let measuredOffsets = resolvedColors.dropFirst().map {
            angularOffset(from: primary.position, to: $0.position)
        }.sorted()

        return harmonies.min(by: {
            score(measuredOffsets, against: $0.angles.sorted()) < score(measuredOffsets, against: $1.angles.sorted())
        }) ?? .floating
    }

    static func makePrimaryColor(
        at point: CGPoint,
        geometry: SumiThemePickerFieldGeometry,
        lightness: Double,
        type: WorkspaceThemeColorType
    ) -> WorkspaceThemeColor {
        let clampedPoint = geometry.clamp(point)
        let resolvedColor = geometry.resolvedColor(
            for: clampedPoint,
            currentLightness: lightness,
            type: type
        )

        return WorkspaceThemeColor(
            hex: resolvedColor.hex,
            isPrimary: true,
            algorithm: .floating,
            lightness: resolvedColor.lightness,
            position: geometry.normalizedPosition(for: clampedPoint),
            type: type
        )
    }

    static func rebuildColors(
        from existingColors: [WorkspaceThemeColor],
        targetCount: Int? = nil,
        harmony: SumiThemePickerHarmony,
        geometry: SumiThemePickerFieldGeometry,
        primaryPoint: CGPoint? = nil
    ) -> [WorkspaceThemeColor] {
        let resolvedExisting = Array(existingColors.prefix(maxDots))
        let resolvedCount = min(max(targetCount ?? resolvedExisting.count, 0), maxDots)

        guard resolvedCount > 0, let primary = resolvedExisting.first else {
            return []
        }

        let resolvedHarmony = resolvedCount > 1 ? harmony : .floating
        let primaryType = primary.type
        let primaryPoint = primaryPoint ?? geometry.point(for: primary.position)
        let clampedPrimaryPoint = geometry.clamp(primaryPoint)
        let primaryColor = geometry.resolvedColor(
            for: clampedPrimaryPoint,
            currentLightness: primary.lightness,
            type: primaryType
        )
        let generatedPoints = [clampedPrimaryPoint]
            + resolvedHarmony.companionPoints(for: clampedPrimaryPoint, geometry: geometry)

        return (0..<resolvedCount).map { index in
            let template = resolvedExisting.indices.contains(index) ? resolvedExisting[index] : primary
            let point = generatedPoints[index]
            let resolvedColor = geometry.resolvedColor(
                for: point,
                currentLightness: primaryColor.lightness,
                type: primaryType
            )

            let isNew = !resolvedExisting.indices.contains(index)

            return WorkspaceThemeColor(
                id: isNew ? UUID() : template.id,
                hex: resolvedColor.hex,
                isCustom: template.isCustom,
                isPrimary: index == 0,
                algorithm: resolvedHarmony.persistedAlgorithm,
                lightness: resolvedColor.lightness,
                position: geometry.normalizedPosition(for: point),
                type: primaryType
            )
        }
    }

    func companionPoints(
        for primaryPoint: CGPoint,
        geometry: SumiThemePickerFieldGeometry
    ) -> [CGPoint] {
        guard !angles.isEmpty else { return [] }

        let baseAngle = Self.angle(for: primaryPoint, center: geometry.center)
        let distance = min(
            hypot(primaryPoint.x - geometry.center.x, primaryPoint.y - geometry.center.y),
            geometry.radius
        )

        return angles.map { angleOffset in
            let radians = ((baseAngle + angleOffset) * .pi) / 180
            return geometry.clamp(
                CGPoint(
                    x: geometry.center.x + cos(radians) * distance,
                    y: geometry.center.y + sin(radians) * distance
                )
            )
        }
    }

    private static func angle(for point: CGPoint, center: CGPoint) -> Double {
        var angle = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        if angle < 0 {
            angle += 360
        }
        return angle
    }

    private static func angularOffset(
        from primary: WorkspaceThemePosition,
        to companion: WorkspaceThemePosition
    ) -> Double {
        let primaryAngle = angle(
            for: CGPoint(x: primary.x, y: primary.y),
            center: CGPoint(x: 0.5, y: 0.5)
        )
        let companionAngle = angle(
            for: CGPoint(x: companion.x, y: companion.y),
            center: CGPoint(x: 0.5, y: 0.5)
        )
        let rawOffset = companionAngle - primaryAngle
        return rawOffset >= 0 ? rawOffset : rawOffset + 360
    }

    private static func circularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private static func score(_ measured: [Double], against expected: [Double]) -> Double {
        guard measured.count == expected.count else {
            return .greatestFiniteMagnitude
        }

        return zip(measured, expected).reduce(0) { partialResult, entry in
            partialResult + circularDistance(entry.0, entry.1)
        }
    }
}
