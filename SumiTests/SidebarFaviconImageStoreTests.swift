import AppKit
@testable import Sumi
import XCTest

@MainActor
final class SidebarFaviconImageStoreTests: XCTestCase {
    func testLoadKeyIncludesURLPartitionAndRefreshIdentity() throws {
        let store = SidebarFaviconImageStore()
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular()

        let key = store.loadKey(launchURL: launchURL, partition: partition)
        let rowKey = store.loadKey(
            launchURL: launchURL,
            partition: partition,
            context: .tabSidebar
        )

        XCTAssertTrue(key.contains(launchURL.absoluteString))
        XCTAssertTrue(key.contains(partition.storageComponent))
        XCTAssertNotEqual(key, rowKey)
    }

    func testDisabledLoadKeyIgnoresURLAndPartitionPolicyInputs() throws {
        let store = SidebarFaviconImageStore()
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular()

        let key = store.loadKey(
            launchURL: launchURL,
            partition: partition,
            isEnabled: false,
            disabledID: "pin-id"
        )

        XCTAssertEqual(key, "disabled|pin-id")
        XCTAssertFalse(key.contains(launchURL.absoluteString))
        XCTAssertFalse(key.contains(partition.storageComponent))
    }

    func testDomainInvalidationRefreshesOnlyMatchingLaunchURL() async throws {
        let notificationCenter = NotificationCenter()
        let store = SidebarFaviconImageStore(
            notificationCenter: notificationCenter
        )
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular()
        let originalKey = store.loadKey(launchURL: launchURL, partition: partition)

        notificationCenter.post(
            name: .faviconCacheUpdated,
            object: nil,
            userInfo: [NSNotification.Name.faviconCacheUpdatedDomainKey: "other.example"]
        )
        await Task.yield()
        XCTAssertEqual(store.loadKey(launchURL: launchURL, partition: partition), originalKey)

        notificationCenter.post(
            name: .faviconCacheUpdated,
            object: nil,
            userInfo: [NSNotification.Name.faviconCacheUpdatedDomainKey: "example.com"]
        )
        await Task.yield()
        XCTAssertNotEqual(store.loadKey(launchURL: launchURL, partition: partition), originalKey)
    }

    func testPartitionInvalidationRefreshesOnlyMatchingEntry() async throws {
        let notificationCenter = NotificationCenter()
        let store = SidebarFaviconImageStore(
            notificationCenter: notificationCenter
        )
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let matchingPartition = SumiFaviconPartition.regular()
        let otherPartition = SumiFaviconPartition.privateEphemeral(
            try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        )
        let matchingKey = store.loadKey(
            launchURL: launchURL,
            partition: matchingPartition
        )
        let otherKey = store.loadKey(
            launchURL: launchURL,
            partition: otherPartition
        )

        notificationCenter.post(
            name: .faviconCacheUpdated,
            object: nil,
            userInfo: [
                NSNotification.Name.faviconCacheUpdatedDomainKey: "example.com",
                NSNotification.Name.faviconCacheUpdatedPartitionKey:
                    matchingPartition.storageComponent,
            ]
        )
        await Task.yield()

        XCTAssertNotEqual(
            store.loadKey(launchURL: launchURL, partition: matchingPartition),
            matchingKey
        )
        XCTAssertEqual(
            store.loadKey(launchURL: launchURL, partition: otherPartition),
            otherKey
        )
    }

