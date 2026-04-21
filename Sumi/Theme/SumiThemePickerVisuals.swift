import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum SumiOpacityWaveMetrics {
    private enum PathCommand {
        case move(CGPoint)
        case line(CGPoint)
        case curve(control1: CGPoint, control2: CGPoint, point: CGPoint)
    }

    static let linePathString = "M 51.373 27.395 L 367.037 27.395"
    static let sinePathString = "M 51.373 27.395 C 60.14 -8.503 68.906 -8.503 77.671 27.395 C 86.438 63.293 95.205 63.293 103.971 27.395 C 112.738 -8.503 121.504 -8.503 130.271 27.395 C 139.037 63.293 147.803 63.293 156.57 27.395 C 165.335 -8.503 174.101 -8.503 182.868 27.395 C 191.634 63.293 200.4 63.293 209.167 27.395 C 217.933 -8.503 226.7 -8.503 235.467 27.395 C 244.233 63.293 252.999 63.293 261.765 27.395 C 270.531 -8.503 279.297 -8.503 288.064 27.395 C 296.83 63.293 305.596 63.293 314.363 27.395 C 323.13 -8.503 331.896 -8.503 340.662 27.395 M 314.438 27.395 C 323.204 -8.503 331.97 -8.503 340.737 27.395 C 349.503 63.293 358.27 63.293 367.037 27.395"

    static let referenceY: CGFloat = 27.3
    static let svgViewBox = CGRect(x: 0, y: -7.605, width: 455, height: 70)
    static let lineStartX: CGFloat = 51.373
    static let lineEndX: CGFloat = 367.037
    static let trackHeight: CGFloat = 18
    static let waveStrokeWidth: CGFloat = 8
    static let waveLeadingOffset: CGFloat = -5
    static let waveMarginLeft: CGFloat = 4
    static let waveWidthMultiplier: CGFloat = 1.1
    static let waveScale: CGFloat = 1.2
    private static let sineCommands = parsePath(sinePathString)

    static func normalizedProgress(for opacity: Double) -> Double {
        let range = WorkspaceGradientTheme.maximumOpacity - WorkspaceGradientTheme.minimumOpacity
        guard range > 0 else { return 0 }
        let normalized = (opacity - WorkspaceGradientTheme.minimumOpacity) / range
        return min(max(normalized, 0), 1)
    }

    static func thumbSize(for progress: Double) -> CGSize {
        let clamped = min(max(progress, 0), 1)
        return CGSize(width: 10 + clamped * 15, height: 40 + clamped * 15)
    }

    static func lineBounds(
        trackWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> ClosedRange<CGFloat> {
        let frameWidth = trackWidth * waveWidthMultiplier
        let fittedScale = min(frameWidth / svgViewBox.width, 1)
        let renderedScale = fittedScale * waveScale
        let originX = horizontalPadding + waveLeadingOffset + waveMarginLeft
        // Match `convert(_:scale:offsetX:offsetY:)` X mapping so thumb/track align with the stroked path.
        let adjustedStartX = lineStartX - svgViewBox.minX
        let adjustedEndX = lineEndX - svgViewBox.minX
        let startX = originX + adjustedStartX * renderedScale
        let endX = originX + adjustedEndX * renderedScale
        return startX...endX
    }

    static func interactiveLineBounds(
        trackWidth: CGFloat,
        horizontalPadding: CGFloat,
        viewWidth: CGFloat
    ) -> ClosedRange<CGFloat> {
        fittedLineBounds(
            lineBounds(trackWidth: trackWidth, horizontalPadding: horizontalPadding),
            viewWidth: viewWidth
        )
    }

    static func progress(
        for xPosition: CGFloat,
        in lineBounds: ClosedRange<CGFloat>
    ) -> Double {
        let clampedX = min(max(xPosition, lineBounds.lowerBound), lineBounds.upperBound)
        let travelWidth = max(lineBounds.upperBound - lineBounds.lowerBound, 1)
        let rawProgress = Double((clampedX - lineBounds.lowerBound) / travelWidth)
        return min(max(rawProgress, 0), 1)
    }

    static func interpolatedPathString(progress: Double) -> String {
        guard progress > 0.001 else {
            return linePathString
        }
        guard progress < 0.999 else {
            return sinePathString
        }

        let t = min(max(progress, 0), 1)
        return sineCommands.map { command in
            switch command {
            case let .move(point):
                let y = referenceY + (point.y - referenceY) * t
                return "M \(point.x) \(y)"
            case let .line(point):
                return "L \(point.x) \(point.y)"
            case let .curve(control1, control2, point):
                let y1 = referenceY + (control1.y - referenceY) * t
                let y2 = referenceY + (control2.y - referenceY) * t
                let y = referenceY + (point.y - referenceY) * t
                return "C \(control1.x) \(y1) \(control2.x) \(y2) \(point.x) \(y)"
            }
        }
        .joined(separator: " ")
    }

    static func path(in rect: CGRect, progress: Double) -> Path {
        let commands = parsePath(interpolatedPathString(progress: progress))
        let scale = min(
            rect.width / svgViewBox.width,
            rect.height / svgViewBox.height
        )
        let fittedSize = CGSize(
            width: svgViewBox.width * scale,
            height: svgViewBox.height * scale
        )
        let offsetX = rect.minX
        let offsetY = rect.midY - fittedSize.height / 2

        var path = Path()
        for command in commands {
            switch command {
            case let .move(point):
                path.move(
                    to: convert(
                        point,
                        scale: scale,
                        offsetX: offsetX,
                        offsetY: offsetY
                    )
                )
            case let .line(point):
                path.addLine(
                    to: convert(
                        point,
                        scale: scale,
                        offsetX: offsetX,
                        offsetY: offsetY
                    )
                )
            case let .curve(control1, control2, point):
                path.addCurve(
                    to: convert(point, scale: scale, offsetX: offsetX, offsetY: offsetY),
                    control1: convert(control1, scale: scale, offsetX: offsetX, offsetY: offsetY),
                    control2: convert(control2, scale: scale, offsetX: offsetX, offsetY: offsetY)
                )
            }
        }
        return path
    }

    static func usesGradientStroke(for progress: Double) -> Bool {
        progress > 0.001
    }

    private static func convert(
        _ point: CGPoint,
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: offsetX + (point.x - svgViewBox.minX) * scale,
            y: offsetY + (point.y - svgViewBox.minY) * scale
        )
    }

    private static func fittedLineBounds(
        _ lineBounds: ClosedRange<CGFloat>,
        viewWidth: CGFloat
    ) -> ClosedRange<CGFloat> {
        let maxThumbHalfWidth = thumbSize(for: 1).width / 2
        let safeLowerBound = max(maxThumbHalfWidth + 1, 1)
        let safeUpperBound = viewWidth - maxThumbHalfWidth - 1

        guard safeUpperBound > safeLowerBound else {
            let anchor = max(min(viewWidth / 2, viewWidth - 1), 1)
            return anchor...anchor
        }

        var lower = lineBounds.lowerBound
        var upper = lineBounds.upperBound

        if upper > safeUpperBound {
            let overflow = upper - safeUpperBound
            lower -= overflow
            upper -= overflow
        }

        if lower < safeLowerBound {
            let underflow = safeLowerBound - lower
            lower += underflow
            upper += underflow
        }

        lower = max(lower, safeLowerBound)
        upper = min(upper, safeUpperBound)

        if upper <= lower {
            return safeLowerBound...safeUpperBound
        }

        return lower...upper
    }

    private static func parsePath(_ pathString: String) -> [PathCommand] {
        let pattern = #"[MCL]\s*[\d\s\.\-\,]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let fullRange = NSRange(pathString.startIndex..., in: pathString)
        return regex.matches(in: pathString, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: pathString) else { return nil }
            let command = pathString[range]
            let type = command.first
            let coordinates = command
                .dropFirst()
                .split(whereSeparator: { $0 == " " || $0 == "," })
                .compactMap { Double($0) }

            switch type {
            case "M":
                guard coordinates.count >= 2 else { return nil }
                return .move(CGPoint(x: coordinates[0], y: coordinates[1]))
            case "L":
                guard coordinates.count >= 2 else { return nil }
                return .line(CGPoint(x: coordinates[0], y: coordinates[1]))
            case "C":
                guard coordinates.count >= 6 else { return nil }
                return .curve(
                    control1: CGPoint(x: coordinates[0], y: coordinates[1]),
                    control2: CGPoint(x: coordinates[2], y: coordinates[3]),
                    point: CGPoint(x: coordinates[4], y: coordinates[5])
                )
            default:
                return nil
            }
        }
    }
}

