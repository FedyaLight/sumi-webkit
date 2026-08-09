import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum SumiFavoriteBackdropRenderer {
    static let pixelDimension = 16
    private static let blurRadius = 3
    private static let blurPassCount = 3
    private static let sourceOverscan: CGFloat = 1.45

    static func bake(favicon: NSImage) -> Data? {
        guard let source = cgImage(from: favicon),
              let context = bitmapContext(),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }

        context.clear(CGRect(
            x: 0,
            y: 0,
            width: pixelDimension,
            height: pixelDimension
        ))
        draw(source, in: context)
        guard containsVisiblePixel(pixels) else { return nil }

        let baseColor = SumiFaviconAccentColor.extract(from: favicon)
            .map(NSColor.init)
            ?? NSColor(calibratedWhite: 0.32, alpha: 1)
        guard let rgb = baseColor.usingColorSpace(.sRGB) else { return nil }

        context.setBlendMode(.copy)
        context.setFillColor(rgb.cgColor)
        context.fill(CGRect(
            x: 0,
            y: 0,
            width: pixelDimension,
            height: pixelDimension
        ))
        context.setBlendMode(.normal)
        context.setAlpha(0.86)
        draw(source, in: context)
        context.setAlpha(1)

        blurOpaqueRGBA(pixels)
        guard let result = context.makeImage() else { return nil }
        return pngData(from: result)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(
            forProposedRect: &rect,
            context: nil,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private static func bitmapContext() -> CGContext? {
        CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: pixelDimension * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func draw(_ image: CGImage, in context: CGContext) {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return }
        let destination = CGFloat(pixelDimension) * sourceOverscan
        let scale = max(destination / width, destination / height)
        let drawSize = CGSize(width: width * scale, height: height * scale)
        let rect = CGRect(
            x: (CGFloat(pixelDimension) - drawSize.width) / 2,
            y: (CGFloat(pixelDimension) - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.interpolationQuality = .high
        context.draw(image, in: rect)
    }

    private static func containsVisiblePixel(_ pixels: UnsafeMutablePointer<UInt8>) -> Bool {
        let count = pixelDimension * pixelDimension
        for index in 0..<count where pixels[index * 4 + 3] > 24 {
            return true
        }
        return false
    }

    private static func blurOpaqueRGBA(_ pixels: UnsafeMutablePointer<UInt8>) {
        let byteCount = pixelDimension * pixelDimension * 4
        var source = Array(UnsafeBufferPointer(start: pixels, count: byteCount))
        var destination = source

        for _ in 0..<blurPassCount {
            boxBlurHorizontal(source: source, destination: &destination)
            swap(&source, &destination)
            boxBlurVertical(source: source, destination: &destination)
            swap(&source, &destination)
        }

        for index in 0..<byteCount {
            pixels[index] = source[index]
        }
    }

    private static func boxBlurHorizontal(
        source: [UInt8],
        destination: inout [UInt8]
    ) {
        let width = pixelDimension
        for y in 0..<pixelDimension {
            for x in 0..<width {
                averagePixel(
                    source: source,
                    destination: &destination,
                    x: x,
                    y: y,
                    varying: max(0, x - blurRadius)...min(width - 1, x + blurRadius),
                    isHorizontal: true
                )
            }
        }
    }

    private static func boxBlurVertical(
        source: [UInt8],
        destination: inout [UInt8]
    ) {
        let height = pixelDimension
        for y in 0..<height {
            for x in 0..<pixelDimension {
                averagePixel(
                    source: source,
                    destination: &destination,
                    x: x,
                    y: y,
                    varying: max(0, y - blurRadius)...min(height - 1, y + blurRadius),
                    isHorizontal: false
                )
            }
        }
    }

    private static func averagePixel(
        source: [UInt8],
        destination: inout [UInt8],
        x: Int,
        y: Int,
        varying: ClosedRange<Int>,
        isHorizontal: Bool
    ) {
        var red = 0
        var green = 0
        var blue = 0
        for value in varying {
            let sampleX = isHorizontal ? value : x
            let sampleY = isHorizontal ? y : value
            let offset = (sampleY * pixelDimension + sampleX) * 4
            red += Int(source[offset])
            green += Int(source[offset + 1])
            blue += Int(source[offset + 2])
        }
        let count = varying.count
        let offset = (y * pixelDimension + x) * 4
        destination[offset] = UInt8(red / count)
        destination[offset + 1] = UInt8(green / count)
        destination[offset + 2] = UInt8(blue / count)
        destination[offset + 3] = 255
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
