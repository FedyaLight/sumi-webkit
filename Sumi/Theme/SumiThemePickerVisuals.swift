import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

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
