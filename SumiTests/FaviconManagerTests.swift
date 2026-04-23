import AppKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class FaviconManagerTests: XCTestCase {
    func testHandleFaviconLinksPrefersPageLinksAndCachesImage() async throws {
        let faviconURL = URL(string: "https://example.com/apple-touch-icon.png")!
        let pageURL = URL(string: "https://example.com/article")!
        let downloader = RecordingFaviconDownloader { url in
            XCTAssertEqual(url, faviconURL)
            return try XCTUnwrap(Self.makeImageData(color: .systemOrange, size: 64))
        }

        let manager = FaviconManager(
            cacheType: .inMemory,
            downloader: downloader
        )

        let favicon = await manager.handleLiveFaviconLinks(
            [FaviconUserScript.FaviconLink(href: faviconURL, rel: "apple-touch-icon")],
            documentUrl: pageURL,
            webView: nil
        )

        XCTAssertEqual(downloader.recordedURLs, [faviconURL])
        XCTAssertEqual(favicon?.url, faviconURL)
        XCTAssertNotNil(
            manager.getCachedFavicon(
                for: pageURL,
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.image
        )
        XCTAssertNotNil(
            manager.getCachedFavicon(
                for: "example.com",
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.image
        )
    }

    func testHandleFaviconLinksPrefersDownscalingMediumOverUpscalingTinyForSmallIcons() async throws {
        let tinyURL = URL(string: "https://example.com/favicon-16.png")!
        let mediumURL = URL(string: "https://example.com/apple-touch-icon-180.png")!
        let pageURL = URL(string: "https://example.com/article")!
        let downloader = RecordingFaviconDownloader { url in
            switch url {
            case tinyURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemRed, size: 16))
            case mediumURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemBlue, size: 180))
            default:
                XCTFail("Unexpected download URL: \(url)")
                return Data()
            }
        }

        let manager = FaviconManager(
            cacheType: .inMemory,
            downloader: downloader
        )

        let favicon = await manager.handleLiveFaviconLinks(
            [
                FaviconUserScript.FaviconLink(href: tinyURL, rel: "icon"),
                FaviconUserScript.FaviconLink(href: mediumURL, rel: "apple-touch-icon"),
            ],
            documentUrl: pageURL,
            webView: nil
        )

        XCTAssertEqual(Set(downloader.recordedURLs), Set([tinyURL, mediumURL]))
        XCTAssertEqual(favicon?.url, mediumURL)
        XCTAssertEqual(
            manager.getCachedFavicon(
                for: pageURL,
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.url,
            mediumURL
        )
    }

    func testHandleFaviconLinksPrefersDownscalingLargeOverUpscalingTinyForSmallIcons() async throws {
        let tinyURL = URL(string: "https://example.com/favicon-16.png")!
        let largeURL = URL(string: "https://example.com/icon-512.png")!
        let pageURL = URL(string: "https://example.com/article")!
        let downloader = RecordingFaviconDownloader { url in
            switch url {
            case tinyURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemRed, size: 16))
            case largeURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemPurple, size: 512))
            default:
                XCTFail("Unexpected download URL: \(url)")
                return Data()
            }
        }

        let manager = FaviconManager(
            cacheType: .inMemory,
            downloader: downloader
        )

        let favicon = await manager.handleLiveFaviconLinks(
            [
                FaviconUserScript.FaviconLink(href: tinyURL, rel: "icon"),
                FaviconUserScript.FaviconLink(href: largeURL, rel: "icon"),
            ],
            documentUrl: pageURL,
            webView: nil
        )

        XCTAssertEqual(Set(downloader.recordedURLs), Set([tinyURL, largeURL]))
        XCTAssertEqual(favicon?.url, largeURL)
        XCTAssertEqual(
            manager.getCachedFavicon(
                for: pageURL,
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.url,
            largeURL
        )
    }

    func testHandleFaviconLinksPrefersDownscalingMediumOverExactSmallForSmallIcons() async throws {
        let smallURL = URL(string: "https://example.com/icon-32.png")!
        let mediumURL = URL(string: "https://example.com/apple-touch-icon-180.png")!
        let pageURL = URL(string: "https://example.com/article")!
        let downloader = RecordingFaviconDownloader { url in
            switch url {
            case smallURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemRed, size: 32))
            case mediumURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemBlue, size: 180))
            default:
                XCTFail("Unexpected download URL: \(url)")
                return Data()
            }
        }

        let manager = FaviconManager(
            cacheType: .inMemory,
            downloader: downloader
        )

        let favicon = await manager.handleLiveFaviconLinks(
            [
                FaviconUserScript.FaviconLink(href: smallURL, rel: "icon"),
                FaviconUserScript.FaviconLink(href: mediumURL, rel: "icon"),
            ],
            documentUrl: pageURL,
            webView: nil
        )

        XCTAssertEqual(Set(downloader.recordedURLs), Set([smallURL, mediumURL]))
        XCTAssertEqual(favicon?.url, mediumURL)
        XCTAssertEqual(
            manager.getCachedFavicon(
                for: pageURL,
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.url,
            mediumURL
        )
    }

    func testFallbackUsesCurrentSchemeThenHTTPSUpgrade() async throws {
        let pageURL = URL(string: "http://upgrade.example.com/path")!
        let httpFallbackURL = URL(string: "http://upgrade.example.com/favicon.ico")!
        let httpsFallbackURL = URL(string: "https://upgrade.example.com/favicon.ico")!
        let downloader = RecordingFaviconDownloader { url in
            if url == httpFallbackURL {
                throw URLError(.badServerResponse)
            }

            XCTAssertEqual(url, httpsFallbackURL)
            return try XCTUnwrap(Self.makeImageData(color: .systemBlue, size: 48))
        }

        let manager = FaviconManager(
            cacheType: .inMemory,
            downloader: downloader
        )

        let favicon = await manager.loadFavicon(for: pageURL, webView: nil)

        XCTAssertEqual(Set(downloader.recordedURLs), Set([httpFallbackURL, httpsFallbackURL]))
        XCTAssertEqual(favicon?.url, httpsFallbackURL)
        XCTAssertNotNil(
            manager.getCachedFavicon(
                for: "upgrade.example.com",
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.image
        )
    }

    func testLoadFaviconDoesNotDowngradeExistingPageProvidedIcon() async throws {
        let pageURL = URL(string: "https://example.com/article")!
        let pageIconURL = URL(string: "https://example.com/apple-touch-icon.png")!
        let fallbackURL = URL(string: "https://example.com/favicon.ico")!
        let downloader = RecordingFaviconDownloader { url in
            switch url {
            case pageIconURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemBlue, size: 180))
            case fallbackURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemRed, size: 16))
            default:
                XCTFail("Unexpected download URL: \(url)")
                return Data()
            }
        }

        let manager = FaviconManager(
            cacheType: .inMemory,
            downloader: downloader
        )

        let initial = await manager.handleLiveFaviconLinks(
            [FaviconUserScript.FaviconLink(href: pageIconURL, rel: "apple-touch-icon")],
            documentUrl: pageURL,
            webView: nil
        )
        let resolvedAfterFallback = await manager.loadFavicon(for: pageURL, webView: nil)

        XCTAssertEqual(initial?.url, pageIconURL)
        XCTAssertEqual(resolvedAfterFallback?.url, pageIconURL)
        XCTAssertEqual(
            manager.getCachedFavicon(
                for: pageURL,
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.url,
            pageIconURL
        )
        XCTAssertEqual(downloader.recordedURLs, [pageIconURL])
    }

    func testHandleLiveFaviconLinksDoesNotClearExistingReferenceWhenNewBatchFails() async throws {
        let pageURL = URL(string: "https://example.com/article")!
        let initialURL = URL(string: "https://example.com/initial.png")!
        let failingURL = URL(string: "https://example.com/failing.png")!
        let downloader = RecordingFaviconDownloader { url in
            switch url {
            case initialURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemGreen, size: 128))
            case failingURL:
                throw URLError(.cannotDecodeRawData)
            default:
                XCTFail("Unexpected download URL: \(url)")
                return Data()
            }
        }

        let manager = FaviconManager(
            cacheType: .inMemory,
            downloader: downloader
        )

        _ = await manager.handleLiveFaviconLinks(
            [FaviconUserScript.FaviconLink(href: initialURL, rel: "icon")],
            documentUrl: pageURL,
            webView: nil
        )
        let resolved = await manager.handleLiveFaviconLinks(
            [FaviconUserScript.FaviconLink(href: failingURL, rel: "icon")],
            documentUrl: pageURL,
            webView: nil
        )

        XCTAssertEqual(resolved?.url, initialURL)
        XCTAssertEqual(
            manager.getCachedFavicon(
                for: pageURL,
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.url,
            initialURL
        )
        XCTAssertEqual(downloader.recordedURLs, [initialURL, failingURL])
    }

    func testInvalidPayloadsDoNotReplaceExistingCachedFavicon() async throws {
        let pageURL = URL(string: "https://example.com/article")!
        let initialURL = URL(string: "https://example.com/initial.png")!
        let htmlURL = URL(string: "https://example.com/html-fallback")!
        let tinyGarbageURL = URL(string: "https://example.com/tiny-garbage")!
        let downloader = RecordingFaviconDownloader { url in
            switch url {
            case initialURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemOrange, size: 128))
            case htmlURL:
                return Data("""
                <!doctype html><html><head><title>not an image</title></head><body></body></html>
                """.utf8)
            case tinyGarbageURL:
                return Data([0x00])
            default:
                XCTFail("Unexpected download URL: \(url)")
                return Data()
            }
        }

        let manager = FaviconManager(
            cacheType: .inMemory,
            downloader: downloader
        )

        _ = await manager.handleLiveFaviconLinks(
            [FaviconUserScript.FaviconLink(href: initialURL, rel: "icon")],
            documentUrl: pageURL,
            webView: nil
        )
        let afterHTML = await manager.handleLiveFaviconLinks(
            [FaviconUserScript.FaviconLink(href: htmlURL, rel: "icon")],
            documentUrl: pageURL,
            webView: nil
        )
        let afterGarbage = await manager.handleLiveFaviconLinks(
            [FaviconUserScript.FaviconLink(href: tinyGarbageURL, rel: "icon")],
            documentUrl: pageURL,
            webView: nil
        )

        XCTAssertEqual(afterHTML?.url, initialURL)
        XCTAssertEqual(afterGarbage?.url, initialURL)
        XCTAssertEqual(
            manager.getCachedFavicon(
                for: pageURL,
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.url,
            initialURL
        )
        XCTAssertEqual(downloader.recordedURLs, [initialURL, htmlURL, tinyGarbageURL])
    }

    func testPersistentStoreReloadsCachedHostLookupForLaunchersAndHistory() async throws {
        let storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = storeDirectory.appendingPathComponent("favicons.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: storeDirectory)
        }

        let faviconURL = URL(string: "https://persist.example.com/favicon.ico")!
        let pageURL = URL(string: "https://persist.example.com/path")!
        let imageData = try XCTUnwrap(Self.makeImageData(color: .systemGreen, size: 64))

        let writer = FaviconManager(
            cacheType: .standard(storeURL: storeURL),
            downloader: RecordingFaviconDownloader { _ in imageData }
        )

        _ = await writer.handleLiveFaviconLinks(
            [FaviconUserScript.FaviconLink(href: faviconURL, rel: "icon")],
            documentUrl: pageURL,
            webView: nil
        )

        let reader = FaviconManager(
            cacheType: .standard(storeURL: storeURL),
            downloader: RecordingFaviconDownloader { _ in
                XCTFail("Reader should not re-download cached favicon")
                return imageData
            }
        )
        await reader.waitUntilLoaded()

        XCTAssertEqual(
            reader.getCachedFavicon(
                for: pageURL,
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.url,
            faviconURL
        )
        XCTAssertEqual(
            reader.getCachedFavicon(
                for: "persist.example.com",
                sizeCategory: .small,
                fallBackToSmaller: true
            )?.url,
            faviconURL
        )
        XCTAssertNotNil(reader.image(forLookupKey: "persist.example.com"))
    }

    func testLoadCachesClearsDirtyStoreWhenDuplicateFaviconURLsExist() async throws {
        let faviconURL = URL(string: "https://dirty.example.com/favicon.ico")!
        let documentURL = URL(string: "https://dirty.example.com/page")!
        let image = try XCTUnwrap(
            Self.makeImageData(color: .systemOrange, size: 64).flatMap(NSImage.init(data:))
        )
        let duplicateFavicons = [
            Favicon(
                identifier: UUID(),
                url: faviconURL,
                image: image,
                relationString: "icon",
                documentUrl: documentURL,
                dateCreated: Date().addingTimeInterval(-10)
            ),
            Favicon(
                identifier: UUID(),
                url: faviconURL,
                image: image,
                relationString: "icon",
                documentUrl: documentURL,
                dateCreated: Date()
            ),
        ]
        let store = DirtyFaviconStore(favicons: duplicateFavicons)
        let manager = FaviconManager(
            store: store,
            downloader: RecordingFaviconDownloader { _ in Data() }
        )

        await manager.waitUntilLoaded()

        XCTAssertEqual(store.clearAllCallCount, 1)
        XCTAssertTrue(manager.isCacheLoaded)
        XCTAssertNil(
            manager.getCachedFavicon(
                for: documentURL,
                sizeCategory: .small,
                fallBackToSmaller: true
            )
        )
    }

    func testLoadCachesClearsDirtyStoreWhenDuplicateReferenceKeysExist() async throws {
        let documentURL = URL(string: "https://dirty.example.com/page")!
        let faviconURL = URL(string: "https://dirty.example.com/favicon.ico")!
        let duplicateReferences = (
            [
                FaviconHostReference(
                    identifier: UUID(),
                    smallFaviconUrl: faviconURL,
                    mediumFaviconUrl: faviconURL,
                    host: "dirty.example.com",
                    documentUrl: documentURL,
                    dateCreated: Date().addingTimeInterval(-10)
                ),
                FaviconHostReference(
                    identifier: UUID(),
                    smallFaviconUrl: faviconURL,
                    mediumFaviconUrl: faviconURL,
                    host: "dirty.example.com",
                    documentUrl: documentURL,
                    dateCreated: Date()
                ),
            ],
            [FaviconUrlReference]()
        )
        let store = DirtyFaviconStore(references: duplicateReferences)
        let manager = FaviconManager(
            store: store,
            downloader: RecordingFaviconDownloader { _ in Data() }
        )

        await manager.waitUntilLoaded()

        XCTAssertEqual(store.clearAllCallCount, 1)
        XCTAssertTrue(manager.isCacheLoaded)
        XCTAssertNil(
            manager.getCachedFavicon(
                for: "dirty.example.com",
                sizeCategory: .small,
                fallBackToSmaller: true
            )
        )
    }

    func testDownloaderRetainsTemporaryDownloadSurfaceUntilSessionCompletes() async throws {
        let url = URL(string: "https://example.com/favicon.png")!
        let session = ControlledFaviconDownloadSession()
        weak var weakSurface: RetainedDownloadSurface?

        let downloader = FaviconDownloader(
            startDownloadSession: { request, webView in
                XCTAssertEqual(request.url, url)
                XCTAssertNil(webView)

                let surface = RetainedDownloadSurface()
                weakSurface = surface
                return (session, surface)
            }
        )

        let downloadTask = Task {
            try await downloader.download(from: url, using: nil)
        }

        await Task.yield()
        XCTAssertNotNil(weakSurface)

        let imageData = try XCTUnwrap(Self.makeImageData(color: .systemTeal, size: 24))
        try await session.finish(with: imageData, url: url)

        let resolvedData = try await downloadTask.value
        XCTAssertEqual(resolvedData, imageData)
        XCTAssertNil(weakSurface)
    }

    private static func makeImageData(color: NSColor, size: CGFloat) -> Data? {
        let pixelSize = max(1, Int(size.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor
private final class ControlledFaviconDownloadSession: FaviconDownloadSession {
    weak var delegate: (any FaviconDownloadSessionDelegate)?

    func cancel(_ completionHandler: @escaping @Sendable (Data?) -> Void) {
        completionHandler(nil)
    }

    func finish(with data: Data, url: URL, suggestedFilename: String = "favicon.png") async throws {
        let response = URLResponse(
            url: url,
            mimeType: "image/png",
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        guard let destinationURL = await delegate?.faviconDownloadSession(
            self,
            decideDestinationUsing: response,
            suggestedFilename: suggestedFilename
        ) else {
            XCTFail("Expected download destination URL")
            return
        }

        try data.write(to: destinationURL)
        delegate?.faviconDownloadSessionDidFinish(self)
    }
}

private final class RetainedDownloadSurface {
}

@MainActor
private final class RecordingFaviconDownloader: FaviconDownloading {
    private let handler: (URL) throws -> Data
    private(set) var recordedURLs: [URL] = []

    init(handler: @escaping (URL) throws -> Data) {
        self.handler = handler
    }

    func download(from url: URL, using webView: WKWebView?) async throws -> Data {
        _ = webView
        recordedURLs.append(url)
        return try handler(url)
    }
}

private final class DirtyFaviconStore: FaviconStoring {
    private let faviconsToLoad: [Favicon]
    private let referencesToLoad: ([FaviconHostReference], [FaviconUrlReference])

    private(set) var clearAllCallCount = 0

    init(
        favicons: [Favicon] = [],
        references: ([FaviconHostReference], [FaviconUrlReference]) = ([], [])
    ) {
        self.faviconsToLoad = favicons
        self.referencesToLoad = references
    }

    func loadFavicons() async throws -> [Favicon] {
        faviconsToLoad
    }

    func save(_ favicons: [Favicon]) async throws {
        _ = favicons
    }

    func removeFavicons(_ favicons: [Favicon]) async throws {
        _ = favicons
    }

    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference]) {
        referencesToLoad
    }

    func save(hostReference: FaviconHostReference) async throws {
        _ = hostReference
    }

    func save(urlReference: FaviconUrlReference) async throws {
        _ = urlReference
    }

    func remove(hostReferences: [FaviconHostReference]) async throws {
        _ = hostReferences
    }

    func remove(urlReferences: [FaviconUrlReference]) async throws {
        _ = urlReferences
    }

    func clearAll() throws {
        clearAllCallCount += 1
    }
}
