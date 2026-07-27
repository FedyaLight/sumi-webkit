import AppKit
import Foundation
import SumiDomain
import XCTest

@testable import Sumi

final class SumiFaviconV2SchedulerAndCacheTests: XCTestCase {
    func testFetchSchedulerCoalescesDuplicateCandidateRequests() async throws {
        let fetchStarted = expectation(description: "coalesced network fetch started")
        let fetcher = ControlledFaviconNetworkFetcher { callNumber in
            if callNumber == 1 {
                fetchStarted.fulfill()
            }
        }
        addTeardownBlock {
            fetcher.releaseAll()
        }
        let scheduler = SumiFaviconFetchScheduler(
            fetcher: fetcher,
            configuration: .init(globalConcurrencyLimit: 2, perOriginConcurrencyLimit: 1)
        )
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let iconURL = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
        let candidate = SumiFaviconCandidate(
            pageURL: pageURL,
            iconURL: iconURL,
            sourceKind: .rootFavicon,
            partition: .regular(nil)
        )

        let first = await scheduler.request(
            candidate: candidate,
            context: .publicRootFallback,
            priority: .visibleActiveTab
        )
        let second = await scheduler.request(
            candidate: candidate,
            context: .publicRootFallback,
            priority: .visibleActiveTab
        )
        await fulfillment(of: [fetchStarted], timeout: 1)
        fetcher.releaseCall(1)
        _ = await (first.value, second.value)

        XCTAssertEqual(fetcher.callCount, 1)
    }

    func testFetchQueueOrdersByPriorityThenOrigin() {
        let low = SumiFaviconFetchQueueOrder(
            priority: .backgroundPrefetch,
            origin: "https://z.example"
        )
        let highSecondOrigin = SumiFaviconFetchQueueOrder(
            priority: .visibleActiveTab,
            origin: "https://b.example"
        )
        let highFirstOrigin = SumiFaviconFetchQueueOrder(
            priority: .visibleActiveTab,
            origin: "https://a.example"
        )

        XCTAssertEqual(
            [low, highSecondOrigin, highFirstOrigin].sorted(
                by: SumiFaviconFetchQueueOrder.isOrderedBefore
            ),
            [highFirstOrigin, highSecondOrigin, low]
        )
    }

    func testCancelledColdFetchDoesNotPoisonNextInFlightFetch() async throws {
        let firstFetchStarted = expectation(description: "cancelled network fetch started")
        let secondFetchStarted = expectation(description: "replacement network fetch started")
        let fetcher = ControlledFaviconNetworkFetcher { callNumber in
            switch callNumber {
            case 1:
                firstFetchStarted.fulfill()
            case 2:
                secondFetchStarted.fulfill()
            default:
                break
            }
        }
        addTeardownBlock {
            fetcher.releaseAll()
        }
        let scheduler = SumiFaviconFetchScheduler(
            fetcher: fetcher,
            configuration: .init(globalConcurrencyLimit: 2, perOriginConcurrencyLimit: 2)
        )
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let iconURL = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
        let candidate = SumiFaviconCandidate(
            pageURL: pageURL,
            iconURL: iconURL,
            sourceKind: .rootFavicon,
            partition: .regular(nil)
        )

        let firstRequest = await scheduler.request(
            candidate: candidate,
            context: .publicRootFallback,
            priority: .backgroundPrefetch
        )
        await fulfillment(of: [firstFetchStarted], timeout: 1)
        await scheduler.cancelAll()

        let secondRequest = await scheduler.request(
            candidate: candidate,
            context: .publicRootFallback,
            priority: .visibleActiveTab
        )
        await fulfillment(of: [secondFetchStarted], timeout: 1)

        fetcher.releaseCall(1)
        let firstResult = await firstRequest.value
        guard case .cancelled = firstResult else {
            return XCTFail("Expected cancelled fetch to remain non-cacheable")
        }

        let thirdRequest = await scheduler.request(
            candidate: candidate,
            context: .publicRootFallback,
            priority: .visibleActiveTab
        )
        XCTAssertEqual(fetcher.callCount, 2)

        fetcher.releaseCall(2)
        let secondResult = await secondRequest.value
        let thirdResult = await thirdRequest.value

        guard case .success = secondResult else {
            return XCTFail("Expected second fetch to complete from live network request")
        }
        guard case .success = thirdResult else {
            return XCTFail("Expected third fetch to coalesce with the second in-flight request")
        }
    }