    func testLiveAliasUpdateInvalidatesOnlyAffectedSidebarFavicons() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SidebarFaviconScopedUpdate-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }

        let notificationCenter = NotificationCenter()
        let store = SidebarFaviconImageStore(
            notificationCenter: notificationCenter
        )
        let reader = SidebarFaviconImageReaderStub(image: solidImage())
        let updatedURL = try XCTUnwrap(URL(string: "https://mail.example/inbox"))
        let aliasURL = try XCTUnwrap(URL(string: "https://launcher.example/mail"))
        let unrelatedURL = try XCTUnwrap(URL(string: "https://calendar.example/app"))
        let iconURL = try XCTUnwrap(URL(string: "https://mail.example/favicon.png"))
        let partition = SumiFaviconPartition.regular()

        for url in [updatedURL, aliasURL, unrelatedURL] {
            await store.load(
                launchURL: url,
                partition: partition,
                imageReader: reader
            )
        }
        let updatedKey = store.loadKey(
            launchURL: updatedURL,
            partition: partition
        )
        let aliasKey = store.loadKey(
            launchURL: aliasURL,
            partition: partition
        )
        let unrelatedKey = store.loadKey(
            launchURL: unrelatedURL,
            partition: partition
        )

        let scopedUpdate = faviconUpdateExpectation(
            domain: "mail.example",
            notificationCenter: notificationCenter
        )
        let aliasUpdate = faviconUpdateExpectation(
            domain: "launcher.example",
            notificationCenter: notificationCenter
        )
        let broadUpdate = faviconUpdateExpectation(
            domain: nil,
            notificationCenter: notificationCenter,
            isInverted: true
        )
        let image = try await ingestLiveFavicon(
            rootDirectory: directory,
            notificationCenter: notificationCenter,
            documentURL: updatedURL,
            aliasURL: aliasURL,
            iconURL: iconURL,
            partition: partition
        )
        XCTAssertNotNil(image)

        await fulfillment(
            of: [scopedUpdate, aliasUpdate, broadUpdate],
            timeout: 0.5
        )
        await Task.yield()

        XCTAssertNotEqual(
            store.loadKey(launchURL: updatedURL, partition: partition),
            updatedKey
        )
        XCTAssertNotEqual(
            store.loadKey(launchURL: aliasURL, partition: partition),
            aliasKey
        )
        XCTAssertEqual(
            store.loadKey(launchURL: unrelatedURL, partition: partition),
            unrelatedKey
        )
        XCTAssertNotNil(
            store.nsImage(for: unrelatedURL, partition: partition)
        )
    }

    func testConcurrentLoadsForSameKeyAreCoalesced() async throws {
        let store = SidebarFaviconImageStore()
        let reader = SidebarFaviconImageReaderStub(
            image: solidImage(),
            delayNanoseconds: 20_000_000
        )
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular()

        async let first: Void = store.load(
            launchURL: launchURL,
            partition: partition,
            imageReader: reader
        )
        async let second: Void = store.load(
            launchURL: launchURL,
            partition: partition,
            imageReader: reader
        )
        _ = await (first, second)

        XCTAssertEqual(reader.preparedImageCallCount, 1)
        XCTAssertNotNil(store.image(for: launchURL, partition: partition))
    }

    func testRepeatedReadsUseWeakEntryWithoutRepeatingRepositoryLookup() async throws {
        let store = SidebarFaviconImageStore()
        let reader = SidebarFaviconImageReaderStub(image: solidImage())
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular()

        await store.load(
            launchURL: launchURL,
            partition: partition,
            imageReader: reader
        )
        let lookupCountAfterLoad = reader.cachedPreparedImageCallCount

        XCTAssertNotNil(store.image(for: launchURL, partition: partition))
        XCTAssertNotNil(store.image(for: launchURL, partition: partition))
        XCTAssertNotNil(store.nsImage(for: launchURL, partition: partition))
        XCTAssertEqual(
            reader.cachedPreparedImageCallCount,
            lookupCountAfterLoad
        )
    }

    func testRepeatedColdReadsDoNotRepeatRepositoryLookup() throws {
        let store = SidebarFaviconImageStore()
        let reader = SidebarFaviconImageReaderStub(image: solidImage())
        store.configure(imageReader: reader)
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/cold"))
        let partition = SumiFaviconPartition.regular()

        XCTAssertNil(store.image(for: launchURL, partition: partition))
        XCTAssertNil(store.image(for: launchURL, partition: partition))
        XCTAssertNil(store.nsImage(for: launchURL, partition: partition))
        XCTAssertEqual(reader.cachedPreparedImageCallCount, 1)
    }

    func testPrewarmPublishesImageWithoutMountedViewTask() async throws {
        let store = SidebarFaviconImageStore()
        let reader = SidebarFaviconImageReaderStub(
            image: solidImage(),
            delayNanoseconds: 5_000_000
        )
        store.configure(imageReader: reader)
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular()
        let request = SidebarFaviconImageStore.Request(
            launchURL: launchURL,
            partition: partition,
            context: .pinnedLauncher
        )

        store.prewarm([request, request])
        store.prewarm([request])
        for _ in 0..<100 where store.image(
            for: launchURL,
            partition: partition
        ) == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertNotNil(store.image(for: launchURL, partition: partition))
        XCTAssertEqual(reader.preparedImageCallCount, 1)
    }

    func testLoadCompletesWhenInitiatingViewTaskIsCancelled() async throws {
        let store = SidebarFaviconImageStore()
        let reader = SidebarFaviconImageReaderStub(
            image: solidImage(),
            delayNanoseconds: 20_000_000
        )
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular()

        let viewTask = Task {
            await store.load(
                launchURL: launchURL,
                partition: partition,
                imageReader: reader
            )
        }
        for _ in 0..<100 where reader.preparedImageCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(reader.preparedImageCallCount, 1)

        viewTask.cancel()
        await viewTask.value

        XCTAssertNotNil(store.image(for: launchURL, partition: partition))
    }

    func testResolvableSnapshotIconReplacesColdFallbackAfterStoreLoad() async throws {
        let store = SidebarFaviconImageStore()
        let reader = SidebarFaviconImageReaderStub(image: solidImage())
        store.configure(imageReader: reader)
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular()
        let icon = SpaceSidebarSnapshotIcon.resolvable(
            launchURL: launchURL,
            partition: partition,
            fallback: .system("globe")
        )

        guard case .system("globe") = icon.resolved(using: store) else {
            return XCTFail("A cold snapshot icon must initially use its fallback")
        }

        await icon.load(using: store)

        guard case .image = icon.resolved(using: store) else {
            return XCTFail("The mounted snapshot must observe the loaded favicon")
        }
        XCTAssertEqual(reader.preparedImageCallCount, 1)
    }

    func testFaviconNotificationMatcherMatchesDomainUpdates() throws {
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let matchingNotification = Notification(
            name: .faviconCacheUpdated,
            userInfo: [NSNotification.Name.faviconCacheUpdatedDomainKey: "example.com"]
        )
        let nonMatchingNotification = Notification(
            name: .faviconCacheUpdated,
            userInfo: [NSNotification.Name.faviconCacheUpdatedDomainKey: "other.example"]
        )
        let broadNotification = Notification(name: .faviconCacheUpdated)

        XCTAssertTrue(SumiFaviconNotificationMatcher.update(matchingNotification, matches: launchURL))
        XCTAssertFalse(SumiFaviconNotificationMatcher.update(nonMatchingNotification, matches: launchURL))
        XCTAssertTrue(SumiFaviconNotificationMatcher.update(broadNotification, matches: launchURL))
        XCTAssertFalse(SumiFaviconNotificationMatcher.update(matchingNotification, matches: nil))
    }

    func testFaviconNotificationMatcherHonorsPartitionWhenProvided() throws {
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular()
        let otherPartition = SumiFaviconPartition.privateEphemeral(
            try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        )
        let matchingNotification = Notification(
            name: .faviconCacheUpdated,
            userInfo: [
                NSNotification.Name.faviconCacheUpdatedDomainKey: "example.com",
                NSNotification.Name.faviconCacheUpdatedPartitionKey: partition.storageComponent,
            ]
        )
        let otherPartitionNotification = Notification(
            name: .faviconCacheUpdated,
            userInfo: [
                NSNotification.Name.faviconCacheUpdatedDomainKey: "example.com",
                NSNotification.Name.faviconCacheUpdatedPartitionKey: otherPartition.storageComponent,
            ]
        )

        XCTAssertTrue(
            SumiFaviconNotificationMatcher.update(
                matchingNotification,
                matches: launchURL,
                partition: partition
            )
        )
        XCTAssertFalse(
            SumiFaviconNotificationMatcher.update(
                otherPartitionNotification,
                matches: launchURL,
                partition: partition
            )
        )
    }

    private func faviconUpdateExpectation(
        domain: String?,
        notificationCenter: NotificationCenter,
        isInverted: Bool = false
    ) -> XCTestExpectation {
        let result = expectation(
            forNotification: .faviconCacheUpdated,
            object: nil,
            notificationCenter: notificationCenter
        ) { notification in
            notification.userInfo?[
                NSNotification.Name.faviconCacheUpdatedDomainKey
            ] as? String == domain
        }
        result.isInverted = isInverted
        return result
    }

    private func ingestLiveFavicon(
        rootDirectory: URL,
        notificationCenter: NotificationCenter,
        documentURL: URL,
        aliasURL: URL,
        iconURL: URL,
        partition: SumiFaviconPartition
    ) async throws -> NSImage? {
        let fetcher = RoutingFaviconNetworkFetcher(
            responses: [
                iconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(
                            width: 64,
                            height: 64
                        ),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let runtime = SumiFaviconRuntime(
            rootDirectory: rootDirectory,
            fetcher: fetcher,
            notificationCenter: notificationCenter
        )
        return await runtime.liveDiscovery.ingest(
            links: [
                SumiFaviconDiscoveredLink(
                    href: iconURL.absoluteString,
                    rel: "icon",
                    type: "image/png",
                    sizes: "64x64"
                ),
            ],
            documentURL: documentURL,
            baseURL: documentURL,
            partition: partition,
            webView: nil,
            aliasPageURLs: [documentURL, aliasURL]
        )
    }

    private func solidImage() -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }
    }
}

