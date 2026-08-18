import AppKit
import Foundation
import ImageIO
import SumiDomain
import UniformTypeIdentifiers
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabFaviconRuntimeOwnershipTests: XCTestCase {
    func testRegularTabCacheMissUsesTemplateGlobePlaceholder() {
        let tab = Tab(
            url: URL(string: "https://runtime-owner.example/page")!,
            name: "Example",
            loadsCachedFaviconOnInit: false
        )

        XCTAssertTrue(tab.faviconIsTemplateGlobePlaceholder)
        XCTAssertTrue(tab.usesChromeThemedTemplateFavicon)
    }

    func testInternalSurfaceClearsGlobePlaceholder() {
        let historyURL = SumiSurface.historySurfaceURL(rangeQuery: "all")
        let tab = Tab(
            url: URL(string: "https://runtime-owner.example/page")!,
            name: "Example",
            loadsCachedFaviconOnInit: false
        )

        XCTAssertTrue(tab.faviconIsTemplateGlobePlaceholder)
        tab.url = historyURL
        XCTAssertTrue(tab.applyCachedFaviconOrPlaceholder(for: historyURL))

        XCTAssertFalse(tab.faviconIsTemplateGlobePlaceholder)
        XCTAssertTrue(tab.usesChromeThemedTemplateFavicon)
    }
}

