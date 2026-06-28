import AppKit
import Foundation
import ImageIO

// Stateless apart from queue-protected stores/caches; SVG rasterization stays on the main actor.
final class SumiPreparedFaviconPipeline: @unchecked Sendable {
    private let blobStore: SumiFaviconBlobStore
    private let preparedCache: SumiPreparedFaviconCache

    init(
        blobStore: SumiFaviconBlobStore,
        preparedCache: SumiPreparedFaviconCache
    ) {
        self.blobStore = blobStore
        self.preparedCache = preparedCache
    }

    func cachedImage(
        for selection: SumiStoredFaviconSelection,
        request: SumiPreparedFaviconRequest
    ) -> NSImage? {
        preparedCache.image(for: identity(selection: selection, request: request))
    }

    func preparedImage(
        for selection: SumiStoredFaviconSelection,
        request: SumiPreparedFaviconRequest
    ) async -> NSImage? {
        let identity = identity(selection: selection, request: request)
        if let cached = preparedCache.image(for: identity) {
            return cached
        }

        guard let data = blobStore.payloadData(
            blobID: selection.blobID,
            partition: selection.partition
        ) else {
            return nil
        }

        let image: NSImage?
        if selection.payloadKind == .svg {
            image = await renderSVG(data: data, request: request)
        } else {
            image = renderRaster(data: data, request: request)
        }

        guard let image else { return nil }
        image.isTemplate = request.templateMode == .template
        preparedCache.setImage(image, for: identity)
        return image
    }

    func invalidate(
        partition: SumiFaviconPartition? = nil,
        blobID: String? = nil,
        revision: String? = nil
    ) {
        preparedCache.invalidate(partition: partition, blobID: blobID, revision: revision)
    }

    private func identity(
        selection: SumiStoredFaviconSelection,
        request: SumiPreparedFaviconRequest
    ) -> SumiPreparedFaviconIdentity {
        SumiPreparedFaviconIdentity(
            partition: selection.partition,
            blobID: selection.blobID,
            revision: selection.revision,
            sourceURL: selection.sourceURL,
            request: request
        )
    }

    private func renderRaster(data: Data, request: SumiPreparedFaviconRequest) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else {
            return nil
        }

        let targetPixelSize = request.pixelSize
        let index = SumiFaviconPayloadValidator.bestImageIndex(
            in: source,
            targetPixelSize: targetPixelSize
        )
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary

        guard let sourceImage = CGImageSourceCreateThumbnailAtIndex(source, index, options) else {
            return nil
        }

        return makePreparedImage(
            targetPixelSize: targetPixelSize,
            pointSize: request.pointSize,
            cornerRadius: request.cornerRadius * request.backingScale
        ) { context, targetRect in
            draw(
                cgImage: sourceImage,
                in: context,
                targetRect: targetRect
            )
        }
    }

    @MainActor
    private func renderSVG(data: Data, request: SumiPreparedFaviconRequest) -> NSImage? {
        guard let svgImage = NSImage(data: data), svgImage.isValid else {
            return nil
        }

        return makePreparedImage(
            targetPixelSize: request.pixelSize,
            pointSize: request.pointSize,
            cornerRadius: request.cornerRadius * request.backingScale
        ) { context, targetRect in
            let drawRect = Self.aspectFitRect(
                sourceSize: svgImage.size,
                targetRect: targetRect
            )
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            svgImage.draw(
                in: NSRect(
                    x: drawRect.origin.x,
                    y: drawRect.origin.y,
                    width: drawRect.width,
                    height: drawRect.height
                ),
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: false,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func makePreparedImage(
        targetPixelSize: Int,
        pointSize: CGFloat,
        cornerRadius: CGFloat,
        draw: (CGContext, CGRect) -> Void
    ) -> NSImage? {
        let width = max(1, targetPixelSize)
        let height = max(1, targetPixelSize)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if cornerRadius > 0 {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            context.clip()
        }
        draw(context, rect)

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: pointSize, height: pointSize)
        )
    }

    private func draw(
        cgImage: CGImage,
        in context: CGContext,
        targetRect: CGRect
    ) {
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        guard sourceWidth > 0, sourceHeight > 0 else { return }

        let drawRect = Self.aspectFitRect(
            sourceSize: CGSize(width: sourceWidth, height: sourceHeight),
            targetRect: targetRect
        )
        context.draw(cgImage, in: drawRect)
    }

    private static func aspectFitRect(sourceSize: CGSize, targetRect: CGRect) -> CGRect {
        guard sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              sourceSize.width > 0,
              sourceSize.height > 0,
              targetRect.width > 0,
              targetRect.height > 0
        else {
            return targetRect
        }

        let scale = min(targetRect.width / sourceSize.width, targetRect.height / sourceSize.height)
        let drawSize = CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )
        return CGRect(
            x: targetRect.midX - drawSize.width / 2,
            y: targetRect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }
}
