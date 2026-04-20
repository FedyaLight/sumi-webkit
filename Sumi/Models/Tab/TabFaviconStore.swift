import AppKit
import Foundation
import ImageIO

enum TabFaviconStore {
    private static var faviconCache: [String: NSImage] = [:]
    private static var faviconCacheOrder: [String] = []
    private static let faviconCacheMaxSize = 200
    private static let faviconCacheLock = NSLock()
    private static let diskCacheFileExtension = "favicon"

    private static let faviconCacheDirectory: URL = {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let faviconDir = cacheDir.appendingPathComponent("FaviconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: faviconDir, withIntermediateDirectories: true)
        return faviconDir
    }()

    static func getCachedImage(for key: String) -> NSImage? {
        if let cachedImage = cachedMemoryImage(for: key) {
            return cachedImage
        }

        guard let diskImage = loadImageFromDisk(for: key) else {
            return nil
        }

        storeMemoryImage(diskImage, for: key)
        return diskImage
    }

    static func cacheImage(_ image: NSImage, rawData: Data? = nil, for key: String) {
        let evictedKeys = storeMemoryImage(image, for: key)
        saveImageToDisk(image, rawData: rawData, for: key)
        removeImagesFromDisk(for: evictedKeys)
    }

    static func clearMemoryCache() {
        faviconCacheLock.lock()
        faviconCache.removeAll()
        faviconCacheOrder.removeAll()
        faviconCacheLock.unlock()
    }

    static func clearCache() {
        clearMemoryCache()
        clearAllImagesFromDisk()
    }

    static func getFaviconCacheStats() -> (count: Int, domains: [String]) {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }
        return (faviconCache.count, Array(faviconCache.keys).sorted())
    }

    #if DEBUG
    static func debugDiskData(for key: String) -> Data? {
        let fileURL = diskFileURL(for: key)
        return try? Data(contentsOf: fileURL)
    }
    #endif

    @discardableResult
    private static func storeMemoryImage(_ image: NSImage, for key: String) -> [String] {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }

        faviconCache[key] = image
        markAccessed(key)

        guard faviconCache.count > faviconCacheMaxSize else {
            return []
        }

        let evictCount = faviconCache.count - faviconCacheMaxSize + 20
        let keysToRemove = Array(faviconCacheOrder.prefix(evictCount))
        for keyToRemove in keysToRemove {
            faviconCache.removeValue(forKey: keyToRemove)
        }
        faviconCacheOrder.removeFirst(min(evictCount, faviconCacheOrder.count))
        return keysToRemove
    }

    private static func cachedMemoryImage(for key: String) -> NSImage? {
        faviconCacheLock.lock()
        defer { faviconCacheLock.unlock() }

        guard let cachedImage = faviconCache[key] else {
            return nil
        }

        markAccessed(key)
        return cachedImage
    }

    private static func markAccessed(_ key: String) {
        faviconCacheOrder.removeAll { $0 == key }
        faviconCacheOrder.append(key)
    }

    private static func saveImageToDisk(_ image: NSImage, rawData: Data?, for key: String) {
        let fileURL = diskFileURL(for: key)

        if let rawData, !rawData.isEmpty {
            try? rawData.write(to: fileURL, options: .atomic)
            return
        }

        var proposedRect = NSRect(origin: .zero, size: image.size)
        let cgImage: CGImage?
        if proposedRect.isEmpty {
            cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else {
            cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        }

        guard let cgImage,
              let pngData = NSBitmapImageRep(cgImage: cgImage).representation(
                using: .png,
                properties: [:]
              )
        else {
            return
        }

        try? pngData.write(to: fileURL, options: .atomic)
    }

    private static func loadImageFromDisk(for key: String) -> NSImage? {
        let fileURL = diskFileURL(for: key)
        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }

        if let image = FaviconImageDecoder.image(from: imageData) {
            return image
        }

        try? FileManager.default.removeItem(at: fileURL)
        return nil
    }

    private static func removeImagesFromDisk(for keys: [String]) {
        for key in keys {
            try? FileManager.default.removeItem(at: diskFileURL(for: key))
        }
    }

    private static func clearAllImagesFromDisk() {
        try? FileManager.default.removeItem(at: faviconCacheDirectory)
        try? FileManager.default.createDirectory(
            at: faviconCacheDirectory,
            withIntermediateDirectories: true
        )
    }

    private static func diskFileURL(for key: String) -> URL {
        faviconCacheDirectory.appendingPathComponent(fileName(for: key, fileExtension: diskCacheFileExtension))
    }

    private static func fileName(for key: String, fileExtension: String) -> String {
        let hex = key.utf8.map { String(format: "%02x", $0) }.joined()
        return "\(hex).\(fileExtension)"
    }
}