final class SumiFaviconV2DiscoveryTests: XCTestCase {
    func testRelParsingTreatsShortcutIconAsCaseInsensitiveTokens() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/path/page"))
        let candidates = SumiFaviconDiscovery.documentCandidates(
            from: [
                SumiFaviconDiscoveredLink(
                    href: "/favicon.ico",
                    rel: "Shortcut Icon",
                    type: "image/x-icon",
                    sizes: "16x16 32x32"
                ),
            ],
            pageURL: pageURL,
            baseURL: pageURL,
            partition: .regular()
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].relTokens, ["shortcut", "icon"])
        XCTAssertEqual(candidates[0].iconURL.absoluteString, "https://example.com/favicon.ico")
        XCTAssertEqual(candidates[0].declaredSizes.map(\.longestSide), [16, 32])
    }

    func testFirstManifestLinkInTreeOrderIsCanonical() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let first = SumiFaviconDiscovery.firstManifestURL(
            from: [
                SumiFaviconDiscoveredLink(href: "/one.webmanifest", rel: "manifest"),
                SumiFaviconDiscoveredLink(href: "/two.webmanifest", rel: "MANIFEST"),
            ],
            pageURL: pageURL,
            baseURL: pageURL
        )

        XCTAssertEqual(first?.absoluteString, "https://example.com/one.webmanifest")
    }

    func testManifestCandidatesPreserveSizesTypeAndPurpose() throws {
        let manifestURL = try XCTUnwrap(URL(string: "https://example.com/app.webmanifest"))
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let data = """
        {
          "icons": [
            { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
            { "src": "/maskable.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
          ]
        }
        """.data(using: .utf8)!

        let candidates = SumiWebAppManifestIconDiscovery.candidates(
            from: data,
            manifestURL: manifestURL,
            pageURL: pageURL,
            partition: .regular()
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].iconURL.absoluteString, "https://example.com/icon-192.png")
        XCTAssertEqual(candidates[0].declaredType, "image/png")
        XCTAssertEqual(candidates[0].declaredSizes, [SumiFaviconDeclaredSize(width: 192, height: 192)])
        XCTAssertEqual(candidates[0].purposes, [.any])
        XCTAssertEqual(candidates[1].purposes, [.maskable])
    }

    func testManifestCandidatesReturnEmptyForInvalidManifestJSON() throws {
        let manifestURL = try XCTUnwrap(URL(string: "https://example.com/app.webmanifest"))
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let data = Data(#"{ "icons": ["#.utf8)

        let candidates = SumiWebAppManifestIconDiscovery.candidates(
            from: data,
            manifestURL: manifestURL,
            pageURL: pageURL,
            partition: .regular()
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testAppleTouchAndRelativeDocumentLinksResolveAgainstBaseURL() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/app/page"))
        let baseURL = try XCTUnwrap(URL(string: "https://cdn.example.com/assets/index.html"))
        let candidates = SumiFaviconDiscovery.documentCandidates(
            from: [
                SumiFaviconDiscoveredLink(
                    href: "../touch.png",
                    rel: "APPLE-TOUCH-ICON-PRECOMPOSED",
                    type: "image/png",
                    sizes: "180x180"
                ),
            ],
            pageURL: pageURL,
            baseURL: baseURL,
            partition: .regular()
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].iconURL.absoluteString, "https://cdn.example.com/touch.png")
        XCTAssertEqual(candidates[0].declaredSizes, [SumiFaviconDeclaredSize(width: 180, height: 180)])
        XCTAssertEqual(candidates[0].sourcePriority, 1)
    }

    func testRootFallbackIsBoundedAndOrderedAfterDocumentDiscovery() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://browserbench.org/Speedometer3.1/"))
        let documentCandidates = SumiFaviconDiscovery.documentCandidates(
            from: [
                SumiFaviconDiscoveredLink(href: "resources/favicon.png", rel: "icon", type: "image/png"),
            ],
            pageURL: pageURL,
            baseURL: pageURL,
            partition: .regular()
        )
        let rootCandidates = SumiFaviconDiscovery.rootFallbackCandidates(
            for: pageURL,
            partition: .regular()
        )

        XCTAssertEqual(documentCandidates.first?.iconURL.absoluteString, "https://browserbench.org/Speedometer3.1/resources/favicon.png")
        XCTAssertEqual(rootCandidates.map(\.iconURL.path), [
            "/favicon.ico",
            "/favicon.png",
            "/apple-touch-icon.png",
            "/apple-touch-icon-precomposed.png",
            "/apple-touch-icon-180x180.png",
            "/apple-touch-icon-152x152.png",
        ])
        XCTAssertLessThan(documentCandidates[0].sourcePriority, rootCandidates[0].sourcePriority)
    }

    func testDataAndBlobCandidatesOnlyComeFromLiveDocumentDiscovery() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let candidates = SumiFaviconDiscovery.documentCandidates(
            from: [
                SumiFaviconDiscoveredLink(href: "data:image/svg+xml,%3Csvg%2F%3E", rel: "icon"),
                SumiFaviconDiscoveredLink(href: "blob:https://example.com/icon", rel: "icon"),
            ],
            pageURL: pageURL,
            baseURL: pageURL,
            partition: .regular()
        )

        XCTAssertEqual(Set(candidates.compactMap(\.iconURL.scheme)), ["data", "blob"])
        XCTAssertTrue(
            SumiFaviconDiscovery.rootFallbackCandidates(for: pageURL, partition: .regular())
                .allSatisfy { $0.iconURL.scheme == "https" }
        )
    }
}

final class SumiFaviconV2SelectorTests: XCTestCase {
    func testSelectorPrefersSharpManifestCandidateOverTinyDocumentIcon() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let tinyURL = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
        let manifestURL = try XCTUnwrap(URL(string: "https://example.com/icon-192.png"))
        let partition = SumiFaviconPartition.regular()
        let tiny = SumiFaviconCandidate(
            pageURL: pageURL,
            iconURL: tinyURL,
            sourceKind: .documentLink,
            relTokens: ["icon"],
            declaredSizes: [SumiFaviconDeclaredSize(width: 16, height: 16)],
            declaredType: "image/x-icon",
            partition: partition
        )
        let manifest = SumiFaviconCandidate(
            pageURL: pageURL,
            iconURL: manifestURL,
            sourceKind: .webAppManifest,
            relTokens: ["manifest"],
            declaredSizes: [SumiFaviconDeclaredSize(width: 192, height: 192)],
            declaredType: "image/png",
            partition: partition
        )

