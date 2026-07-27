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
        let settingsURL = SumiSurface.settingsSurfaceURL(paneQuery: "general")
        let tab = Tab(
            url: URL(string: "https://runtime-owner.example/page")!,
            name: "Example",
            loadsCachedFaviconOnInit: false
        )

        XCTAssertTrue(tab.faviconIsTemplateGlobePlaceholder)
        tab.url = settingsURL
        XCTAssertTrue(tab.applyCachedFaviconOrPlaceholder(for: settingsURL))

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
            partition: .regular(nil)
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
            partition: .regular(nil)
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
            partition: .regular(nil)
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
            partition: .regular(nil)
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
            partition: .regular(nil)
        )
        let rootCandidates = SumiFaviconDiscovery.rootFallbackCandidates(
            for: pageURL,
            partition: .regular(nil)
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
            partition: .regular(nil)
        )

        XCTAssertEqual(Set(candidates.compactMap(\.iconURL.scheme)), ["data", "blob"])
        XCTAssertTrue(
            SumiFaviconDiscovery.rootFallbackCandidates(for: pageURL, partition: .regular(nil))
                .allSatisfy { $0.iconURL.scheme == "https" }
        )
    }
}

final class SumiFaviconV2SelectorTests: XCTestCase {
    func testSelectorPrefersSharpManifestCandidateOverTinyDocumentIcon() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let tinyURL = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
        let manifestURL = try XCTUnwrap(URL(string: "https://example.com/icon-192.png"))
        let partition = SumiFaviconPartition.regular(nil)
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
        let partition = SumiFaviconPartition.regular(nil)
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
            partition: .regular(nil)
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

    private func candidate(url: String, type: String) throws -> SumiFaviconCandidate {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let iconURL = try XCTUnwrap(URL(string: url))
        return SumiFaviconCandidate(
            pageURL: pageURL,
            iconURL: iconURL,
            sourceKind: .documentLink,
            declaredType: type,
            partition: .regular(nil)
        )
    }

    private static func pngData(width: Int, height: Int) throws -> Data {
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

    private static func icoData(frameSizes: [Int]) throws -> Data {
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

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0x00ff),
            UInt8((value & 0xff00) >> 8),
        ])
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0x000000ff),
            UInt8((value & 0x0000ff00) >> 8),
            UInt8((value & 0x00ff0000) >> 16),
            UInt8((value & 0xff000000) >> 24),
        ])
    }
}

@MainActor
final class SumiFaviconV2PipelineRegressionTests: XCTestCase {
    func testLocalExtensionIconIsPreparedThroughFaviconPipeline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2ExtensionIcon-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let iconURL = directory.appendingPathComponent("extension-icon-128.png")
        try SumiFaviconTestImages.pngData(width: 128, height: 128).write(to: iconURL, options: [.atomic])

        let pageURL = try XCTUnwrap(URL(string: "webkit-extension://ext-test/onboarding.html"))
        XCTAssertNotNil(SumiFaviconLookupKey.cacheKey(for: pageURL))

        let runtime = SumiFaviconRuntime(
            rootDirectory: directory.appendingPathComponent("store", isDirectory: true),
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        let partition = SumiFaviconPartition.regular(UUID())
        let image = await runtime.payloadIngestion.ingestLocalExtensionIcon(
            fileURL: iconURL,
            documentURL: pageURL,
            partition: partition,
            context: .tabSidebar
        )
        let request = request(pageURL: pageURL, partition: partition, context: .tabSidebar)
        try assertPreparedImage(image, matches: request)

        let selection = try XCTUnwrap(runtime.images.cachedSelection(for: pageURL, partition: partition))
        XCTAssertEqual(selection.sourceKind, .extensionManifest)
        XCTAssertEqual(selection.sourceURL.standardizedFileURL.path, iconURL.standardizedFileURL.path)

        try assertPreparedImage(
            runtime.images.cachedPreparedImage(for: request),
            matches: request
        )
    }

    func testReferenceKeyHelpersShareTheSameNormalization() throws {
        let url = try XCTUnwrap(URL(string: "https://EXAMPLE.com/Path?q=1"))
        let referenceKey = try XCTUnwrap(SumiFaviconLookupKey.referenceKey(for: url))

        XCTAssertEqual(referenceKey, "example.com")
        XCTAssertEqual(TabFaviconStore.referenceKey(forDocumentURL: url), referenceKey)
        XCTAssertEqual(
            SumiFaviconLookupKey.documentURL(forReferenceKey: referenceKey)?.absoluteString,
            "https://example.com"
        )
        XCTAssertEqual(
            TabFaviconStore.documentURL(forReferenceKey: referenceKey)?.absoluteString,
            "https://example.com"
        )
    }

    func testReferenceKeyAndDocumentURLLookupHitTheSamePreparedImage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2ReferenceKey-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pageURL = try XCTUnwrap(URL(string: "https://example.com/path"))
        let partition = SumiFaviconPartition.regular(nil)
        let imageData = try SumiFaviconTestImages.pngData(width: 64, height: 64)

