import AppKit
import Common
import Persistence
import UserScript
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class FaviconManagerTests: XCTestCase {
    func testHandleFaviconLinksPrefersPageLinksAndCachesDocumentAndHost() async throws {
        let faviconURL = URL(string: "https://example.com/apple-touch-icon.png")!
        let pageURL = URL(string: "https://example.com/article")!
        let downloader = RecordingFaviconDownloader { url in
            XCTAssertEqual(url, faviconURL)
            return try XCTUnwrap(Self.makeImageData(color: .systemOrange, size: 64))
        }
        let manager = makeManager(downloader: downloader)

        let favicon = await manager.handleFaviconLinks(
            [FaviconUserScript.FaviconLink(href: faviconURL, rel: "apple-touch-icon", type: "image/png")],
            documentUrl: pageURL,
            webView: nil
        )

        XCTAssertEqual(downloader.recordedURLs, [faviconURL])
        XCTAssertEqual(favicon?.url, faviconURL)
        XCTAssertEqual(
            manager.getCachedFavicon(for: pageURL, sizeCategory: .small, fallBackToSmaller: true)?.url,
            faviconURL
        )
        XCTAssertEqual(
            manager.getCachedFavicon(for: "example.com", sizeCategory: .small, fallBackToSmaller: true)?.url,
            faviconURL
        )
    }

    func testHandleFaviconLinksAcceptsSVGFaviconsOnMacOSAndCachesDocumentAndHost() async throws {
        let faviconURL = URL(string: "https://svg.example.com/favicon.svg")!
        let pageURL = URL(string: "https://svg.example.com/article")!
        let svgData = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
              <rect width="128" height="128" fill="#0074D8"/>
              <circle cx="64" cy="64" r="36" fill="#FFFFFF"/>
            </svg>
            """.utf8
        )
        let downloader = RecordingFaviconDownloader { url in
            XCTAssertEqual(url, faviconURL)
            return svgData
        }
        let manager = makeManager(downloader: downloader)

        let favicon = await manager.handleFaviconLinks(
            [FaviconUserScript.FaviconLink(href: faviconURL, rel: "icon", type: "image/svg+xml")],
            documentUrl: pageURL,
            webView: nil
        )

        XCTAssertEqual(downloader.recordedURLs, [faviconURL])
        XCTAssertEqual(favicon?.url, faviconURL)
        XCTAssertEqual(
            manager.getCachedFavicon(for: pageURL, sizeCategory: .small, fallBackToSmaller: true)?.url,
            faviconURL
        )
        XCTAssertEqual(
            manager.getCachedFavicon(for: "svg.example.com", sizeCategory: .small, fallBackToSmaller: true)?.url,
            faviconURL
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
        let manager = makeManager(downloader: downloader)

        let favicon = await manager.handleFaviconLinks([], documentUrl: pageURL, webView: nil)

        XCTAssertEqual(Set(downloader.recordedURLs), Set([httpFallbackURL, httpsFallbackURL]))
        XCTAssertEqual(favicon?.url, httpsFallbackURL)
        XCTAssertEqual(
            manager.getCachedFavicon(for: "upgrade.example.com", sizeCategory: .small, fallBackToSmaller: true)?.url,
            httpsFallbackURL
        )
    }

    func testFallbackOnlyCallDoesNotDowngradeExistingPageProvidedIcon() async throws {
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
        let manager = makeManager(downloader: downloader)

        let initial = await manager.handleFaviconLinks(
            [FaviconUserScript.FaviconLink(href: pageIconURL, rel: "apple-touch-icon", type: "image/png")],
            documentUrl: pageURL,
            webView: nil
        )
        let resolvedAfterFallbackOnlyCall = await manager.handleFaviconLinks([], documentUrl: pageURL, webView: nil)

        XCTAssertEqual(initial?.url, pageIconURL)
        XCTAssertEqual(resolvedAfterFallbackOnlyCall?.url, pageIconURL)
        XCTAssertEqual(downloader.recordedURLs, [pageIconURL])
        XCTAssertEqual(
            manager.getCachedFavicon(for: pageURL, sizeCategory: .small, fallBackToSmaller: true)?.url,
            pageIconURL
        )
    }

    func testFailedOrInvalidBatchDoesNotClearExistingReference() async throws {
        let pageURL = URL(string: "https://example.com/article")!
        let initialURL = URL(string: "https://example.com/initial.png")!
        let failingURL = URL(string: "https://example.com/failing.png")!
        let htmlURL = URL(string: "https://example.com/not-image")!
        let tinyGarbageURL = URL(string: "https://example.com/tiny-garbage")!
        let downloader = RecordingFaviconDownloader { url in
            switch url {
            case initialURL:
                return try XCTUnwrap(Self.makeImageData(color: .systemGreen, size: 128))
            case failingURL:
                throw URLError(.cannotDecodeRawData)
            case htmlURL:
                return Data("<!doctype html><html><body>not an image</body></html>".utf8)
            case tinyGarbageURL:
                return Data([0x00])
            default:
                XCTFail("Unexpected download URL: \(url)")
                return Data()
            }
        }
        let manager = makeManager(downloader: downloader)

        _ = await manager.handleFaviconLinks(
            [FaviconUserScript.FaviconLink(href: initialURL, rel: "icon", type: "image/png")],
            documentUrl: pageURL,
            webView: nil
        )
        let afterFailure = await manager.handleFaviconLinks(
            [FaviconUserScript.FaviconLink(href: failingURL, rel: "icon", type: "image/png")],
            documentUrl: pageURL,
            webView: nil
        )
        let afterHTML = await manager.handleFaviconLinks(
            [FaviconUserScript.FaviconLink(href: htmlURL, rel: "icon", type: "text/html")],
            documentUrl: pageURL,
            webView: nil
        )
        let afterGarbage = await manager.handleFaviconLinks(
            [FaviconUserScript.FaviconLink(href: tinyGarbageURL, rel: "icon")],
            documentUrl: pageURL,
            webView: nil
        )

        XCTAssertEqual(afterFailure?.url, initialURL)
        XCTAssertEqual(afterHTML?.url, initialURL)
        XCTAssertEqual(afterGarbage?.url, initialURL)
        XCTAssertEqual(
            manager.getCachedFavicon(for: pageURL, sizeCategory: .small, fallBackToSmaller: true)?.url,
            initialURL
        )
        XCTAssertEqual(downloader.recordedURLs, [initialURL, failingURL, htmlURL, tinyGarbageURL])
    }

    func testPersistentStoreReloadsCachedHostLookupForPassiveConsumers() async throws {
        let storeDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        let database = try await Self.makeFaviconDatabase(in: storeDirectory)
        let faviconURL = URL(string: "https://persist.example.com/favicon.ico")!
        let pageURL = URL(string: "https://persist.example.com/path")!
        let imageData = try XCTUnwrap(Self.makeImageData(color: .systemGreen, size: 64))
        let writerStore = FaviconStore(database: database)
        let writer = makeManager(
            store: writerStore,
            downloader: RecordingFaviconDownloader { _ in imageData }
        )

        _ = await writer.handleFaviconLinks(
            [FaviconUserScript.FaviconLink(href: faviconURL, rel: "icon", type: "image/png")],
            documentUrl: pageURL,
            webView: nil
        )
        try await waitUntilStoreHasReferences(writerStore)

        let reader = makeManager(
            store: FaviconStore(database: database),
            downloader: RecordingFaviconDownloader { _ in
                XCTFail("Reader should not re-download cached favicon")
                return imageData
            }
        )
        await reader.waitUntilLoaded()

        XCTAssertEqual(
            reader.getCachedFavicon(for: pageURL, sizeCategory: .small, fallBackToSmaller: true)?.url,
            faviconURL
        )
        XCTAssertEqual(
            reader.getCachedFavicon(for: "persist.example.com", sizeCategory: .small, fallBackToSmaller: true)?.url,
            faviconURL
        )
        XCTAssertNotNil(reader.image(forLookupKey: "persist.example.com"))
    }

    func testLoadCachesClearDirtyStoreAfterLoadFailure() async throws {
        let store = ThrowingFaviconStore(loadError: CocoaError(.fileReadCorruptFile))
        let manager = makeManager(
            store: store,
            downloader: RecordingFaviconDownloader { _ in Data() }
        )

        await manager.waitUntilLoaded()

        XCTAssertEqual(store.clearAllCallCount, 1)
        XCTAssertTrue(manager.isCacheLoaded)
    }

    private func makeManager(
        store: FaviconStoring = FaviconNullStore(),
        downloader: RecordingFaviconDownloader,
        bookmarkManager: TestBookmarkManager? = nil
    ) -> FaviconManager {
        let bookmarkManager = bookmarkManager ?? TestBookmarkManager()
        return FaviconManager(
            store: store,
            bookmarkManager: bookmarkManager,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStore(context: nil), tld: TLD()),
            privacyConfigurationManager: SumiStaticPrivacyConfigurationManager(),
            faviconDownloader: downloader
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func makeFaviconDatabase(in directory: URL) async throws -> CoreDataDatabase {
        FaviconValueTransformers.register()
        let model = CoreDataDatabase.loadModel(from: .main, named: "Favicons")
            ?? CoreDataDatabase.loadModel(from: Bundle(for: FaviconManagedObject.self), named: "Favicons")
        let unwrappedModel = try XCTUnwrap(model)
        let database = CoreDataDatabase(name: "Favicons", containerLocation: directory, model: unwrappedModel)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.loadStore { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        return database
    }

    private func waitUntilStoreHasReferences(_ store: FaviconStore) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let favicons = try await store.loadFavicons()
            let references = try await store.loadFaviconReferences()
            if !favicons.isEmpty, !references.0.isEmpty || !references.1.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for favicon store persistence")
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
private final class TestBookmarkManager: BookmarkManager {
    var hosts = Set<String>()

    func allHosts() -> Set<String> {
        hosts
    }
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

private final class ThrowingFaviconStore: FaviconStoring {
    private let loadError: Error
    private(set) var clearAllCallCount = 0
    private var didThrow = false

    init(loadError: Error) {
        self.loadError = loadError
    }

    func loadFavicons() async throws -> [Favicon] {
        if !didThrow {
            didThrow = true
            throw loadError
        }
        return []
    }

    func save(_ favicons: [Favicon]) async throws {
        _ = favicons
    }

    func removeFavicons(_ favicons: [Favicon]) async throws {
        _ = favicons
    }

    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference]) {
        ([], [])
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

    func clearAll() async throws {
        clearAllCallCount += 1
    }
}