        XCTAssertEqual(
            SumiFaviconCandidateSelector.bestCandidate(
                [tiny, manifest],
                for: .tabSidebar,
                backingScale: 2
            )?.iconURL,
            manifestURL
        )
    }

    func testSelectorDoesNotPreferMaskableOverAnyForNormalUI() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let partition = SumiFaviconPartition.regular()
        let anyURL = try XCTUnwrap(URL(string: "https://example.com/any.png"))
        let maskableURL = try XCTUnwrap(URL(string: "https://example.com/maskable.png"))
        let any = SumiFaviconCandidate(
            pageURL: pageURL,
            iconURL: anyURL,
            sourceKind: .webAppManifest,
            declaredSizes: [SumiFaviconDeclaredSize(width: 192, height: 192)],
            declaredType: "image/png",
            purposes: [.any],
            partition: partition
        )
        let maskable = SumiFaviconCandidate(
            pageURL: pageURL,
            iconURL: maskableURL,
            sourceKind: .webAppManifest,
            declaredSizes: [SumiFaviconDeclaredSize(width: 192, height: 192)],
            declaredType: "image/png",
            purposes: [.maskable],
            partition: partition
        )

        XCTAssertEqual(
            SumiFaviconCandidateSelector.bestCandidate(
                [maskable, any],
                for: .tabSidebar,
                backingScale: 2
            )?.iconURL,
            anyURL
        )
    }

    func testYouTubeDocumentCandidatesPreferRetinaSizedPNGOverTinyShortcutIcon() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=J8O9LLpJNrg"))
        let candidates = SumiFaviconDiscovery.documentCandidates(
            from: [
                SumiFaviconDiscoveredLink(
                    href: "https://www.youtube.com/s/desktop/test/img/favicon.ico",
                    rel: "shortcut icon",
                    type: "image/x-icon"
                ),
                SumiFaviconDiscoveredLink(
                    href: "https://www.youtube.com/s/desktop/test/img/favicon_32x32.png",
                    rel: "icon",
                    type: "image/png",
                    sizes: "32x32"
                ),
                SumiFaviconDiscoveredLink(
                    href: "https://www.youtube.com/s/desktop/test/img/favicon_48x48.png",
                    rel: "icon",
                    type: "image/png",
                    sizes: "48x48"
                ),
                SumiFaviconDiscoveredLink(
                    href: "https://www.youtube.com/s/desktop/test/img/favicon_96x96.png",
                    rel: "icon",
                    type: "image/png",
                    sizes: "96x96"
                ),
            ],
            pageURL: pageURL,
            baseURL: pageURL,
            partition: .regular()
        )

        XCTAssertEqual(
            SumiFaviconCandidateSelector.bestCandidate(
                candidates,
                for: .tabSidebar,
                backingScale: 2
            )?.iconURL.absoluteString,
            "https://www.youtube.com/s/desktop/test/img/favicon_48x48.png"
        )
        XCTAssertEqual(
            SumiFaviconCandidateSelector.bestCandidate(
                candidates,
                for: .pinnedLauncher,
                backingScale: 2
            )?.iconURL.absoluteString,
            "https://www.youtube.com/s/desktop/test/img/favicon_48x48.png"
        )
    }
}

final class SumiFaviconV2PayloadTests: XCTestCase {
    func testValidatorRejectsHTMLPayloadPretendingToBeIcon() throws {
        let candidate = try candidate(url: "https://example.com/favicon.ico", type: "image/x-icon")
        let result = SumiFaviconPayloadValidator.validate(
            data: Data("<!doctype html><html></html>".utf8),
            responseMimeType: "image/x-icon",
            candidate: candidate
        )

        guard case .invalid(let failure) = result else {
            return XCTFail("Expected invalid payload")
        }
        XCTAssertEqual(failure, .htmlPayload)
    }