    func testFailureCacheDurationMapsTransientAndVerifiedFailures() {
        XCTAssertEqual(
            SumiFaviconTTL.failureCacheDuration(for: .transport),
            SumiFaviconTTL.transientTransportFailure
        )
        XCTAssertEqual(
            SumiFaviconTTL.failureCacheDuration(for: .notFound),
            SumiFaviconTTL.verifiedInvalidPayload
        )
        XCTAssertEqual(
            SumiFaviconTTL.failureCacheDuration(for: .invalidPayload),
            SumiFaviconTTL.verifiedInvalidPayload
        )
        XCTAssertEqual(
            SumiFaviconTTL.failureCacheDuration(for: .noIconFound),
            SumiFaviconTTL.noIconFound
        )
    }

    func testExpiredFailureIsRemovedOnLookupAndRefetched() async throws {
        let clock = FaviconTestClock(now: Date(timeIntervalSince1970: 2_000_000_000))
        let fetcher = ImmediateFailureFaviconNetworkFetcher()
        let scheduler = SumiFaviconFetchScheduler(
            fetcher: fetcher,
            configuration: .init(now: { clock.current })
        )
        let candidate = SumiFaviconCandidate(
            pageURL: try XCTUnwrap(URL(string: "https://example.test/")),
            iconURL: try XCTUnwrap(URL(string: "https://example.test/favicon.ico")),
            sourceKind: .rootFavicon,
            partition: .regular(nil)
        )

        let first = await scheduler.request(
            candidate: candidate,
            context: .publicRootFallback,
            priority: .visibleActiveTab
        )
        _ = await first.value
        XCTAssertEqual(fetcher.callCount, 1)

        clock.advance(by: SumiFaviconTTL.transientTransportFailure + 1)
        let second = await scheduler.request(
            candidate: candidate,
            context: .publicRootFallback,
            priority: .visibleActiveTab
        )
        _ = await second.value

        XCTAssertEqual(fetcher.callCount, 2)
        let cachedFailureCount = await scheduler.cachedFailureCountForTests
        XCTAssertEqual(cachedFailureCount, 1)
    }

    func testFailureCacheNeverExceedsHardCap() async throws {
        let clock = FaviconTestClock(now: Date(timeIntervalSince1970: 2_000_000_000))
        let fetcher = ImmediateFailureFaviconNetworkFetcher()
        let scheduler = SumiFaviconFetchScheduler(
            fetcher: fetcher,
            configuration: .init(
                globalConcurrencyLimit: 16,
                perOriginConcurrencyLimit: 16,
                now: { clock.current }
            )
        )
        let pageURL = try XCTUnwrap(URL(string: "https://example.test/"))

        for index in 0..<1_025 {
            let candidate = SumiFaviconCandidate(
                pageURL: pageURL,
                iconURL: try XCTUnwrap(URL(string: "https://example.test/icon-\(index).ico")),
                sourceKind: .documentLink,
                partition: .regular(nil)
            )
            let request = await scheduler.request(
                candidate: candidate,
                context: .publicRootFallback,
                priority: .backgroundPrefetch
            )
            _ = await request.value
        }

        let cachedFailureCount = await scheduler.cachedFailureCountForTests
        XCTAssertEqual(cachedFailureCount, 1_024)
    }

    func testPreparedCacheInvalidatesOnlyMatchingRevision() throws {
        let cache = SumiPreparedFaviconCache(totalCostLimit: 1024 * 1024)
        let request = SumiPreparedFaviconRequest(
            pageURL: try XCTUnwrap(URL(string: "https://example.com/")),
            partition: .regular(nil),
            context: .tabSidebar,
            backingScale: 2
        )
        let first = SumiPreparedFaviconIdentity(
            partition: .regular(nil),
            blobID: "a",
            revision: "ra",
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/a.png")),
            request: request
        )
        let second = SumiPreparedFaviconIdentity(
            partition: .regular(nil),
            blobID: "b",
            revision: "rb",
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/b.png")),
            request: request
        )
        cache.setImage(NSImage(size: NSSize(width: 18, height: 18)), for: first)
        cache.setImage(NSImage(size: NSSize(width: 18, height: 18)), for: second)

        cache.invalidate(partition: .regular(nil), blobID: "a", revision: "ra")

        XCTAssertNil(cache.image(for: first))
        XCTAssertNotNil(cache.image(for: second))
    }

