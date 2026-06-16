import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

enum URLBarHubScreenshotCapture {
    private static let maximumPixelCount = 67_108_864
    private static let maximumPixelDimension = 16_384

    @MainActor
    static func writeVisibleSnapshot(
        of webView: WKWebView,
        rect: CGRect? = nil,
        quality: URLBarHubScreenshotQuality,
        to destinationURL: URL,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        let captureRect = rect ?? webView.bounds
        guard captureRect.width > 0, captureRect.height > 0 else {
            completion(.failure(CaptureError.emptyViewport))
            return
        }

        let configuration = WKSnapshotConfiguration()
        configuration.rect = captureRect
        configuration.snapshotWidth = NSNumber(
            value: Double(snapshotWidth(for: captureRect.size, quality: quality))
        )

        webView.takeSnapshot(with: configuration) { image, error in
            Task { @MainActor in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let image else {
                    completion(.failure(CaptureError.missingImage))
                    return
                }

                let result = autoreleasepool {
                    Result {
                        try writePNG(image: image, to: destinationURL)
                    }
                }
                completion(result)
            }
        }
    }

    private static func snapshotWidth(
        for viewportSize: CGSize,
        quality: URLBarHubScreenshotQuality
    ) -> Int {
        let requestedWidth = max(1, Int(ceil(viewportSize.width * quality.scale)))
        let requestedHeight = max(1, Int(ceil(viewportSize.height * quality.scale)))
        let requestedPixels = requestedWidth * requestedHeight
        let pixelScale: CGFloat

        if requestedPixels > maximumPixelCount {
            pixelScale = sqrt(CGFloat(maximumPixelCount) / CGFloat(requestedPixels))
        } else {
            pixelScale = 1
        }

        return min(
            maximumPixelDimension,
            max(1, Int(floor(CGFloat(requestedWidth) * pixelScale)))
        )
    }

    private static func writePNG(image: NSImage, to destinationURL: URL) throws {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw CaptureError.missingCGImage
        }

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.cannotCreateDestination
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.writeFailed
        }
    }

    enum CaptureError: LocalizedError {
        case emptyViewport
        case missingImage
        case missingCGImage
        case cannotCreateDestination
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .emptyViewport:
                return "The page viewport is empty."
            case .missingImage, .missingCGImage:
                return "WebKit did not return a screenshot image."
            case .cannotCreateDestination:
                return "The screenshot file could not be created."
            case .writeFailed:
                return "The screenshot file could not be written."
            }
        }
    }
}