    func testValidatorAcceptsSafeSVGAndRejectsExternalSVGResources() throws {
        let candidate = try candidate(url: "https://example.com/icon.svg", type: "image/svg+xml")
        let safe = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect width="16" height="16"/></svg>"#.utf8)
        let unsafe = Data(#"<svg xmlns="http://www.w3.org/2000/svg"><image href="https://tracker.example/icon.png"/></svg>"#.utf8)

        guard case .valid(let payload) = SumiFaviconPayloadValidator.validate(data: safe, responseMimeType: nil, candidate: candidate) else {
            return XCTFail("Expected safe SVG to validate")
        }
        XCTAssertEqual(payload.payloadKind, .svg)

        guard case .invalid(let failure) = SumiFaviconPayloadValidator.validate(data: unsafe, responseMimeType: nil, candidate: candidate) else {
            return XCTFail("Expected unsafe SVG to fail")
        }
        XCTAssertEqual(failure, .unsafeSVG)
    }

    func testValidatorAcceptsStyledSVGWithInternalStyleOnly() throws {
        let candidate = try candidate(url: "https://shield.turtlecute.org/assets/styled/icon.svg", type: "image/svg+xml")
        let result = SumiFaviconPayloadValidator.validate(
            data: SumiFaviconTestImages.styledSVGData(),
            responseMimeType: "image/svg+xml",
            candidate: candidate
        )

        guard case .valid(let payload) = result else {
            return XCTFail("Expected styled SVG favicon to validate")
        }
        XCTAssertEqual(payload.payloadKind, .svg)
    }

    func testValidatorAcceptsSmallPNG() throws {
        let candidate = try candidate(url: "https://example.com/icon.png", type: "image/png")
        let result = SumiFaviconPayloadValidator.validate(
            data: try Self.pngData(width: 32, height: 32),
            responseMimeType: "image/png",
            candidate: candidate
        )

        guard case .valid(let payload) = result else {
            return XCTFail("Expected valid PNG")
        }
        XCTAssertEqual(payload.payloadKind, .png)
        XCTAssertEqual(payload.pixelWidth, 32)
        XCTAssertEqual(payload.pixelHeight, 32)
    }

    func testValidatorSelectsBestFrameFromMultiFrameICO() throws {
        let candidate = try candidate(url: "https://example.com/favicon.ico", type: "image/x-icon")
        let result = SumiFaviconPayloadValidator.validate(
            data: try Self.icoData(frameSizes: [16, 64]),
            responseMimeType: "image/x-icon",
            candidate: candidate
        )

        guard case .valid(let payload) = result else {
            return XCTFail("Expected valid ICO")
        }
        XCTAssertEqual(payload.payloadKind, .ico)
        XCTAssertEqual(payload.pixelWidth, 64)
        XCTAssertEqual(payload.pixelHeight, 64)
    }

    func candidate(url: String, type: String) throws -> SumiFaviconCandidate {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let iconURL = try XCTUnwrap(URL(string: url))
        return SumiFaviconCandidate(
            pageURL: pageURL,
            iconURL: iconURL,
            sourceKind: .documentLink,
            declaredType: type,
            partition: .regular()
        )
    }

    static func pngData(width: Int, height: Int) throws -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 220
            pixels[index + 1] = 32
            pixels[index + 2] = 32
            pixels[index + 3] = 255
        }
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func icoData(frameSizes: [Int]) throws -> Data {
        let frames = try frameSizes.map { size in
            (size: size, data: try pngData(width: size, height: size))
        }
        var result = Data([0x00, 0x00, 0x01, 0x00])
        appendUInt16(UInt16(frames.count), to: &result)

        var imageOffset = 6 + frames.count * 16
        for frame in frames {
            result.append(contentsOf: [UInt8(frame.size == 256 ? 0 : frame.size), UInt8(frame.size == 256 ? 0 : frame.size), 0x00, 0x00])
            appendUInt16(1, to: &result)
            appendUInt16(32, to: &result)
            appendUInt32(UInt32(frame.data.count), to: &result)
            appendUInt32(UInt32(imageOffset), to: &result)
            imageOffset += frame.data.count
        }

        for frame in frames {
            result.append(frame.data)
        }
        return result
    }

    static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0x00ff),
            UInt8((value & 0xff00) >> 8),
        ])
    }

    static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0x000000ff),
            UInt8((value & 0x0000ff00) >> 8),
            UInt8((value & 0x00ff0000) >> 16),
            UInt8((value & 0xff000000) >> 24),
        ])
    }
}


