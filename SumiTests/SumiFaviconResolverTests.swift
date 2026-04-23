import AppKit
import Foundation
import XCTest
@testable import Sumi

final class SumiFaviconResolverTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TabFaviconStore.clearCache()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        TabFaviconStore.clearCache()
        super.tearDown()
    }

    func testCacheKeyLowercasesHost() {
        let key = SumiFaviconResolver.cacheKey(
            for: URL(string: "https://Example.COM/articles/123")!
        )

        XCTAssertEqual(key, "example.com")
    }

    func testNonHTTPURLSkipsNetwork() async {
        let resolver = makeResolver()
        let image = await resolver.image(for: URL(fileURLWithPath: "/tmp/local-file"))

        XCTAssertNil(image)
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.count, 0)
    }

    func testMemoryHitSkipsNetwork() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://memory-hit.example.com/article")!
        let key = SumiFaviconResolver.cacheKey(for: pageURL)!
        let cachedImage = makeImage()
        TabFaviconStore.cacheImage(cachedImage, for: key)

        let resolvedImage = await resolver.image(for: pageURL)

        XCTAssertNotNil(resolvedImage)
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.count, 0)
    }

    func testDiskHitSkipsNetwork() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://disk-hit.example.com/article")!
        let key = SumiFaviconResolver.cacheKey(for: pageURL)!
        TabFaviconStore.cacheImage(makeImage(), for: key)
        TabFaviconStore.clearMemoryCache()

        let resolvedImage = await resolver.image(for: pageURL)

        XCTAssertNotNil(resolvedImage)
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.count, 0)
    }

    func testInFlightRequestsAreDeduplicated() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://dedupe.example.com/path")!
        let faviconURL = URL(string: "https://dedupe.example.com/favicon.ico")!
        let pngData = makePNGData()

        StubURLProtocol.setHandler { request in
            XCTAssertEqual(request.url, faviconURL)
            Thread.sleep(forTimeInterval: 0.05)
            return StubURLProtocol.Response(
                statusCode: 200,
                data: pngData,
                url: faviconURL
            )
        }

        async let first = resolver.image(for: pageURL)
        async let second = resolver.image(for: pageURL)
        let images = await [first, second]

        XCTAssertNotNil(images[0])
        XCTAssertNotNil(images[1])
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.count, 1)
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.first, faviconURL)
    }

    func testNegativeCacheSuppressesRepeatedMisses() async {
        let resolver = makeResolver(negativeCacheTTL: 60)
        let pageURL = URL(string: "https://negative-cache.example.com/article")!

        StubURLProtocol.setHandler { request in
            StubURLProtocol.Response(
                statusCode: 404,
                data: Data(),
                url: request.url ?? pageURL
            )
        }

        let firstResult = await resolver.image(for: pageURL)
        let firstCount = StubURLProtocol.recordedRequestURLs.count
        let secondResult = await resolver.image(for: pageURL)
        let secondCount = StubURLProtocol.recordedRequestURLs.count

        XCTAssertNil(firstResult)
        XCTAssertNil(secondResult)
        XCTAssertEqual(firstCount, 3)
        XCTAssertEqual(secondCount, firstCount)
    }

    func testDiscoveredFaviconBypassesNegativeCacheAndCachesImage() async {
        let resolver = makeResolver(negativeCacheTTL: 60)
        let pageURL = URL(string: "https://discovered-negative.example.com/article")!
        let discoveredIconURL = URL(string: "https://cdn.example.com/discovered-icon.png")!
        let key = SumiFaviconResolver.cacheKey(for: pageURL)!

        StubURLProtocol.setHandler { request in
            StubURLProtocol.Response(
                statusCode: 404,
                data: Data(),
                url: request.url ?? pageURL
            )
        }

        let initialMiss = await resolver.image(for: pageURL)
        XCTAssertNil(initialMiss)
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.count, 3)

        StubURLProtocol.reset()
        let pngData = makePNGData(size: 64)
        StubURLProtocol.setHandler { request in
            XCTAssertEqual(request.url, discoveredIconURL)
            return StubURLProtocol.Response(
                statusCode: 200,
                data: pngData,
                url: discoveredIconURL
            )
        }

        let image = await resolver.image(
            for: pageURL,
            discoveredLinks: [
                SumiDiscoveredFaviconLink(
                    url: discoveredIconURL,
                    relation: "icon",
                    sizes: "64x64"
                )
            ]
        )

        XCTAssertNotNil(image)
        XCTAssertNotNil(TabFaviconStore.getCachedImage(for: key))
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs, [discoveredIconURL])
    }

    @MainActor
    func testTabKeepsExistingFaviconForSameHostCacheMiss() {
        let firstURL = URL(string: "https://same-host.example.com/first")!
        let secondURL = URL(string: "https://same-host.example.com/second")!
        let key = SumiFaviconResolver.cacheKey(for: firstURL)!
        let tab = Tab(url: firstURL, name: "Same Host", skipFaviconFetch: true)

        TabFaviconStore.cacheImage(makeImage(), for: key)
        XCTAssertTrue(tab.applyCachedFaviconOrPlaceholder(for: firstURL))
        XCTAssertFalse(tab.faviconIsTemplateGlobePlaceholder)

        TabFaviconStore.clearCache()
        XCTAssertFalse(tab.applyCachedFaviconOrPlaceholder(for: secondURL))
        XCTAssertFalse(tab.faviconIsTemplateGlobePlaceholder)
        XCTAssertEqual(tab.resolvedFaviconCacheKey, key)
    }

    func testDirectFaviconHitCachesImage() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://direct-hit.example.com/article")!
        let key = SumiFaviconResolver.cacheKey(for: pageURL)!
        let faviconURL = URL(string: "https://direct-hit.example.com/favicon.ico")!
        let pngData = makePNGData(size: 64)

        StubURLProtocol.setHandler { request in
            XCTAssertEqual(request.url, faviconURL)
            return StubURLProtocol.Response(
                statusCode: 200,
                data: pngData,
                url: faviconURL
            )
        }

        let firstImage = await resolver.image(for: pageURL)
        XCTAssertNotNil(firstImage)
        XCTAssertNotNil(TabFaviconStore.getCachedImage(for: key))
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.count, 1)

        StubURLProtocol.reset()
        let secondImage = await resolver.image(for: pageURL)

        XCTAssertNotNil(secondImage)
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.count, 0)
    }

    func testLowResolutionDirectFaviconFallsBackToHigherQualityHTMLIcon() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://upgrade-direct.example.com/article")!
        let faviconURL = URL(string: "https://upgrade-direct.example.com/favicon.ico")!
        let appleTouchURL = URL(string: "https://upgrade-direct.example.com/apple-touch-icon.png")!
        let resolvedIconURL = URL(string: "https://cdn.example.com/icons/icon-64.png")!
        let html = """
        <html>
          <head>
            <link rel="icon" href="https://cdn.example.com/icons/icon-64.png" sizes="64x64">
          </head>
        </html>
        """

        StubURLProtocol.setHandler { [self] request in
            switch request.url {
            case faviconURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    data: self.makePNGData(size: 16),
                    url: faviconURL
                )
            case appleTouchURL:
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: appleTouchURL)
            case pageURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html; charset=utf-8"],
                    data: Data(html.utf8),
                    url: pageURL
                )
            case resolvedIconURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    data: self.makePNGData(size: 64),
                    url: resolvedIconURL
                )
            default:
                XCTFail("Unexpected URL requested: \(String(describing: request.url))")
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: request.url ?? pageURL)
            }
        }

        let image = await resolver.image(for: pageURL)

        XCTAssertNotNil(image)
        XCTAssertGreaterThanOrEqual(image?.size.width ?? 0, 32)
        XCTAssertEqual(
            StubURLProtocol.recordedRequestURLs,
            [faviconURL, appleTouchURL, pageURL, resolvedIconURL]
        )
    }

    func testLowResolutionCachedFaviconTriggersUpgradeFetch() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://upgrade-cached.example.com/article")!
        let key = SumiFaviconResolver.cacheKey(for: pageURL)!
        let faviconURL = URL(string: "https://upgrade-cached.example.com/favicon.ico")!
        let appleTouchURL = URL(string: "https://upgrade-cached.example.com/apple-touch-icon.png")!
        let resolvedIconURL = URL(string: "https://cdn.example.com/icons/cached-icon-64.png")!
        let html = """
        <html>
          <head>
            <link rel="icon" href="https://cdn.example.com/icons/cached-icon-64.png" sizes="64x64">
          </head>
        </html>
        """

        TabFaviconStore.cacheImage(makeImage(size: 16), for: key)

        StubURLProtocol.setHandler { [self] request in
            switch request.url {
            case faviconURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    data: self.makePNGData(size: 16),
                    url: faviconURL
                )
            case appleTouchURL:
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: appleTouchURL)
            case pageURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html; charset=utf-8"],
                    data: Data(html.utf8),
                    url: pageURL
                )
            case resolvedIconURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    data: self.makePNGData(size: 64),
                    url: resolvedIconURL
                )
            default:
                XCTFail("Unexpected URL requested: \(String(describing: request.url))")
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: request.url ?? pageURL)
            }
        }

        let image = await resolver.image(for: pageURL)

        XCTAssertNotNil(image)
        XCTAssertGreaterThanOrEqual(image?.size.width ?? 0, 32)
        XCTAssertEqual(
            StubURLProtocol.recordedRequestURLs,
            [faviconURL, appleTouchURL, pageURL, resolvedIconURL]
        )
    }

    func testLowQualityFallbackDoesNotRetryUpgradeOnEveryRequest() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://accepted-low-quality.example.com/article")!
        let faviconURL = URL(string: "https://accepted-low-quality.example.com/favicon.ico")!
        let appleTouchURL = URL(string: "https://accepted-low-quality.example.com/apple-touch-icon.png")!

        StubURLProtocol.setHandler { [self] request in
            switch request.url {
            case faviconURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    data: self.makePNGData(size: 16),
                    url: faviconURL
                )
            case appleTouchURL, pageURL:
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: request.url!)
            default:
                XCTFail("Unexpected URL requested: \(String(describing: request.url))")
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: request.url ?? pageURL)
            }
        }

        let firstImage = await resolver.image(for: pageURL)

        XCTAssertNotNil(firstImage)
        XCTAssertEqual(
            StubURLProtocol.recordedRequestURLs,
            [faviconURL, appleTouchURL, pageURL]
        )

        StubURLProtocol.reset()
        let secondImage = await resolver.image(for: pageURL)

        XCTAssertNotNil(secondImage)
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.count, 0)
    }

    func testLargeFaviconIsThumbnailDecodedForNetworkAndDiskCache() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://thumbnail.example.com/article")!
        let key = SumiFaviconResolver.cacheKey(for: pageURL)!
        let faviconURL = URL(string: "https://thumbnail.example.com/favicon.ico")!
        let pngData = makePNGData(size: 512)

        StubURLProtocol.setHandler { request in
            XCTAssertEqual(request.url, faviconURL)
            return StubURLProtocol.Response(
                statusCode: 200,
                data: pngData,
                url: faviconURL
            )
        }

        let firstImage = await resolver.image(for: pageURL)
        XCTAssertNotNil(firstImage)
        XCTAssertLessThanOrEqual(firstImage?.size.width ?? .greatestFiniteMagnitude, CGFloat(FaviconImageDecoder.defaultMaxPixelSize))
        XCTAssertLessThanOrEqual(firstImage?.size.height ?? .greatestFiniteMagnitude, CGFloat(FaviconImageDecoder.defaultMaxPixelSize))

        TabFaviconStore.clearMemoryCache()
        let diskImage = TabFaviconStore.getCachedImage(for: key)

        XCTAssertNotNil(diskImage)
        XCTAssertLessThanOrEqual(diskImage?.size.width ?? .greatestFiniteMagnitude, CGFloat(FaviconImageDecoder.defaultMaxPixelSize))
        XCTAssertLessThanOrEqual(diskImage?.size.height ?? .greatestFiniteMagnitude, CGFloat(FaviconImageDecoder.defaultMaxPixelSize))
    }

    func testDiskCachePreservesOriginalDownloadedBytes() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://raw-bytes.example.com/article")!
        let key = SumiFaviconResolver.cacheKey(for: pageURL)!
        let faviconURL = URL(string: "https://raw-bytes.example.com/favicon.ico")!
        let jpegData = makeJPEGData(size: 96)

        StubURLProtocol.setHandler { request in
            XCTAssertEqual(request.url, faviconURL)
            return StubURLProtocol.Response(
                statusCode: 200,
                headers: ["Content-Type": "image/jpeg"],
                data: jpegData,
                url: faviconURL
            )
        }

        let image = await resolver.image(for: pageURL)

        XCTAssertNotNil(image)

        TabFaviconStore.clearMemoryCache()
        XCTAssertNotNil(TabFaviconStore.getCachedImage(for: key))
    }

    func testHTMLFallbackResolvesRelativeIconURL() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://html-fallback.example.com/articles/42")!
        let faviconURL = URL(string: "https://html-fallback.example.com/favicon.ico")!
        let appleTouchURL = URL(string: "https://html-fallback.example.com/apple-touch-icon.png")!
        let resolvedIconURL = URL(string: "https://cdn.example.com/icons/icon-64.png")!
        let html = """
        <html>
          <head>
            <base href="https://cdn.example.com/icons/">
            <link rel="icon" href="icon-64.png" sizes="64x64">
          </head>
          <body></body>
        </html>
        """

        StubURLProtocol.setHandler { [self] request in
            switch request.url {
            case faviconURL, appleTouchURL:
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: request.url!)
            case pageURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html; charset=utf-8"],
                    data: Data(html.utf8),
                    url: pageURL
                )
            case resolvedIconURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    data: self.makePNGData(),
                    url: resolvedIconURL
                )
            default:
                XCTFail("Unexpected URL requested: \(String(describing: request.url))")
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: request.url ?? pageURL)
            }
        }

        let image = await resolver.image(for: pageURL)

        XCTAssertNotNil(image)
        XCTAssertEqual(
            StubURLProtocol.recordedRequestURLs,
            [faviconURL, appleTouchURL, pageURL, resolvedIconURL]
        )
    }

    func testClearCacheRemovesStoredFavicons() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://clear-cache.example.com/article")!
        let faviconURL = URL(string: "https://clear-cache.example.com/favicon.ico")!

        StubURLProtocol.setHandler { [self] request in
            XCTAssertEqual(request.url, faviconURL)
            return StubURLProtocol.Response(
                statusCode: 200,
                data: self.makePNGData(),
                url: faviconURL
            )
        }

        let image = await resolver.image(for: pageURL)
        XCTAssertNotNil(image)
        XCTAssertNotNil(TabFaviconStore.getCachedImage(for: SumiFaviconResolver.cacheKey(for: pageURL)!))

        await resolver.resetTransientState()
        TabFaviconStore.clearCache()
        let stats = TabFaviconStore.getFaviconCacheStats()

        XCTAssertNil(TabFaviconStore.getCachedImage(for: SumiFaviconResolver.cacheKey(for: pageURL)!))
        XCTAssertEqual(stats.count, 0)
    }

    func testResolvedIconURLCacheSkipsHTMLLookupOnSubsequentMiss() async {
        let resolver = makeResolver()
        let pageURL = URL(string: "https://resolved-cache.example.com/articles/42")!
        let faviconURL = URL(string: "https://resolved-cache.example.com/favicon.ico")!
        let appleTouchURL = URL(string: "https://resolved-cache.example.com/apple-touch-icon.png")!
        let resolvedIconURL = URL(string: "https://cdn.example.com/resolved/icon-64.png")!
        let html = """
        <html>
          <head>
            <link rel="icon" href="https://cdn.example.com/resolved/icon-64.png" sizes="64x64">
          </head>
          <body>ignored</body>
        </html>
        """

        StubURLProtocol.setHandler { [self] request in
            switch request.url {
            case faviconURL, appleTouchURL:
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: request.url!)
            case pageURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html; charset=utf-8"],
                    data: Data(html.utf8),
                    url: pageURL
                )
            case resolvedIconURL:
                return StubURLProtocol.Response(
                    statusCode: 200,
                    data: self.makePNGData(),
                    url: resolvedIconURL
                )
            default:
                XCTFail("Unexpected URL requested: \(String(describing: request.url))")
                return StubURLProtocol.Response(statusCode: 404, data: Data(), url: request.url ?? pageURL)
            }
        }

        let firstImage = await resolver.image(for: pageURL)
        XCTAssertNotNil(firstImage)
        XCTAssertEqual(
            StubURLProtocol.recordedRequestURLs,
            [faviconURL, appleTouchURL, pageURL, resolvedIconURL]
        )

        TabFaviconStore.clearCache()
        StubURLProtocol.reset()
        StubURLProtocol.setHandler { [self] request in
            XCTAssertEqual(request.url, resolvedIconURL)
            return StubURLProtocol.Response(
                statusCode: 200,
                data: self.makePNGData(),
                url: resolvedIconURL
            )
        }

        let secondImage = await resolver.image(for: pageURL)

        XCTAssertNotNil(secondImage)
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs, [resolvedIconURL])
    }

    func testNetworkConcurrencyLimitCapsParallelFetches() async {
        let resolver = makeResolver(maxConcurrentNetworkRequests: 2)
        let pageURLs = (0..<5).map { URL(string: "https://limit-\($0).example.com/page")! }
        let pngData = makePNGData()
        let lock = NSLock()
        var activeRequests = 0
        var maxActiveRequests = 0

        StubURLProtocol.setHandler { request in
            lock.lock()
            activeRequests += 1
            maxActiveRequests = max(maxActiveRequests, activeRequests)
            lock.unlock()

            Thread.sleep(forTimeInterval: 0.05)

            lock.lock()
            activeRequests -= 1
            lock.unlock()

            return StubURLProtocol.Response(
                statusCode: 200,
                data: pngData,
                url: request.url!
            )
        }

        await withTaskGroup(of: NSImage?.self) { group in
            for pageURL in pageURLs {
                group.addTask {
                    await resolver.image(for: pageURL)
                }
            }

            for await image in group {
                XCTAssertNotNil(image)
            }
        }

        XCTAssertLessThanOrEqual(maxActiveRequests, 2)
        XCTAssertEqual(StubURLProtocol.recordedRequestURLs.count, pageURLs.count)
    }

    private func makeResolver(
        negativeCacheTTL: TimeInterval = 600,
        maxConcurrentNetworkRequests: Int = 6,
        maxDocumentBytes: Int = 65_536
    ) -> SumiFaviconResolver {
        SumiFaviconResolver(
            session: makeSession(),
            negativeCacheTTL: negativeCacheTTL,
            maxConcurrentNetworkRequests: maxConcurrentNetworkRequests,
            maxDocumentBytes: maxDocumentBytes
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeImage(size: CGFloat = 64) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        image.unlockFocus()
        return image
    }

    private func makePNGData(size: CGFloat = 64) -> Data {
        guard let tiffData = makeImage(size: size).tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Failed to build test PNG data")
            return Data()
        }
        return pngData
    }

    private func makeJPEGData(size: CGFloat = 16) -> Data {
        guard let tiffData = makeImage(size: size).tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.85]
              )
        else {
            XCTFail("Failed to build test JPEG data")
            return Data()
        }
        return jpegData
    }
}

private final class StubURLProtocol: URLProtocol {
    struct Response {
        var statusCode: Int
        var headers: [String: String] = [:]
        var data: Data
        var url: URL
    }

    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> Response)?
    private static var requests: [URL] = []

    static var recordedRequestURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func setHandler(_ handler: @escaping (URLRequest) throws -> Response) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        requests.removeAll()
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request.url ?? URL(fileURLWithPath: "/"))
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let response = try handler(request)
            let httpResponse = HTTPURLResponse(
                url: response.url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
