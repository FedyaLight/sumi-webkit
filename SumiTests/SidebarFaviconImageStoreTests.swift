@testable import Sumi
import AppKit
import XCTest

@MainActor
final class SidebarFaviconImageStoreTests: XCTestCase {
    func testLoadKeyIncludesURLPartitionAndRefreshIdentity() throws {
        let store = SidebarFaviconImageStore()
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        let key = store.loadKey(launchURL: launchURL, partition: partition)

        XCTAssertTrue(key.contains(launchURL.absoluteString))
        XCTAssertTrue(key.contains(partition.storageComponent))
    }

    func testDisabledLoadKeyIgnoresURLAndPartitionPolicyInputs() throws {
        let store = SidebarFaviconImageStore()
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

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
        let partition = SumiFaviconPartition.regular(nil)
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
        let matchingPartition = SumiFaviconPartition.regular(
            try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        )
        let otherPartition = SumiFaviconPartition.regular(
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

    func testConcurrentLoadsForSameKeyAreCoalesced() async throws {
        let store = SidebarFaviconImageStore()
        let reader = SidebarFaviconImageReaderStub(
            image: solidImage(),
            delayNanoseconds: 20_000_000
        )
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular(nil)

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

    func testPrewarmPublishesImageWithoutMountedViewTask() async throws {
        let store = SidebarFaviconImageStore()
        let reader = SidebarFaviconImageReaderStub(
            image: solidImage(),
            delayNanoseconds: 5_000_000
        )
        store.configure(imageReader: reader)
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular(nil)
        let request = SidebarFaviconImageStore.Request(
            launchURL: launchURL,
            partition: partition
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
        let partition = SumiFaviconPartition.regular(nil)

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
        let partition = SumiFaviconPartition.regular(nil)
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
        let partition = SumiFaviconPartition.regular(
            try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        )
        let otherPartition = SumiFaviconPartition.regular(
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

    init(image: NSImage, delayNanoseconds: UInt64 = 0) {
        self.image = image
        self.delayNanoseconds = delayNanoseconds
    }

    var preparedImageCallCount: Int {
        lock.withLock { callCount }
    }

    func cachedPreparedImage(for _: SumiPreparedFaviconRequest) -> NSImage? {
        nil
    }

    func cachedSelection(
        for _: URL,
        partition _: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection? {
        nil
    }

    func preparedImage(
        for _: SumiPreparedFaviconRequest,
        priority _: SumiFaviconFetchPriority,
        scheduleFetchOnMiss _: Bool
    ) async -> NSImage? {
        lock.withLock { callCount += 1 }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return image
    }
}