        // Use an isolated runtime rooted in a temp directory instead of the
        // shared system so this test does not persist blobs across runs.
        let runtime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        try runtime.payloadIngestion.storeExternalPayload(
            imageData,
            faviconURL: pageURL.appendingPathComponent("favicon.png"),
            documentURL: pageURL,
            partition: partition
        )

        let loadedImage = await TabFaviconStore.loadCachedDisplayImage(
            forDocumentURL: pageURL,
            partition: partition,
            context: .tabSidebar,
            priority: .visibleSidebarOrTabStrip,
            imageReader: runtime.images
        )
        XCTAssertNotNil(loadedImage)

        let referenceKey = try XCTUnwrap(TabFaviconStore.referenceKey(forDocumentURL: pageURL))
        let imageByReference = TabFaviconStore.getCachedImage(
            forReferenceKey: referenceKey,
            partition: partition,
            context: .tabSidebar,
            imageReader: runtime.images
        )
        let imageByDocumentURL = TabFaviconStore.getCachedImage(
            forDocumentURL: pageURL,
            partition: partition,
            imageReader: runtime.images
        )

        XCTAssertNotNil(imageByReference)
        XCTAssertNotNil(imageByDocumentURL)
        XCTAssertEqual(imageByReference?.size, imageByDocumentURL?.size)
    }

    func testCorruptDatabaseMetadataIsPreservedWhenLocalServiceLoadsPartition() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2CorruptMetadata-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let partition = SumiFaviconPartition.regular(nil)
        let database = try SumiDatabase.inMemory()
        let metadataKey = "favicon.metadata.\(partition.storageComponent)"
        let corruptPayload = Data("{ not valid favicon metadata".utf8)
        try database.transaction {
            try $0.documents.save(corruptPayload, forKey: metadataKey)
        }

        let runtime = SumiFaviconRuntime(
            database: database,
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        XCTAssertNil(
            runtime.images.cachedSelection(
                for: try XCTUnwrap(URL(string: "https://example.com/")),
                partition: partition
            )
        )

        XCTAssertEqual(
            try database.read {
                try $0.documents.data(forKey: metadataKey)
            },
            corruptPayload
        )
    }

    func testSpeedometerRelativeDocumentIconPersistsForColdCacheBackedLookup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2Speedometer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pageURL = try XCTUnwrap(URL(string: "https://browserbench.org/Speedometer3.1/"))
        let iconURL = try XCTUnwrap(URL(string: "https://browserbench.org/Speedometer3.1/resources/favicon.png"))
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                iconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 64, height: 64),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: fetcher)
        let partition = SumiFaviconPartition.regular(nil)

        let visibleImage = await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: "resources/favicon.png",
                    rel: "icon",
                    type: "image/png"
                ),
            ],
            documentURL: pageURL,
            baseURL: pageURL,
            partition: partition,
            webView: nil
        )

        XCTAssertNotNil(visibleImage)
        let requestedURLs = await fetcher.requestedURLs.map(\.absoluteString)
        XCTAssertEqual(requestedURLs, [iconURL.absoluteString])
        let selection = try XCTUnwrap(runtime.images.cachedSelection(for: pageURL, partition: partition))
        XCTAssertEqual(selection.sourceURL.absoluteString, iconURL.absoluteString)
        let cachedSidebarImage = TabFaviconStore.getCachedImage(
            forDocumentURL: pageURL,
            partition: partition,
            context: .tabSidebar,
            imageReader: runtime.images
        )
        XCTAssertNotNil(cachedSidebarImage)

        let restartedRuntime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        let coldImage = await restartedRuntime.images.preparedImage(
            for: SumiPreparedFaviconRequest(
                pageURL: pageURL,
                partition: partition,
                context: .pinnedLauncher,
                backingScale: 2
            ),
            priority: .pinnedLauncher,
            scheduleFetchOnMiss: false
        )
        XCTAssertNotNil(coldImage)
    }

    func testExplicitDocumentIconOverridesFreshRootNoIconNegative() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2RootNegativeOverride-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pageURL = try XCTUnwrap(URL(string: "https://browserbench.org/Speedometer3.1/"))
        let iconURL = try XCTUnwrap(URL(string: "https://browserbench.org/Speedometer3.1/resources/favicon.png"))
        let finalRootRequest = expectation(description: "final root fallback requested")
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                iconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 64, height: 64),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ],
            onRequest: { url in
                if url.absoluteString == "https://browserbench.org/apple-touch-icon-152x152.png" {
                    finalRootRequest.fulfill()
                }
            }
        )
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: fetcher)
        let partition = SumiFaviconPartition.regular(nil)

        let coldMiss = await runtime.images.preparedImage(
            for: SumiPreparedFaviconRequest(
                pageURL: pageURL,
                partition: partition,
                context: .tabSidebar,
                backingScale: 2
            ),
            priority: .historyBookmarkVisibleRow,
            scheduleFetchOnMiss: true
        )
        XCTAssertNil(coldMiss)

        await fulfillment(of: [finalRootRequest], timeout: 1)
        var requestedURLs = await fetcher.requestedURLs.map(\.absoluteString)
        XCTAssertTrue(requestedURLs.contains("https://browserbench.org/favicon.ico"))
        XCTAssertTrue(requestedURLs.contains("https://browserbench.org/apple-touch-icon-152x152.png"))

        let visibleImage = await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: "resources/favicon.png",
                    rel: "icon",
                    type: "image/png"
                ),
            ],
            documentURL: pageURL,
            baseURL: pageURL,
            partition: partition,
            webView: nil
        )

        XCTAssertNotNil(visibleImage)
        requestedURLs = await fetcher.requestedURLs.map(\.absoluteString)
        XCTAssertTrue(requestedURLs.contains(iconURL.absoluteString))
    }

    func testExplicitHighQualityDocumentIconUpgradesCachedTinyRootFallback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2RootUpgrade-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pageURL = try XCTUnwrap(URL(string: "https://www.example.com/watch"))
        let rootIconURL = try XCTUnwrap(URL(string: "https://www.example.com/favicon.ico"))
        let documentIconURL = try XCTUnwrap(URL(string: "https://www.example.com/assets/favicon-96.png"))
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                rootIconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 16, height: 16),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
                documentIconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 96, height: 96),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let notificationCenter = NotificationCenter()
        let cacheUpdated = expectation(
            forNotification: .faviconCacheUpdated,
            object: nil,
            notificationCenter: notificationCenter
        )
        let runtime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: fetcher,
            notificationCenter: notificationCenter
        )
        let partition = SumiFaviconPartition.regular(nil)

        let coldMiss = await runtime.images.preparedImage(
            for: SumiPreparedFaviconRequest(
                pageURL: pageURL,
                partition: partition,
                context: .tabSidebar,
                backingScale: 2
            ),
            priority: .historyBookmarkVisibleRow,
            scheduleFetchOnMiss: true
        )
        XCTAssertNil(coldMiss)

        await fulfillment(of: [cacheUpdated], timeout: 1)

        var requestedURLs = await fetcher.requestedURLs.map(\.absoluteString)
        XCTAssertTrue(
            runtime.images.hasFavicon(for: pageURL, partition: partition),
            "Expected cold root fallback to be cached before live discovery. Requests: \(requestedURLs)"
        )
        XCTAssertTrue(
            requestedURLs.contains(rootIconURL.absoluteString),
            "Expected root fallback request. Requests: \(requestedURLs)"
        )
        XCTAssertFalse(requestedURLs.contains(documentIconURL.absoluteString))

        let visibleImage = await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: "/assets/favicon-96.png",
                    rel: "icon",
                    type: "image/png",
                    sizes: "96x96"
                ),
            ],
            documentURL: pageURL,
            baseURL: pageURL,
            partition: partition,
            webView: nil
        )

        XCTAssertNotNil(visibleImage)
        requestedURLs = await fetcher.requestedURLs.map(\.absoluteString)
        XCTAssertTrue(
            requestedURLs.contains(documentIconURL.absoluteString),
            "Expected explicit document icon to upgrade cached root fallback. Requests: \(requestedURLs)"
        )

        XCTAssertEqual(
            runtime.images.cachedSelection(
                for: pageURL,
                partition: partition
            )?.sourceURL,
            documentIconURL,
            "Expected the durable page mapping to point at the upgraded document icon."
        )
    }

    func testPinnedLauncherColdLookupFetchesAndPreparesWithoutWebView() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2PinnedColdFetch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pageURL = try XCTUnwrap(URL(string: "https://pinned.example/app"))
        let rootIconURL = try XCTUnwrap(URL(string: "https://pinned.example/favicon.ico"))
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                rootIconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 64, height: 64),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let notificationCenter = NotificationCenter()
        let cacheUpdated = expectation(
            forNotification: .faviconCacheUpdated,
            object: nil,
            notificationCenter: notificationCenter
        )
        let runtime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: fetcher,
            notificationCenter: notificationCenter
        )
        let partition = SumiFaviconPartition.regular(UUID())
        let request = SumiPreparedFaviconRequest(
            pageURL: pageURL,
            partition: partition,
            context: .pinnedLauncher,
            backingScale: 2
        )

        let placeholderPathResult = await runtime.images.preparedImage(
            for: request,
            priority: .pinnedLauncher,
            scheduleFetchOnMiss: true
        )
        XCTAssertNil(placeholderPathResult)

        await fulfillment(of: [cacheUpdated], timeout: 1)

        let requestedURLs = await fetcher.requestedURLs.map(\.absoluteString)
        XCTAssertTrue(
            requestedURLs.contains(rootIconURL.absoluteString),
            "Expected inactive pinned cold lookup to schedule bounded root fallback without a WebView. Requests: \(requestedURLs)"
        )

        let prepared = await runtime.images.preparedImage(
            for: request,
            priority: .pinnedLauncher,
            scheduleFetchOnMiss: false
        )
        XCTAssertNotNil(prepared)
        try assertPreparedImage(prepared, matches: request)
    }

    func testHighQualityDocumentIconProducesRetinaPreparedVariantsForTabAndPinnedContexts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2PreparedRetina-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pageURL = try XCTUnwrap(URL(string: "https://www.example.com/"))
        let iconURL = try XCTUnwrap(URL(string: "https://www.example.com/s/desktop/favicon_96x96.png"))
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                iconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 96, height: 96),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: fetcher)
        let partition = SumiFaviconPartition.regular(nil)

        let visibleImage = await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: "/s/desktop/favicon_96x96.png",
                    rel: "icon",
                    type: "image/png",
                    sizes: "96x96"
                ),
            ],
            documentURL: pageURL,
            baseURL: pageURL,
            partition: partition,
            webView: nil
        )
        XCTAssertNotNil(visibleImage)

        for context in [SumiFaviconDisplayContext.tabSidebar, .pinnedLauncher] {
            let request = SumiPreparedFaviconRequest(
                pageURL: pageURL,
                partition: partition,
                context: context,
                backingScale: 2
            )
            let image = await runtime.images.preparedImage(
                for: request,
                priority: .visibleSidebarOrTabStrip,
                scheduleFetchOnMiss: false
            )
            try assertPreparedImage(image, matches: request)
        }
    }

    func testNonSquareSVGPreparedImagePreservesAspectRatio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2PreparedSVGAspect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pageURL = try XCTUnwrap(URL(string: "https://testsafebrowsing.example/"))
        let iconURL = try XCTUnwrap(URL(string: "https://testsafebrowsing.example/favicon.svg"))
        let partition = SumiFaviconPartition.regular(nil)
        let runtime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        try runtime.payloadIngestion.storeExternalPayload(
            SumiFaviconTestImages.tallSVGData(),
            faviconURL: iconURL,
            documentURL: pageURL,
            partition: partition
        )

        let request = SumiPreparedFaviconRequest(
            pageURL: pageURL,
            partition: partition,
            context: .pinnedLauncher,
            backingScale: 2
        )
        let image = await runtime.images.preparedImage(
            for: request,
            priority: .pinnedLauncher,
            scheduleFetchOnMiss: false
        )
        try assertPreparedImage(image, matches: request)
        let cgImage = try preparedCGImage(from: image)
        let centerAlpha = try alpha(in: cgImage, x: cgImage.width / 2, y: cgImage.height / 2)
        let leftEdgeAlpha = try alpha(in: cgImage, x: 0, y: cgImage.height / 2)

        XCTAssertGreaterThan(centerAlpha, 200)
        XCTAssertLessThan(leftEdgeAlpha, 10)
    }

    func testLiveDiscoveredHighQualityFaviconIsSharedWithMatchingPinnedLauncherAlias() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2LauncherAlias-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let launchURL = try XCTUnwrap(URL(string: "https://app.example.com/"))
        let documentURL = try XCTUnwrap(URL(string: "https://app.example.com/dashboard"))
        let iconURL = try XCTUnwrap(URL(string: "https://app.example.com/assets/icon-96.png"))
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                iconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 96, height: 96),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: fetcher)
        let partition = SumiFaviconPartition.regular(UUID())

        let visibleImage = await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: "/assets/icon-96.png",
                    rel: "icon",
                    type: "image/png",
                    sizes: "96x96"
                ),
            ],
            documentURL: documentURL,
            baseURL: documentURL,
            partition: partition,
            webView: nil,
            aliasPageURLs: [launchURL]
        )
        XCTAssertNotNil(visibleImage)

        let liveSelection = try XCTUnwrap(runtime.images.cachedSelection(for: documentURL, partition: partition))
        let launcherSelection = try XCTUnwrap(runtime.images.cachedSelection(for: launchURL, partition: partition))
        assertSameStoredFaviconSource(liveSelection, launcherSelection, expectedSourceURL: iconURL)

        let tabRequest = request(pageURL: documentURL, partition: partition, context: .tabSidebar)
        let launcherRequest = request(pageURL: launchURL, partition: partition, context: .pinnedLauncher)
        let tabImage = await runtime.images.preparedImage(for: tabRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        let launcherImage = await runtime.images.preparedImage(for: launcherRequest, priority: .pinnedLauncher, scheduleFetchOnMiss: false)
        try assertPreparedImage(tabImage, matches: tabRequest)
        try assertPreparedImage(launcherImage, matches: launcherRequest)
        XCTAssertNotEqual(tabRequest.pixelSize, launcherRequest.pixelSize)

        let restartedRuntime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        let coldLauncherImage = await restartedRuntime.images.preparedImage(
            for: launcherRequest,
            priority: .pinnedLauncher,
            scheduleFetchOnMiss: false
        )
        try assertPreparedImage(coldLauncherImage, matches: launcherRequest)
        let restartedLauncherSelection = try XCTUnwrap(restartedRuntime.images.cachedSelection(for: launchURL, partition: partition))
        XCTAssertEqual(restartedLauncherSelection.blobID, liveSelection.blobID)
        XCTAssertEqual(restartedLauncherSelection.revision, liveSelection.revision)
    }

    func testPinnedLauncherRootFallbackUpgradesToSharedLiveDocumentSelection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2LauncherRootUpgrade-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let launchURL = try XCTUnwrap(URL(string: "https://www.example.com/app"))
        let documentURL = try XCTUnwrap(URL(string: "https://www.example.com/app/home"))
        let rootIconURL = try XCTUnwrap(URL(string: "https://www.example.com/favicon.ico"))
        let documentIconURL = try XCTUnwrap(URL(string: "https://www.example.com/assets/favicon-96.png"))
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                rootIconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 16, height: 16),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
                documentIconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 96, height: 96),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let notificationCenter = NotificationCenter()
        let cacheUpdated = expectation(
            forNotification: .faviconCacheUpdated,
            object: nil,
            notificationCenter: notificationCenter
        )
        let runtime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: fetcher,
            notificationCenter: notificationCenter
        )
        let partition = SumiFaviconPartition.regular(nil)

        let initialLauncherImage = await runtime.images.preparedImage(
            for: request(pageURL: launchURL, partition: partition, context: .pinnedLauncher),
            priority: .pinnedLauncher,
            scheduleFetchOnMiss: true
        )
        XCTAssertNil(initialLauncherImage)

        await fulfillment(of: [cacheUpdated], timeout: 1)

        let requestedURLs = await fetcher.requestedURLs.map(\.absoluteString)
        XCTAssertTrue(
            runtime.images.hasFavicon(for: launchURL, partition: partition),
            "Expected cold root fallback to be cached for launcher before live discovery. Requests: \(requestedURLs)"
        )
        let rootSelection = try XCTUnwrap(runtime.images.cachedSelection(for: launchURL, partition: partition))
        XCTAssertEqual(rootSelection.sourceKind, .rootFavicon)
        XCTAssertEqual(rootSelection.sourceURL, rootIconURL)

        let visibleImage = await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: "/assets/favicon-96.png",
                    rel: "icon",
                    type: "image/png",
                    sizes: "96x96"
                ),
            ],
            documentURL: documentURL,
            baseURL: documentURL,
            partition: partition,
            webView: nil,
            aliasPageURLs: [launchURL]
        )
        XCTAssertNotNil(visibleImage)

        let liveSelection = try XCTUnwrap(runtime.images.cachedSelection(for: documentURL, partition: partition))
        let launcherSelection = try XCTUnwrap(runtime.images.cachedSelection(for: launchURL, partition: partition))
        assertSameStoredFaviconSource(liveSelection, launcherSelection, expectedSourceURL: documentIconURL)
        XCTAssertNotEqual(launcherSelection.revision, rootSelection.revision)

        let tabRequest = request(pageURL: documentURL, partition: partition, context: .tabSidebar)
        let launcherRequest = request(pageURL: launchURL, partition: partition, context: .pinnedLauncher)
        try assertPreparedImage(
            await runtime.images.preparedImage(for: tabRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false),
            matches: tabRequest
        )
        try assertPreparedImage(
            await runtime.images.preparedImage(for: launcherRequest, priority: .pinnedLauncher, scheduleFetchOnMiss: false),
            matches: launcherRequest
        )
    }

    func testExplicitFaviconRootsDoNotShareStoredState() throws {
        let firstDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconRootA-\(UUID().uuidString)", isDirectory: true)
        let secondDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconRootB-\(UUID().uuidString)", isDirectory: true)
        defer {
            removeFaviconTestDirectories([firstDirectory, secondDirectory])
        }

        let launchURL = try XCTUnwrap(URL(string: "https://root-isolation.example/app"))
        let partition = SumiFaviconPartition.regular(nil)
        let firstRoot = SumiFaviconSystem(
            rootDirectory: firstDirectory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        let secondRoot = SumiFaviconSystem(
            rootDirectory: secondDirectory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )

        try firstRoot.runtime.payloadIngestion.storeExternalPayload(
            SumiFaviconTestImages.pngData(width: 32, height: 32),
            faviconURL: launchURL.appendingPathComponent("favicon.png"),
            documentURL: launchURL,
            partition: partition
        )

        XCTAssertNotNil(firstRoot.runtime.images.cachedSelection(for: launchURL, partition: partition))
        XCTAssertNil(secondRoot.runtime.images.cachedSelection(for: launchURL, partition: partition))
    }

    func testUnavailableFaviconCompositionFailsClosedWithoutPersistentWork() async throws {
        let unavailable = BrowserManagerDataServices.unavailable()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiUnavailableFavicon-\(UUID().uuidString)", isDirectory: true)
        let pageURL = try XCTUnwrap(URL(string: "https://unavailable.example/page"))
        let request = SumiPreparedFaviconRequest(
            pageURL: pageURL,
            partition: .regular(nil),
            context: .pinnedLauncher,
            backingScale: SumiFaviconPresentationMetrics.defaultBackingScale()
        )

        unavailable.faviconCapabilities.prefetch.scheduleColdFetch(
            for: pageURL,
            partition: .regular(nil),
            priority: .pinnedLauncher
        )
        let preparedImage = await unavailable.faviconCapabilities.images.preparedImage(
            for: request,
            priority: .pinnedLauncher,
            scheduleFetchOnMiss: true
        )
        XCTAssertNil(preparedImage)
        let localImage = await unavailable.faviconCapabilities.localIconIngestion.ingestLocalExtensionIcon(
            fileURL: directory.appendingPathComponent("missing.png"),
            documentURL: pageURL,
            partition: .regular(nil),
            context: .pinnedLauncher
        )
        XCTAssertNil(localImage)
        let discoveredImage = await unavailable.faviconCapabilities.liveDiscovery.ingestVisibleTabDiscovery(
            links: [],
            documentURL: pageURL,
            baseURL: pageURL,
            partition: .regular(nil),
            webView: nil,
            aliasPageURLs: []
        )
        XCTAssertNil(discoveredImage)
        await unavailable.faviconService.drainRuntimeTasksForTests(cancel: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLauncherFaviconAliasesRemainPartitionIsolated() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2LauncherPartitionIsolation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let launchURL = try XCTUnwrap(URL(string: "https://partition.example/app"))
        let documentURL = try XCTUnwrap(URL(string: "https://partition.example/app/home"))
        let iconURL = try XCTUnwrap(URL(string: "https://partition.example/icon.png"))
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                iconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 64, height: 64),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: fetcher)
        let profileA = SumiFaviconPartition.regular(UUID())
        let profileB = SumiFaviconPartition.regular(UUID())
        let privateA = SumiFaviconPartition.privateEphemeral(UUID())

        _ = await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: "/icon.png",
                    rel: "icon",
                    type: "image/png",
                    sizes: "64x64"
                ),
            ],
            documentURL: documentURL,
            baseURL: documentURL,
            partition: profileA,
            webView: nil,
            aliasPageURLs: [launchURL]
        )

        XCTAssertNotNil(runtime.images.cachedSelection(for: launchURL, partition: profileA))
        XCTAssertNil(runtime.images.cachedSelection(for: launchURL, partition: profileB))
        XCTAssertNil(runtime.images.cachedSelection(for: launchURL, partition: privateA))
    }

    func testSiteCleanupClearsLauncherAliasMappingsAndPreparedVariants() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2LauncherAliasCleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let launchURL = try XCTUnwrap(URL(string: "https://cleanup.example/app"))
        let documentURL = try XCTUnwrap(URL(string: "https://cleanup.example/app/home"))
        let iconURL = try XCTUnwrap(URL(string: "https://cleanup.example/icon.png"))
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                iconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 64, height: 64),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: fetcher)
        let partition = SumiFaviconPartition.regular(UUID())
        _ = await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: "/icon.png",
                    rel: "icon",
                    type: "image/png",
                    sizes: "64x64"
                ),
            ],
            documentURL: documentURL,
            baseURL: documentURL,
            partition: partition,
            webView: nil,
            aliasPageURLs: [launchURL]
        )

        let launcherRequest = request(pageURL: launchURL, partition: partition, context: .pinnedLauncher)
        let tabRequest = request(pageURL: documentURL, partition: partition, context: .tabSidebar)
        try assertPreparedImage(
            await runtime.images.preparedImage(for: launcherRequest, priority: .pinnedLauncher, scheduleFetchOnMiss: false),
            matches: launcherRequest
        )
        try assertPreparedImage(
            await runtime.images.preparedImage(for: tabRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false),
            matches: tabRequest
        )

        runtime.maintenance.invalidateSite(domain: "cleanup.example", partition: partition)

        XCTAssertNil(runtime.images.cachedSelection(for: launchURL, partition: partition))
        XCTAssertNil(runtime.images.cachedSelection(for: documentURL, partition: partition))
        let clearedLauncherImage = await runtime.images.preparedImage(for: launcherRequest, priority: .pinnedLauncher, scheduleFetchOnMiss: false)
        let clearedTabImage = await runtime.images.preparedImage(for: tabRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        XCTAssertNil(clearedLauncherImage)
        XCTAssertNil(clearedTabImage)
    }

    func testFaviconCleanupInvalidatesOnlyMatchingSiteAndPartitionScopes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2Cleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: RoutingFaviconNetworkFetcher(responses: [:]))
        let profileA = SumiFaviconPartition.regular(UUID())
        let profileB = SumiFaviconPartition.regular(UUID())
        let privateA = SumiFaviconPartition.privateEphemeral(UUID())
        let clearA = try XCTUnwrap(URL(string: "https://clear.example/page"))
        let keepA = try XCTUnwrap(URL(string: "https://keep.example/page"))
        let clearB = try XCTUnwrap(URL(string: "https://clear.example/other-profile"))
        let clearPrivate = try XCTUnwrap(URL(string: "https://clear.example/private"))
        let imageData = try SumiFaviconTestImages.pngData(width: 64, height: 64)

        try runtime.payloadIngestion.storeExternalPayload(imageData, faviconURL: clearA.appendingPathComponent("favicon.png"), documentURL: clearA, partition: profileA)
        try runtime.payloadIngestion.storeExternalPayload(imageData, faviconURL: keepA.appendingPathComponent("favicon.png"), documentURL: keepA, partition: profileA)
        try runtime.payloadIngestion.storeExternalPayload(imageData, faviconURL: clearB.appendingPathComponent("favicon.png"), documentURL: clearB, partition: profileB)
        try runtime.payloadIngestion.storeExternalPayload(imageData, faviconURL: clearPrivate.appendingPathComponent("favicon.png"), documentURL: clearPrivate, partition: privateA)

        let clearARequest = request(pageURL: clearA, partition: profileA)
        let keepARequest = request(pageURL: keepA, partition: profileA)
        let clearBRequest = request(pageURL: clearB, partition: profileB)
        let clearPrivateRequest = request(pageURL: clearPrivate, partition: privateA)
        let initialClearA = await runtime.images.preparedImage(for: clearARequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        let initialKeepA = await runtime.images.preparedImage(for: keepARequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        let initialClearB = await runtime.images.preparedImage(for: clearBRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        let initialClearPrivate = await runtime.images.preparedImage(for: clearPrivateRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        XCTAssertNotNil(initialClearA)
        XCTAssertNotNil(initialKeepA)
        XCTAssertNotNil(initialClearB)
        XCTAssertNotNil(initialClearPrivate)

        runtime.maintenance.invalidateSite(domain: "clear.example", partition: profileA)
        let siteInvalidatedClearA = await runtime.images.preparedImage(for: clearARequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        let siteInvalidatedKeepA = await runtime.images.preparedImage(for: keepARequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        let siteInvalidatedClearB = await runtime.images.preparedImage(for: clearBRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        let siteInvalidatedClearPrivate = await runtime.images.preparedImage(for: clearPrivateRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        XCTAssertNil(siteInvalidatedClearA)
        XCTAssertNotNil(siteInvalidatedKeepA)
        XCTAssertNotNil(siteInvalidatedClearB)
        XCTAssertNotNil(siteInvalidatedClearPrivate)

        try runtime.maintenance.clearPartition(profileB)
        let clearedProfileB = await runtime.images.preparedImage(for: clearBRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        let afterProfileClearPrivate = await runtime.images.preparedImage(for: clearPrivateRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        XCTAssertNil(clearedProfileB)
        XCTAssertNotNil(afterProfileClearPrivate)

        try runtime.maintenance.clearPartition(privateA)
        let clearedPrivate = await runtime.images.preparedImage(for: clearPrivateRequest, priority: .visibleSidebarOrTabStrip, scheduleFetchOnMiss: false)
        XCTAssertNil(clearedPrivate)
    }

    func testClearPartitionRemovesRegularProfileDiskDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2ProfileDelete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profileID = UUID()
        let partition = SumiFaviconPartition.regular(profileID)
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: RoutingFaviconNetworkFetcher(responses: [:]))
        let pageURL = try XCTUnwrap(URL(string: "https://profile-delete.example/page"))
        let imageData = try SumiFaviconTestImages.pngData(width: 64, height: 64)

        try runtime.payloadIngestion.storeExternalPayload(
            imageData,
            faviconURL: pageURL.appendingPathComponent("favicon.png"),
            documentURL: pageURL,
            partition: partition
        )

        let profileDirectory = directory
            .appendingPathComponent("profile-\(profileID.uuidString.lowercased())", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileDirectory.path))

        try runtime.maintenance.clearPartition(partition)

        XCTAssertFalse(FileManager.default.fileExists(atPath: profileDirectory.path))
        XCTAssertNil(runtime.images.cachedPreparedImage(
            for: SumiPreparedFaviconRequest(
                pageURL: pageURL,
                partition: partition,
                context: .tabSidebar,
                backingScale: 2
            )
        ))
    }

    func testClearPrivatePartitionDoesNotPersistFaviconDataToDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2PrivateLifecycle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: RoutingFaviconNetworkFetcher(responses: [:]))
        let partition = SumiFaviconPartition.privateEphemeral(UUID())
        let pageURL = try XCTUnwrap(URL(string: "https://private.example/page"))
        let imageData = try SumiFaviconTestImages.pngData(width: 64, height: 64)

        try runtime.payloadIngestion.storeExternalPayload(
            imageData,
            faviconURL: pageURL.appendingPathComponent("favicon.png"),
            documentURL: pageURL,
            partition: partition
        )
        XCTAssertTrue(runtime.images.hasFavicon(for: pageURL, partition: partition))

        try runtime.maintenance.clearPartition(partition)

        XCTAssertFalse(runtime.images.hasFavicon(for: pageURL, partition: partition))
        let privateEntries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("private-") }
        XCTAssertTrue(privateEntries.isEmpty)
    }

    func testStyledDocumentSVGIconPersistsForColdCacheBackedLookup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2StyledSVG-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pageURL = try XCTUnwrap(URL(string: "https://shield.turtlecute.org/"))
        let iconURL = try XCTUnwrap(URL(string: "https://shield.turtlecute.org/assets/styled/icon.svg"))
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                iconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: SumiFaviconTestImages.styledSVGData(),
                        mimeType: "image/svg+xml",
                        statusCode: 200
                    )
                ),
            ]
        )
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: fetcher)
        let partition = SumiFaviconPartition.regular(nil)

        let visibleImage = await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: "/assets/styled/icon.svg",
                    rel: "icon",
                    type: "image/svg+xml"
                ),
            ],
            documentURL: pageURL,
            baseURL: pageURL,
            partition: partition,
            webView: nil
        )

        XCTAssertNotNil(visibleImage)
        let requestedURLs = await fetcher.requestedURLs.map(\.absoluteString)
        XCTAssertEqual(requestedURLs, [iconURL.absoluteString])

        let restartedRuntime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        let coldImage = await restartedRuntime.images.preparedImage(
            for: SumiPreparedFaviconRequest(
                pageURL: pageURL,
                partition: partition,
                context: .tabSidebar,
                backingScale: 2
            ),
            priority: .visibleSidebarOrTabStrip,
            scheduleFetchOnMiss: false
        )
        XCTAssertNotNil(coldImage)
    }

    private func request(
        pageURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .tabSidebar
    ) -> SumiPreparedFaviconRequest {
        SumiPreparedFaviconRequest(
            pageURL: pageURL,
            partition: partition,
            context: context,
            backingScale: 2
        )
    }

    private func assertSameStoredFaviconSource(
        _ lhs: SumiStoredFaviconSelection,
        _ rhs: SumiStoredFaviconSelection,
        expectedSourceURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.blobID, rhs.blobID, file: file, line: line)
        XCTAssertEqual(lhs.revision, rhs.revision, file: file, line: line)
        XCTAssertEqual(lhs.sourceURL, expectedSourceURL, file: file, line: line)
        XCTAssertEqual(rhs.sourceURL, expectedSourceURL, file: file, line: line)
    }

    private func assertPreparedImage(
        _ image: NSImage?,
        matches request: SumiPreparedFaviconRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let image = try XCTUnwrap(image, file: file, line: line)
        XCTAssertEqual(image.size.width, request.pointSize, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(image.size.height, request.pointSize, accuracy: 0.01, file: file, line: line)

        var rect = NSRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(
            image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
            file: file,
            line: line
        )
        XCTAssertEqual(cgImage.width, request.pixelSize, file: file, line: line)
        XCTAssertEqual(cgImage.height, request.pixelSize, file: file, line: line)
    }

    private func preparedCGImage(
        from image: NSImage?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGImage {
        let image = try XCTUnwrap(image, file: file, line: line)
        var rect = NSRect(origin: .zero, size: image.size)
        return try XCTUnwrap(
            image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
            file: file,
            line: line
        )
    }

    private func alpha(
        in image: CGImage,
        x: Int,
        y: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UInt8 {
        XCTAssertGreaterThanOrEqual(image.bitsPerPixel, 32, file: file, line: line)
        let data = try XCTUnwrap(image.dataProvider?.data, file: file, line: line)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data), file: file, line: line)
        let safeX = max(0, min(x, image.width - 1))
        let safeY = max(0, min(y, image.height - 1))
        let offset = safeY * image.bytesPerRow + safeX * 4 + 3
        XCTAssertLessThan(offset, CFDataGetLength(data), file: file, line: line)
        return bytes[offset]
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

private func removeFaviconTestDirectories(
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

private actor RoutingFaviconNetworkFetcher: SumiFaviconNetworkFetching {
    private let responses: [String: SumiFaviconFetchResult]
    private let onRequest: @Sendable (URL) -> Void
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
