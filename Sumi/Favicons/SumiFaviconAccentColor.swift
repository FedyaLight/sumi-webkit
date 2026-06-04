import AppKit
import SwiftUI

enum SumiFaviconAccentColor {
    private static let sampleDimension = 16
    private static let minimumSaturation: CGFloat = 0.25
    private static let minimumBrightness: CGFloat = 0.24
    private static let maximumBrightness: CGFloat = 0.88
    private static let maximumNeutralBrightness: CGFloat = 0.56

    static func extract(from image: NSImage) -> Color? {
        guard let cgImage = downsampledCGImage(from: image) else { return nil }
        return extract(from: cgImage)
    }

    static func extract(from cgImage: CGImage) -> Color? {
        dominantSampleColor(for: cgImage).map(clampedDisplayColor)
    }

    static func clampedDisplayColor(_ color: NSColor) -> Color {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return Color(nsColor: color)
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if saturation < 0.12 {
            return Color(
                nsColor: NSColor(
                    hue: hue,
                    saturation: 0,
                    brightness: min(max(brightness, minimumBrightness), maximumNeutralBrightness),
                    alpha: max(alpha, 0.85)
                )
            )
        }

        let clampedSaturation = max(saturation, minimumSaturation)
        let clampedBrightness = min(max(brightness, minimumBrightness), maximumBrightness)
        return Color(
            nsColor: NSColor(
                hue: hue,
                saturation: clampedSaturation,
                brightness: clampedBrightness,
                alpha: max(alpha, 0.85)
            )
        )
    }

    private static func downsampledCGImage(from image: NSImage) -> CGImage? {
        let dimension = sampleDimension
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dimension,
            pixelsHigh: dimension,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(
            in: NSRect(x: 0, y: 0, width: dimension, height: dimension),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.medium]
        )
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func dominantSampleColor(for cgImage: CGImage) -> NSColor? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hueVectorX = 0.0
        var hueVectorY = 0.0
        var saturationTotal = 0.0
        var brightnessTotal = 0.0
        var weightTotal = 0.0
        var neutralBrightnessTotal = 0.0
        var neutralWeightTotal = 0.0

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let alpha = Double(pixels[offset + 3]) / 255
                guard alpha > 0.18 else { continue }

                let color = NSColor(
                    red: CGFloat(pixels[offset]) / 255,
                    green: CGFloat(pixels[offset + 1]) / 255,
                    blue: CGFloat(pixels[offset + 2]) / 255,
                    alpha: CGFloat(alpha)
                )
                guard let rgb = color.usingColorSpace(.sRGB) else { continue }

                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

                guard brightness > 0.05 else { continue }

                if saturation <= 0.28 {
                    let darkPixelWeight = pow(1.08 - Double(brightness), 1.65)
                    let weight = alpha * max(0.05, darkPixelWeight)
                    neutralBrightnessTotal += Double(brightness) * weight
                    neutralWeightTotal += weight
                    continue
                }

                let saturationWeight = pow(Double(saturation), 2.2)
                let brightnessWeight = 0.65 + Double(brightness) * 0.35
                let weight = alpha * saturationWeight * brightnessWeight
                let angle = Double(hue) * 2 * Double.pi
                hueVectorX += cos(angle) * weight
                hueVectorY += sin(angle) * weight
                saturationTotal += Double(saturation) * weight
                brightnessTotal += Double(brightness) * weight
                weightTotal += weight
            }
        }

        guard weightTotal > 0 else {
            guard neutralWeightTotal > 0 else { return nil }
            return NSColor(
                hue: 0,
                saturation: 0,
                brightness: min(
                    max(CGFloat(neutralBrightnessTotal / neutralWeightTotal), minimumBrightness),
                    maximumNeutralBrightness
                ),
                alpha: 1
            )
        }
        let hue = atan2(hueVectorY, hueVectorX) / (2 * Double.pi)
        let normalizedHue = hue < 0 ? hue + 1 : hue
        return NSColor(
            hue: CGFloat(normalizedHue),
            saturation: CGFloat(saturationTotal / weightTotal),
            brightness: CGFloat(brightnessTotal / weightTotal),
            alpha: 1
        )
    }
}