final class FaviconURLNormalizationRegressionTests: XCTestCase {
    func testLiveDiscoveryAcceptsEquivalentDocumentURLNormalizations() throws {
        let documentURL = try XCTUnwrap(URL(string: "https://browserbench.org:443/Speedometer3.1/#run"))
        let currentURL = try XCTUnwrap(URL(string: "https://BROWSERBENCH.org/Speedometer3.1/"))

        XCTAssertTrue(FaviconsTabExtension.documentURL(documentURL, matches: currentURL))
    }

    func testCanonicalPageKeyIgnoresQueryAndFragmentIdentity() throws {
        let first = try XCTUnwrap(URL(string: "HTTPS://Example.COM:443/path?one=1#top"))
        let second = try XCTUnwrap(URL(string: "https://example.com/path?two=2#bottom"))

        XCTAssertEqual(SumiFaviconCanonicalURL.pageURL(first).absoluteString, "https://example.com/path")
        XCTAssertEqual(SumiFaviconCanonicalURL.pageKey(for: first), SumiFaviconCanonicalURL.pageKey(for: second))
    }
}

func removeFaviconTestDirectories(
    _ directories: [URL],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for directory in directories {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            continue
        } catch {
            XCTFail(
                "Failed to remove favicon test directory \(directory.path): \(error)",
                file: file,
                line: line
            )
        }
    }
}

enum SumiFaviconTestImages {
    static func styledSVGData() -> Data {
        Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" fill="#0074D8" version="1.1">
                <style>@media (prefers-color-scheme: dark) { :root { fill: #ffffff; } }</style>
                <path d="M63.98 27.685c-11.2 0-19.45 1.43-28.666 4.974-4.726 1.82-4.948 2.305-4.368 9.538.783 9.734 3.79 21.804 5.788 23.204h.006c1.294.906 1.359.895 5.762-1.055l3.887-1.719.247-4.466c.164-2.95.534-5.16 1.088-6.504 5.8-13.987 24.36-15.6 32.377-2.819a165.87 165.87 0 0 0 1.536 2.415c.067.094 2.902-.286 6.302-.846 8.414-1.387 8.515-1.474 9.115-8.288.61-6.893.258-7.667-4.35-9.434-9.273-3.57-17.497-5-28.724-5z"/>
                <path d="M64.005 14c-4.992 0-9.984.257-13.262.768-9.64 1.5-18.933 4.257-27.123 8.04-5.084 2.35-5.615 3.542-5.632 12.586-.033 20.197 6.158 38.675 18.568 55.385 5.694 7.667 17.217 18.304 24.057 22.214 3.57 2.043 5.931 1.22 13.555-4.733 16.362-12.774 28.101-30.598 33.021-50.138 1.837-7.303 2.46-11.792 2.715-19.636.294-9.007.046-11.2-1.47-13.008-2.835-3.36-18.461-8.73-31.174-10.71-3.276-.51-8.264-.768-13.255-.768z"/>
            </svg>
            """.utf8
        )
    }

    static func tallSVGData() -> Data {
        Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="108" height="162" viewBox="0 0 108 162">
                <rect width="108" height="162" fill="#e02020"/>
            </svg>
            """.utf8
        )
    }

    static func pngData(width: Int, height: Int) throws -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 220
            pixels[index + 1] = 32
            pixels[index + 2] = 32
            pixels[index + 3] = 255
        }
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

actor RoutingFaviconNetworkFetcher: SumiFaviconNetworkFetching {
    let responses: [String: SumiFaviconFetchResult]
    let onRequest: @Sendable (URL) -> Void
    private(set) var requestedURLs: [URL] = []

    init(
        responses: [String: SumiFaviconFetchResult],
        onRequest: @escaping @Sendable (URL) -> Void = { _ in }
    ) {
        self.responses = responses
        self.onRequest = onRequest
    }

    func fetch(url: URL, context _: SumiFaviconFetchContext) async -> SumiFaviconFetchResult {
        requestedURLs.append(url)
        onRequest(url)
        return responses[url.absoluteString] ?? .failure(.notFound)
    }
}