enum FaviconImageDecoder {
    static let defaultMaxPixelSize = 64
    static let preferredMinimumPixelSize = 48

    static func image(from data: Data, maxPixelSize: Int = defaultMaxPixelSize) -> NSImage? {
        decodedImage(from: data, maxPixelSize: maxPixelSize)?.image
    }

    static func decodedImage(
        from data: Data,
        maxPixelSize: Int = defaultMaxPixelSize
    ) -> DecodedFaviconBitmap? {
        guard !data.isEmpty else {
            return nil
        }

        if let bitmap = makeThumbnail(from: data, maxPixelSize: maxPixelSize) {
            return DecodedFaviconBitmap(
                image: NSImage(
                    cgImage: bitmap.image,
                    size: NSSize(width: bitmap.image.width, height: bitmap.image.height)
                ),
                pixelWidth: bitmap.sourcePixelWidth,
                pixelHeight: bitmap.sourcePixelHeight
            )
        }

        guard let image = NSImage(data: data) else {
            return nil
        }

        let repSize = image.representations
            .compactMap { rep -> (width: Int, height: Int)? in
                let width = rep.pixelsWide > 0 ? rep.pixelsWide : Int(rep.size.width)
                let height = rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(rep.size.height)
                guard width > 0, height > 0 else {
                    return nil
                }
                return (width, height)
            }
            .max { lhs, rhs in
                lhs.width * lhs.height < rhs.width * rhs.height
            }

        return DecodedFaviconBitmap(
            image: image,
            pixelWidth: repSize?.width ?? Int(image.size.width),
            pixelHeight: repSize?.height ?? Int(image.size.height)
        )
    }

    private static func makeThumbnail(
        from data: Data,
        maxPixelSize: Int
    ) -> (image: CGImage, sourcePixelWidth: Int, sourcePixelHeight: Int)? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let imageCount = CGImageSourceGetCount(imageSource)
        guard imageCount > 0 else {
            return nil
        }

        let bestIndex = bestImageIndex(in: imageSource)
        let sourceSize = imageSize(in: imageSource, at: bestIndex)
        let sourcePixelWidth = max(1, sourceSize.width)
        let sourcePixelHeight = max(1, sourceSize.height)
        let targetPixelSize = max(16, maxPixelSize)

        if max(sourcePixelWidth, sourcePixelHeight) <= targetPixelSize,
           let cgImage = CGImageSourceCreateImageAtIndex(
            imageSource,
            bestIndex,
            [kCGImageSourceShouldCacheImmediately as String: true] as CFDictionary
           )
        {
            return (cgImage, sourcePixelWidth, sourcePixelHeight)
        }

        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: targetPixelSize,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceShouldCacheImmediately as String: true,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, bestIndex, options) else {
            return nil
        }

        return (cgImage, sourcePixelWidth, sourcePixelHeight)
    }

    private static func bestImageIndex(in imageSource: CGImageSource) -> Int {
        let imageCount = CGImageSourceGetCount(imageSource)
        var bestIndex = 0
        var bestArea = 0

        for index in 0..<imageCount {
            let size = imageSize(in: imageSource, at: index)
            let width = size.width
            let height = size.height
            let area = width * height

            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static func imageSize(in imageSource: CGImageSource, at index: Int) -> (width: Int, height: Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil)
                as? [CFString: Any]
        else {
            return (0, 0)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return (width, height)
    }

    static func isHighQualityEnough(_ bitmap: DecodedFaviconBitmap) -> Bool {
        max(bitmap.pixelWidth, bitmap.pixelHeight) >= preferredMinimumPixelSize
    }
}

struct DecodedFaviconBitmap {
    let image: NSImage
    let pixelWidth: Int
    let pixelHeight: Int
}