    func testPreparedCacheEvictsOldestEntryWhenIdentityIndexExceedsImageCountLimit() throws {
        let cache = SumiPreparedFaviconCache(totalCostLimit: 1024 * 1024)
        let request = SumiPreparedFaviconRequest(
            pageURL: try XCTUnwrap(URL(string: "https://example.com/")),
            partition: .regular(nil),
            context: .tabSidebar,
            backingScale: 2
        )
        let image = NSImage(size: NSSize(width: 1, height: 1))
        var identities: [SumiPreparedFaviconIdentity] = []

        for index in 0..<513 {
            let identity = SumiPreparedFaviconIdentity(
                partition: .regular(nil),
                blobID: "blob-\(index)",
                revision: "revision-\(index)",
                sourceURL: try XCTUnwrap(URL(string: "https://example.com/icon-\(index).png")),
                request: request
            )
            identities.append(identity)
            cache.setImage(image, for: identity)
        }
        let lastIdentity = try XCTUnwrap(identities.last)

        XCTAssertNil(cache.image(for: identities[0]))
        XCTAssertNotNil(cache.image(for: identities[1]))
        XCTAssertNotNil(cache.image(for: lastIdentity))

        cache.invalidate(partition: .regular(nil), blobID: "blob-1", revision: "revision-1")

        XCTAssertNil(cache.image(for: identities[1]))
        XCTAssertNotNil(cache.image(for: lastIdentity))
    }

    func testPreparedCacheSeparatesContextAndScaleKeys() throws {
        let cache = SumiPreparedFaviconCache(totalCostLimit: 1024 * 1024)
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/icon.png"))
        let sidebarRequest = SumiPreparedFaviconRequest(
            pageURL: pageURL,
            partition: .regular(nil),
            context: .tabSidebar,
            backingScale: 2
        )
        let launcherRequest = SumiPreparedFaviconRequest(
            pageURL: pageURL,
            partition: .regular(nil),
            context: .pinnedLauncher,
            backingScale: 2
        )
        let retinaRequest = SumiPreparedFaviconRequest(
            pageURL: pageURL,
            partition: .regular(nil),
            context: .tabSidebar,
            backingScale: 3
        )
        let sidebarIdentity = SumiPreparedFaviconIdentity(
            partition: .regular(nil),
            blobID: "a",
            revision: "ra",
            sourceURL: sourceURL,
            request: sidebarRequest
        )
        let launcherIdentity = SumiPreparedFaviconIdentity(
            partition: .regular(nil),
            blobID: "a",
            revision: "ra",
            sourceURL: sourceURL,
            request: launcherRequest
        )
        let retinaIdentity = SumiPreparedFaviconIdentity(
            partition: .regular(nil),
            blobID: "a",
            revision: "ra",
            sourceURL: sourceURL,
            request: retinaRequest
        )

        cache.setImage(NSImage(size: NSSize(width: 18, height: 18)), for: sidebarIdentity)

        XCTAssertNotNil(cache.image(for: sidebarIdentity))
        XCTAssertNil(cache.image(for: launcherIdentity))
        XCTAssertNil(cache.image(for: retinaIdentity))
    }

    func testBlobStoreSeparatesRegularProfilesAndPrivatePartitions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2Isolation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = SumiFaviconBlobStorage(rootDirectory: directory)
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/private"))
        let iconURL = try XCTUnwrap(URL(string: "https://example.com/icon.png"))
        let profileA = SumiFaviconPartition.regular(UUID())
        let profileB = SumiFaviconPartition.regular(UUID())
        let privateA = SumiFaviconPartition.privateEphemeral(UUID())
        let imageData = try SumiFaviconTestImages.pngData(width: 32, height: 32)
        let payload = SumiFaviconValidatedPayload(
            data: imageData,
            payloadKind: .png,
            mimeType: "image/png",
            pixelWidth: 32,
            pixelHeight: 32,
            byteCount: imageData.count
        )
        _ = try storage.writer.storeValidatedPayload(
            payload,
            for: SumiFaviconCandidate(
                pageURL: pageURL,
                iconURL: iconURL,
                sourceKind: .documentLink,
                declaredType: "image/png",
                partition: profileA
            )
        )

