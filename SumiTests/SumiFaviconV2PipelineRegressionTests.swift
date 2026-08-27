import AppKit
import Foundation
import ImageIO
@testable import Sumi
import SumiDomain
import UniformTypeIdentifiers
import WebKit
import XCTest

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
        XCTAssertNotNil(SumiFaviconLookupKey.referenceKey(for: pageURL))

        let runtime = SumiFaviconRuntime(
            rootDirectory: directory.appendingPathComponent("store", isDirectory: true),
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        let partition = SumiFaviconPartition.regular()
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

    func testCachedPreparedImageDoesNotHydrateColdMetadataFromDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiFaviconMemoryOnlyLookup-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try SumiDatabase.inMemory()
        let partition = SumiFaviconPartition.regular()
        let pageURL = try XCTUnwrap(
            URL(string: "https://memory-only-favicon.example/page")
        )
        let writer = SumiFaviconRuntime(
            database: database,
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        try writer.payloadIngestion.storeExternalPayload(
            SumiFaviconTestImages.pngData(width: 32, height: 32),
            faviconURL: pageURL.appendingPathComponent("favicon.png"),
            documentURL: pageURL,
            partition: partition
        )

        let coldReader = SumiFaviconRuntime(
            database: database,
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        XCTAssertNil(coldReader.images.cachedPreparedImage(
            for: request(pageURL: pageURL, partition: partition)
        ))

        try database.transaction {
            try $0.documents.delete(
                key: "favicon.metadata.\(partition.storageComponent)"
            )
        }
        XCTAssertNil(
            coldReader.images.cachedSelection(
                for: pageURL,
                partition: partition
            ),
            "A synchronous cache lookup must not populate metadata from disk"
        )
    }

    func testReferenceKeyAndDocumentURLLookupHitTheSamePreparedImage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2ReferenceKey-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pageURL = try XCTUnwrap(URL(string: "https://example.com/path"))
        let partition = SumiFaviconPartition.regular()
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

        let partition = SumiFaviconPartition.regular()
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
        let partition = SumiFaviconPartition.regular()

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
        let partition = SumiFaviconPartition.regular()

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
        let partition = SumiFaviconPartition.regular()

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
        XCTAssertNotNil(
            runtime.images.cachedSelection(for: pageURL, partition: partition),
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
        let partition = SumiFaviconPartition.regular()
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
        let partition = SumiFaviconPartition.regular()

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

        for context in [
            SumiFaviconDisplayContext.menu,
            .historyBookmarkRow,
            .tabSidebar,
            .pinnedLauncher,
            .siteDataRow,
            .largePreview,
        ] {
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
        let partition = SumiFaviconPartition.regular()
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

    func testNearTargetRasterDiagonalStaysCrispAtRequestedDisplaySize() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2RasterDiagonal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let partition = SumiFaviconPartition.regular()
        let runtime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        for sourceSize in [32, 33] {
            let pageURL = try XCTUnwrap(URL(string: "https://diagonal-\(sourceSize).example/"))
            try runtime.payloadIngestion.storeExternalPayload(
                SumiFaviconTestImages.diagonalPNGData(size: sourceSize),
                faviconURL: pageURL.appendingPathComponent("favicon.png"),
                documentURL: pageURL,
                partition: partition
            )

            for context in [
                SumiFaviconDisplayContext.tabSidebar,
                .pinnedLauncher,
            ] {
                let image = await runtime.images.preparedImage(
                    for: SumiPreparedFaviconRequest(
                        pageURL: pageURL,
                        partition: partition,
                        context: context,
                        backingScale: 2
                    ),
                    priority: .visibleSidebarOrTabStrip,
                    scheduleFetchOnMiss: false
                )
                let cgImage = try preparedCGImage(from: image)
                let centerY = cgImage.height / 2

                XCTAssertGreaterThan(
                    try alpha(in: cgImage, x: 0, y: centerY),
                    200,
                    "The \(sourceSize) px source must fill \(context.rawValue)"
                )
                XCTAssertGreaterThan(
                    try alpha(in: cgImage, x: cgImage.width - 1, y: centerY),
                    200,
                    "The \(sourceSize) px source must fill \(context.rawValue)"
                )
                XCTAssertGreaterThanOrEqual(
                    try brightGrayscalePixelCount(in: cgImage),
                    8,
                    "The \(sourceSize) px diagonal must keep a crisp core in \(context.rawValue)"
                )
            }
        }
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
        let partition = SumiFaviconPartition.regular()

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
        let partition = SumiFaviconPartition.regular()

        let initialLauncherImage = await runtime.images.preparedImage(
            for: request(pageURL: launchURL, partition: partition, context: .pinnedLauncher),
            priority: .pinnedLauncher,
            scheduleFetchOnMiss: true
        )
        XCTAssertNil(initialLauncherImage)

        await fulfillment(of: [cacheUpdated], timeout: 1)

        let requestedURLs = await fetcher.requestedURLs.map(\.absoluteString)
        XCTAssertNotNil(
            runtime.images.cachedSelection(for: launchURL, partition: partition),
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
        let partition = SumiFaviconPartition.regular()
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
            partition: .regular(),
            context: .pinnedLauncher,
            backingScale: SumiFaviconPresentationMetrics.defaultBackingScale()
        )

        unavailable.faviconCapabilities.prefetch.scheduleColdFetch(
            for: pageURL,
            partition: .regular(),
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
            partition: .regular(),
            context: .pinnedLauncher
        )
        XCTAssertNil(localImage)
        let discoveredImage = await unavailable.faviconCapabilities.liveDiscovery.ingestVisibleTabDiscovery(
            links: [],
            documentURL: pageURL,
            baseURL: pageURL,
            partition: .regular(),
            webView: nil,
            aliasPageURLs: []
        )
        XCTAssertNil(discoveredImage)
        await unavailable.faviconService.drainRuntimeTasksForTests(cancel: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLauncherFaviconAliasesAreSharedByRegularProfiles() async throws {
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
        let profileA = SumiFaviconPartition.regular()
        let profileB = SumiFaviconPartition.regular()
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
        XCTAssertNotNil(runtime.images.cachedSelection(for: launchURL, partition: profileB))
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
        let partition = SumiFaviconPartition.regular()
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

    func testFaviconCleanupInvalidatesTheSharedRegularPartition() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2Cleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: RoutingFaviconNetworkFetcher(responses: [:]))
        let profileA = SumiFaviconPartition.regular()
        let profileB = SumiFaviconPartition.regular()
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
        XCTAssertNil(siteInvalidatedClearB)
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

    func testClearPartitionRemovesSharedRegularDiskDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2ProfileDelete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let partition = SumiFaviconPartition.regular()
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
            .appendingPathComponent(partition.storageComponent, isDirectory: true)
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

    func testReplacingSelectionRemovesUnreferencedBlobImmediately() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiFaviconV2ReplacementCleanup-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }

        let partition = SumiFaviconPartition.regular()
        let runtime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        let pageURL = try XCTUnwrap(URL(string: "https://replacement.example/page"))
        try runtime.payloadIngestion.storeExternalPayload(
            SumiFaviconTestImages.pngData(width: 32, height: 32),
            faviconURL: pageURL.appendingPathComponent("first.png"),
            documentURL: pageURL,
            partition: partition
        )
        try runtime.payloadIngestion.storeExternalPayload(
            SumiFaviconTestImages.pngData(width: 64, height: 64),
            faviconURL: pageURL.appendingPathComponent("second.png"),
            documentURL: pageURL,
            partition: partition
        )

        let blobDirectory = directory
            .appendingPathComponent(partition.storageComponent, isDirectory: true)
            .appendingPathComponent("blobs", isDirectory: true)
        let blobs = try FileManager.default.contentsOfDirectory(
            at: blobDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(blobs.count, 1)
        XCTAssertEqual(
            runtime.images.cachedSelection(
                for: pageURL,
                partition: partition
            )?.sourceURL,
            pageURL.appendingPathComponent("second.png")
        )
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
        XCTAssertNotNil(runtime.images.cachedSelection(for: pageURL, partition: partition))

        try runtime.maintenance.clearPartition(partition)

        XCTAssertNil(runtime.images.cachedSelection(for: pageURL, partition: partition))
        let privateEntries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("private-") }
        XCTAssertTrue(privateEntries.isEmpty)
    }

    func testStyledDocumentSVGIconPersistsForColdCacheBackedLookup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2StyledSVG-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }

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
        let partition = SumiFaviconPartition.regular()

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

    private func brightGrayscalePixelCount(
        in image: CGImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Int {
        XCTAssertGreaterThanOrEqual(image.bitsPerPixel, 32, file: file, line: line)
        let data = try XCTUnwrap(image.dataProvider?.data, file: file, line: line)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data), file: file, line: line)
        return (0..<image.height).reduce(into: 0) { count, y in
            for x in 0..<image.width {
                let offset = y * image.bytesPerRow + x * 4
                if bytes[offset] >= 240,
                   bytes[offset + 1] >= 240,
                   bytes[offset + 2] >= 240 {
                    count += 1
                }
            }
        }
    }
}
