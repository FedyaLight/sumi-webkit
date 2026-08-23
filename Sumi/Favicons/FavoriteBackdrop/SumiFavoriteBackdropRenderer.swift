import Accelerate
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum SumiFavoriteBackdropRenderer {
    static let pixelDimension = 16
    private static let blurRadius = 3
    private static let blurPassCount = 3
    private static let sourceOverscan: CGFloat = 1.45

    @MainActor
    static func bake(favicon: NSImage) async -> Data? {
        guard let source = cgImage(from: favicon) else { return nil }
        return await Task.detached(priority: .utility) {
            bake(source: source)
        }.value
    }

    private static func bake(source: CGImage) -> Data? {
        guard let context = bitmapContext(),
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

        let baseColor = SumiFaviconAccentColor.extract(from: source)
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
        let kernelSize = UInt32(blurRadius * 2 + 1)

        for _ in 0..<blurPassCount {
            source.withUnsafeMutableBytes { sourceBytes in
                destination.withUnsafeMutableBytes { destinationBytes in
                    var sourceBuffer = vImage_Buffer(
                        data: sourceBytes.baseAddress,
                        height: vImagePixelCount(pixelDimension),
                        width: vImagePixelCount(pixelDimension),
                        rowBytes: pixelDimension * 4
                    )
                    var destinationBuffer = vImage_Buffer(
                        data: destinationBytes.baseAddress,
                        height: vImagePixelCount(pixelDimension),
                        width: vImagePixelCount(pixelDimension),
                        rowBytes: pixelDimension * 4
                    )
                    vImageBoxConvolve_ARGB8888(
                        &sourceBuffer,
                        &destinationBuffer,
                        nil,
                        0,
                        0,
                        kernelSize,
                        kernelSize,
                        nil,
                        vImage_Flags(kvImageEdgeExtend)
                    )
                }
            }
            swap(&source, &destination)
        }

        for index in 0..<byteCount {
            pixels[index] = source[index]
        }
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