        XCTAssertNotNil(storage.reader.cachedSelection(for: pageURL, partition: profileA))
        XCTAssertNil(storage.reader.cachedSelection(for: pageURL, partition: profileB))
        XCTAssertNil(storage.reader.cachedSelection(for: pageURL, partition: privateA))
    }

    func testBlobStoreDoesNotRecordNoIconOverFreshPositiveMapping() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2NoIconRace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = SumiFaviconBlobStorage(rootDirectory: directory)
        let pageURL = try XCTUnwrap(URL(string: "https://shield.turtlecute.org/"))
        let iconURL = try XCTUnwrap(URL(string: "https://shield.turtlecute.org/assets/styled/icon.svg"))
        let partition = SumiFaviconPartition.regular(nil)
        let payload = SumiFaviconValidatedPayload(
            data: SumiFaviconTestImages.styledSVGData(),
            payloadKind: .svg,
            mimeType: "image/svg+xml",
            pixelWidth: nil,
            pixelHeight: nil,
            byteCount: SumiFaviconTestImages.styledSVGData().count
        )

        _ = try storage.writer.storeValidatedPayload(
            payload,
            for: SumiFaviconCandidate(
                pageURL: pageURL,
                iconURL: iconURL,
                sourceKind: .documentLink,
                declaredType: "image/svg+xml",
                partition: partition
            )
        )

        storage.writer.recordNoIconFound(for: pageURL, partition: partition)

        XCTAssertFalse(storage.reader.isNoIconFresh(for: pageURL, partition: partition))
        XCTAssertNotNil(storage.reader.cachedSelection(for: pageURL, partition: partition))
    }

    func testClearingPartitionCancelsPendingMetadataPersist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiFaviconV2PendingClear-\(UUID().uuidString)", isDirectory: true)
        defer {
            if FileManager.default.fileExists(atPath: directory.path) {
                do {
                    try FileManager.default.removeItem(at: directory)
                } catch {
                    XCTFail("Failed to remove favicon fixture: \(error)")
                }
            }
        }

        let storage = SumiFaviconBlobStorage(
            rootDirectory: directory,
            persistCoalesceInterval: 60
        )
        let partition = SumiFaviconPartition.regular(UUID())
        let partitionDirectory = directory.appendingPathComponent(
            partition.storageComponent,
            isDirectory: true
        )
        let candidateURL = try XCTUnwrap(URL(string: "https://clear-pending.example/favicon.ico"))

        storage.writer.recordFailure(
            candidateURL: candidateURL,
            partition: partition,
            failureKind: .notFound,
            ttl: 60
        )
        try storage.maintenance.clearPartition(partition)
        storage.maintenance.flushPendingPersists()

        XCTAssertFalse(FileManager.default.fileExists(atPath: partitionDirectory.path))
    }

    func testClearingPartitionPropagatesDiskFailureAndKeepsCacheRetryable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiFaviconV2FailedClear-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileManager = FailingFaviconPartitionRemovalFileManager()
        let storage = SumiFaviconBlobStorage(
            rootDirectory: directory,
            fileManager: fileManager,
            persistCoalesceInterval: 0
        )
        let partition = SumiFaviconPartition.regular(UUID())
        let pageURL = try XCTUnwrap(URL(string: "https://failed-clear.example/"))

        storage.writer.recordNoIconFound(for: pageURL, partition: partition)
        fileManager.rejectRemoval = true

        XCTAssertThrowsError(try storage.maintenance.clearPartition(partition))
        XCTAssertTrue(storage.reader.isNoIconFresh(for: pageURL, partition: partition))

        fileManager.rejectRemoval = false
        try storage.maintenance.clearPartition(partition)

        XCTAssertFalse(storage.reader.isNoIconFresh(for: pageURL, partition: partition))
    }

    func testSessionCookieMatchingUsesOnlyCandidateOriginCookies() throws {
        let url = try XCTUnwrap(URL(string: "https://static.example.com/assets/icon.svg"))
        let matching = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: ".example.com",
                .path: "/assets",
                .name: "session",
                .value: "abc",
                .secure: "TRUE",
            ])
        )
        let wrongDomain = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: ".other.example",
                .path: "/",
                .name: "other",
                .value: "no",
            ])
        )
        let wrongPath = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: ".example.com",
                .path: "/account",
                .name: "path",
                .value: "no",
            ])
        )

        let cookies = SumiCookieMatcher.cookies(
            [matching, wrongDomain, wrongPath],
            matching: url,
            sourceDocumentURL: try XCTUnwrap(URL(string: "https://www.example.com/page"))
        )
        XCTAssertEqual(cookies.map(\.name), ["session"])
    }

    func testSessionCookieMatchingDropsCrossSitePageDeclaredCookies() throws {
        let sourceDocumentURL = try XCTUnwrap(URL(string: "https://attacker.test/page"))
        let iconURL = try XCTUnwrap(URL(string: "https://static.victim.com/assets/icon.svg"))
        let victimCookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: ".victim.com",
                .path: "/assets",
                .name: "session",
                .value: "victim-secret",
                .secure: "TRUE",
            ])
        )

        let cookies = SumiCookieMatcher.cookies(
            [victimCookie],
            matching: iconURL,
            sourceDocumentURL: sourceDocumentURL
        )

        XCTAssertTrue(cookies.isEmpty)
        XCTAssertNil(HTTPCookie.requestHeaderFields(with: cookies)["Cookie"])
    }

    func testSessionCookieMatchingAllowsSameSitePageDeclaredCookies() throws {
        let sourceDocumentURL = try XCTUnwrap(URL(string: "https://www.example.com/page"))
        let iconURL = try XCTUnwrap(URL(string: "https://static.example.com/assets/icon.svg"))
        let sameSiteCookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: ".example.com",
                .path: "/assets",
                .name: "session",
                .value: "same-site",
                .secure: "TRUE",
            ])
        )

        let cookies = SumiCookieMatcher.cookies(
            [sameSiteCookie],
            matching: iconURL,
            sourceDocumentURL: sourceDocumentURL
        )

        XCTAssertEqual(cookies.map(\.name), ["session"])
        XCTAssertEqual(HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], "session=same-site")
    }
}