private final class SidebarFaviconImageReaderStub:
    BrowserFaviconImageReading,
    @unchecked Sendable {
    private let image: NSImage
    private let delayNanoseconds: UInt64
    private let lock = NSLock()
    private var callCount = 0
    private var cachedCallCount = 0
    private var preparedRequests = Set<SumiPreparedFaviconRequest>()

    init(image: NSImage, delayNanoseconds: UInt64 = 0) {
        self.image = image
        self.delayNanoseconds = delayNanoseconds
    }

    var preparedImageCallCount: Int {
        lock.withLock { callCount }
    }

    var cachedPreparedImageCallCount: Int {
        lock.withLock { cachedCallCount }
    }

    func cachedPreparedImage(for request: SumiPreparedFaviconRequest) -> NSImage? {
        lock.withLock {
            cachedCallCount += 1
            return preparedRequests.contains(request) ? image : nil
        }
    }

    func cachedSelection(
        for _: URL,
        partition _: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection? {
        nil
    }

    func preparedImage(
        for request: SumiPreparedFaviconRequest,
        priority _: SumiFaviconFetchPriority,
        scheduleFetchOnMiss _: Bool
    ) async -> NSImage? {
        lock.withLock { callCount += 1 }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        lock.withLock { _ = preparedRequests.insert(request) }
        return image
    }
}