struct SumiOpacityWaveShape: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        SumiOpacityWaveMetrics.path(in: rect, progress: progress)
    }
}

enum SumiTextureRingMetrics {
    static let stepCount = 16
    static let dotSize: CGFloat = 4
    static let handlerWidth: CGFloat = 6
    static let handlerHeight: CGFloat = 12
    static let handlerHoverHeight: CGFloat = 14
    static let innerDiameterRatio: CGFloat = 0.6
    private static let radiusRatio: CGFloat = 0.44

    static func quantized(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        let wrapped = (clamped * Double(stepCount)).rounded() / Double(stepCount)
        return wrapped >= 1 ? 0 : wrapped
    }

    static func rotationDegrees(for value: Double) -> Double {
        quantized(value) * 360 - 90
    }

    static func handlerPoint(in size: CGSize, value: Double) -> CGPoint {
        let wrapperWidth = min(size.width, size.height)
        let rotation = rotationDegrees(for: value)
        let angle = rotation * .pi / 180
        let radius = wrapperWidth * radiusRatio
        return CGPoint(
            x: wrapperWidth / 2 + cos(angle) * radius,
            y: wrapperWidth / 2 + sin(angle) * radius
        )
    }

    static func dotPoint(index: Int, in size: CGSize) -> CGPoint {
        let wrapperWidth = min(size.width, size.height)
        let angle = ((Double(index - 4) / Double(stepCount)) * .pi * 2) - (.pi / 2)
        let radius = wrapperWidth * radiusRatio
        return CGPoint(
            x: wrapperWidth / 2 + cos(angle) * radius,
            y: wrapperWidth / 2 + sin(angle) * radius
        )
    }