private final class FailingFaviconPartitionRemovalFileManager: FileManager,
    @unchecked Sendable {
    var rejectRemoval = false

    override func removeItem(at URL: URL) throws {
        if rejectRemoval {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}

private final class FaviconTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        value = now
    }

    var current: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private final class ImmediateFailureFaviconNetworkFetcher: SumiFaviconNetworkFetching,
    @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func fetch(url _: URL, context _: SumiFaviconFetchContext) async -> SumiFaviconFetchResult {
        incrementCallCount()
        return .failure(.transport)
    }

    private func incrementCallCount() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class ControlledFaviconNetworkFetcher: SumiFaviconNetworkFetching, @unchecked Sendable {
    private struct State {
        var callCount = 0
        var releaseContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
        var releasedBeforeStart: Set<Int> = []
        var isTornDown = false
    }

    private let lock = NSLock()
    private let onStart: (Int) -> Void
    private var state = State()

    init(onStart: @escaping (Int) -> Void) {
        self.onStart = onStart
    }

    deinit {
        releaseAll()
    }

    var callCount: Int {
        withLockedState { $0.callCount }
    }

    func releaseCall(_ callNumber: Int) {
        let continuation = withLockedState { state -> CheckedContinuation<Void, Never>? in
            if let continuation = state.releaseContinuations.removeValue(forKey: callNumber) {
                return continuation
            }
            state.releasedBeforeStart.insert(callNumber)
            return nil
        }
        continuation?.resume()
    }

    func releaseAll() {
        let continuations = withLockedState { state -> [CheckedContinuation<Void, Never>] in
            state.isTornDown = true
            let continuations = Array(state.releaseContinuations.values)
            state.releaseContinuations.removeAll()
            state.releasedBeforeStart.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume() }
    }

    func fetch(url _: URL, context _: SumiFaviconFetchContext) async -> SumiFaviconFetchResult {
        let callNumber = withLockedState { state in
            state.callCount += 1
            return state.callCount
        }
        onStart(callNumber)
        await withCheckedContinuation { continuation in
            let shouldResume = withLockedState { state in
                if state.isTornDown || state.releasedBeforeStart.remove(callNumber) != nil {
                    return true
                }
                state.releaseContinuations[callNumber] = continuation
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
        return .success(
            SumiFaviconFetchResponse(
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                mimeType: "image/png",
                statusCode: 200
            )
        )
    }

    private func withLockedState<Result>(_ body: (inout State) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
