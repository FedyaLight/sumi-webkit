import Foundation
import ImageIO

enum SumiFaviconPayloadValidator {
    static func validate(
        data: Data,
        responseMimeType: String?,
        candidate: SumiFaviconCandidate
    ) -> SumiFaviconValidationResult {
        guard !data.isEmpty else {
            return .invalid(.invalidPayload)
        }
        guard data.count <= SumiFaviconConstants.maxPayloadBytes else {
            return .invalid(.oversizedPayload)
        }
        guard !looksLikeHTML(data) else {
            return .invalid(.htmlPayload)
        }

        let declaredType = candidate.declaredType ?? responseMimeType
        let sniffedKind = payloadKind(data: data, declaredType: declaredType, url: candidate.iconURL)

        switch sniffedKind {
        case .svg:
            guard data.count <= SumiFaviconConstants.maxSVGPayloadBytes else {
                return .invalid(.oversizedPayload)
            }
            guard isSafeSVG(data) else {
                return .invalid(.unsafeSVG)
            }
            return .valid(
                SumiFaviconValidatedPayload(
                    data: data,
                    payloadKind: .svg,
                    mimeType: "image/svg+xml",
                    pixelWidth: nil,
                    pixelHeight: nil,
                    byteCount: data.count
                )
            )

        case .png, .jpeg, .gif, .webp, .ico, .unknownRaster:
            return validateRaster(
                data: data,
                payloadKind: sniffedKind,
                mimeType: declaredType,
                candidate: candidate
            )
        }
    }

    private static func validateRaster(
        data: Data,
        payloadKind: SumiFaviconPayloadKind,
        mimeType: String?,
        candidate: SumiFaviconCandidate
    ) -> SumiFaviconValidationResult {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else {
            return .invalid(.invalidPayload)
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            return .invalid(.invalidPayload)
        }

        var bestWidth = 0
        var bestHeight = 0
        var hasUsableFrame = false
        let target = max(
            SumiFaviconConstants.maxDecodedMasterPixelSize,
            candidate.declaredSizes.map(\.longestSide).max() ?? 0
        )

        for index in 0..<frameCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0,
                  height > 0
            else {
                continue
            }

            guard width * height <= SumiFaviconConstants.maxRasterPixels else {
                continue
            }

            hasUsableFrame = true
            if bestWidth == 0 || frameScore(width: width, height: height, target: target) < frameScore(width: bestWidth, height: bestHeight, target: target) {
                bestWidth = width
                bestHeight = height
            }
        }

        guard hasUsableFrame else {
            return .invalid(.oversizedPixels)
        }

        return .valid(
            SumiFaviconValidatedPayload(
                data: data,
                payloadKind: payloadKind,
                mimeType: normalizedMimeType(mimeType, fallback: payloadKind),
                pixelWidth: bestWidth,
                pixelHeight: bestHeight,
                byteCount: data.count
            )
        )
    }

    static func bestImageIndex(in source: CGImageSource, targetPixelSize: Int) -> Int {
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return 0 }

        var bestIndex = 0
        var bestScore = Int.max
        for index in 0..<count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0,
                  height > 0,
                  width * height <= SumiFaviconConstants.maxRasterPixels
            else {
                continue
            }
            let score = frameScore(width: width, height: height, target: targetPixelSize)
            if score < bestScore {
                bestIndex = index
                bestScore = score
            }
        }
        return bestIndex
    }

    private static func frameScore(width: Int, height: Int, target: Int) -> Int {
        let longest = max(width, height)
        if longest >= target {
            return longest - target
        }
        return 10_000 + target - longest
    }

    private static func payloadKind(
        data: Data,
        declaredType: String?,
        url: URL
    ) -> SumiFaviconPayloadKind {
        let lowerType = declaredType?.lowercased()
        let ext = url.pathExtension.lowercased()
        if lowerType == "image/svg+xml" || ext == "svg" || looksLikeSVG(data) {
            return .svg
        }
        if starts(with: [0x89, 0x50, 0x4E, 0x47], data: data) || lowerType == "image/png" || ext == "png" {
            return .png
        }
        if starts(with: [0xFF, 0xD8, 0xFF], data: data) || lowerType == "image/jpeg" || lowerType == "image/jpg" || ext == "jpg" || ext == "jpeg" {
            return .jpeg
        }
        if starts(withASCII: "GIF8", data: data) || lowerType == "image/gif" || ext == "gif" {
            return .gif
        }
        if starts(withASCII: "RIFF", data: data), data.count >= 12 {
            let webpRange = 8..<12
            if String(data: data[webpRange], encoding: .ascii) == "WEBP" {
                return .webp
            }
        }
        if starts(with: [0x00, 0x00, 0x01, 0x00], data: data)
            || lowerType == "image/x-icon"
            || lowerType == "image/vnd.microsoft.icon"
            || ext == "ico" {
            return .ico
        }
        return .unknownRaster
    }

    private static func normalizedMimeType(
        _ mimeType: String?,
        fallback: SumiFaviconPayloadKind
    ) -> String? {
        if let mimeType, !mimeType.isEmpty {
            return mimeType.lowercased()
        }
        switch fallback {
        case .png:
            return "image/png"
        case .jpeg:
            return "image/jpeg"
        case .gif:
            return "image/gif"
        case .webp:
            return "image/webp"
        case .ico:
            return "image/x-icon"
        case .svg:
            return "image/svg+xml"
        case .unknownRaster:
            return nil
        }
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        let prefix = asciiPrefix(data, limit: 512)
        return prefix.contains("<html")
            || prefix.contains("<!doctype html")
            || prefix.contains("<head")
            || prefix.contains("<body")
            || prefix.contains("<title")
    }

    private static func looksLikeSVG(_ data: Data) -> Bool {
        let prefix = asciiPrefix(data, limit: 512)
        return prefix.contains("<svg") || prefix.contains("<?xml")
    }

    private static func isSafeSVG(_ data: Data) -> Bool {
        guard let string = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
        else {
            return false
        }

        let lower = string.lowercased()
        let unsafeFragments = [
            "<script",
            "javascript:",
            "data:text/html",
            "<foreignobject",
            "<iframe",
            "<object",
            "<embed",
            "<image",
            "xlink:href=\"http",
            "href=\"http://",
            "href=\"https://",
            "url(http://",
            "url(https://",
            "onload=",
            "onclick=",
            "onerror=",
            "onmouseover=",
        ]
        return unsafeFragments.contains { lower.contains($0) } == false
    }

    private static func starts(with bytes: [UInt8], data: Data) -> Bool {
        guard data.count >= bytes.count else { return false }
        return zip(data.prefix(bytes.count), bytes).allSatisfy { $0 == $1 }
    }

    private static func starts(withASCII ascii: String, data: Data) -> Bool {
        guard let bytes = ascii.data(using: .ascii) else { return false }
        return data.prefix(bytes.count) == bytes
    }

    private static func asciiPrefix(_ data: Data, limit: Int) -> String {
        let prefix = data.prefix(limit)
        return String(data: prefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""
    }
}