    static func isActive(index: Int, value: Double) -> Bool {
        let normalizedIndex = (index - 4 + stepCount) % stepCount
        return Double(normalizedIndex) / Double(stepCount) <= quantized(value)
    }

    static func quantizedValue(for location: CGPoint, in size: CGSize) -> Double {
        let wrapperWidth = min(size.width, size.height)
        let center = CGPoint(x: wrapperWidth / 2, y: wrapperWidth / 2)
        let rotation = atan2(location.y - center.y, location.x - center.x)
        var value = rotation * 180 / .pi + 90
        if value < 0 {
            value += 360
        }
        value /= 360
        return quantized(value)
    }
}

#if canImport(AppKit)
private enum SumiThemePickerAssetCatalog {
    private static let sumiSourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let appSourceRoot = sumiSourceRoot
        .deletingLastPathComponent()
    private static let workspaceSourceRoot = appSourceRoot
        .deletingLastPathComponent()
    private static let projectSourceRoot = workspaceSourceRoot
        .deletingLastPathComponent()

    static let grainImage: NSImage? = {
        if let namedImage = NSImage(named: "noise_texture") {
            return namedImage
        }

        for url in grainImageCandidates() {
            guard FileManager.default.fileExists(atPath: url.path),
                  let image = NSImage(contentsOf: url) else {
                continue
            }
            return image
        }

        return nil
    }()

    private static func grainImageCandidates() -> [URL] {
        [
            sumiSourceRoot
                .appendingPathComponent("Assets.xcassets/noise_texture.imageset/noise_texture@3x.png", isDirectory: false),
            sumiSourceRoot
                .appendingPathComponent("Assets.xcassets/noise_texture.imageset/noise_texture@2x.png", isDirectory: false),
            sumiSourceRoot
                .appendingPathComponent("Assets.xcassets/noise_texture.imageset/noise_texture.png", isDirectory: false),
            workspaceSourceRoot
                .appendingPathComponent("references/Zen/src/zen/images/grain-bg.png", isDirectory: false),
            projectSourceRoot
                .appendingPathComponent("references/Zen/src/zen/images/grain-bg.png", isDirectory: false),
        ]
    }
}
#endif

struct TiledNoiseTexture: View {
    var opacity: Double
    var blendMode: BlendMode = .normal

    var body: some View {
        #if canImport(AppKit)
        if let image = SumiThemePickerAssetCatalog.grainImage {
            Image(nsImage: image)
                .resizable(resizingMode: .tile)
                .interpolation(.none)
                .antialiased(false)
                .opacity(max(0, min(1, opacity)))
                .blendMode(blendMode)
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }
}
