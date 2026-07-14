import AppKit
import Foundation
import XCTest

@testable import Sumi

@MainActor
final class SumiFaviconRuntimeArchitectureTests: XCTestCase {
    func testRuntimeLifetimeDoesNotFollowInFlightColdFetchAndCancelsNetworkWork() async throws {
        let directory = temporaryDirectory(named: "RuntimeLifetime")
        defer { removeTestDirectory(directory, context: "runtime lifetime") }
        let fetcher = RuntimeCancellationAwareFaviconFetcher()
        var runtime: SumiFaviconRuntime? = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: fetcher
        )
        weak let weakRuntime = runtime
        let pageURL = try XCTUnwrap(URL(string: "https://lifetime.example/page"))

        runtime?.coldFetches.schedule(
            pageURL: pageURL,
            partition: .regular(nil),
            priority: .backgroundPrefetch
        )
        await fetcher.waitUntilStarted()
        runtime = nil

        XCTAssertNil(
            weakRuntime,
            "The fetch may retain its resolution pipeline, never the composition root"
        )
        await fetcher.waitUntilCancelled()
        let cancellationCount = await fetcher.cancellationCount
        XCTAssertEqual(cancellationCount, 1)
    }

    func testColdFetchRegistryCoalescesDuplicatePageRequests() async throws {
        let directory = temporaryDirectory(named: "ColdCoalescing")
        defer { removeTestDirectory(directory, context: "cold coalescing") }
        let pageURL = try XCTUnwrap(URL(string: "https://coalescing.example/page"))
        let rootIconURL = try XCTUnwrap(URL(string: "https://coalescing.example/favicon.png"))
        let fetcher = RuntimeRoutingFaviconFetcher(
            responses: [
                rootIconURL.absoluteString: .success(
                    SumiFaviconFetchResponse(
                        data: try SumiFaviconTestImages.pngData(width: 32, height: 32),
                        mimeType: "image/png",
                        statusCode: 200
                    )
                ),
            ]
        )
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: fetcher)
        let partition = SumiFaviconPartition.regular(nil)

        runtime.coldFetches.schedule(
            pageURL: pageURL,
            partition: partition,
            priority: .backgroundPrefetch
        )
        runtime.coldFetches.schedule(
            pageURL: pageURL,
            partition: partition,
            priority: .visibleActiveTab
        )
        await runtime.coldFetches.drainForTests(cancel: false)

        let requestedURLs = await fetcher.requestedURLs
        XCTAssertEqual(requestedURLs, [rootIconURL])
        XCTAssertNotNil(runtime.images.cachedSelection(for: pageURL, partition: partition))
    }

    func testPartitionClearPreventsLateFetchFromResurrectingData() async throws {
        let directory = temporaryDirectory(named: "LateFetchClear")
        defer { removeTestDirectory(directory, context: "late-fetch clear") }
        let fetcher = RuntimeControlledSuccessfulFaviconFetcher(
            imageData: try SumiFaviconTestImages.pngData(width: 32, height: 32)
        )
        let runtime = SumiFaviconRuntime(rootDirectory: directory, fetcher: fetcher)
        let partition = SumiFaviconPartition.regular(UUID())
        let pageURL = try XCTUnwrap(URL(string: "https://clear-race.example/page"))

        runtime.coldFetches.schedule(
            pageURL: pageURL,
            partition: partition,
            priority: .backgroundPrefetch
        )
        await fetcher.waitUntilStarted()
        runtime.maintenance.clearPartition(partition)
        await fetcher.release()
        await fetcher.waitUntilCompleted()
        await runtime.coldFetches.drainForTests(cancel: false)

        XCTAssertNil(runtime.images.cachedSelection(for: pageURL, partition: partition))
        let partitionDirectory = directory.appendingPathComponent(
            partition.storageComponent,
            isDirectory: true
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: partitionDirectory.path))
    }

    func testFailedMetadataCommitRestoresOldMappingAndRemovesNewBlob() throws {
        let directory = temporaryDirectory(named: "CommitRollback")
        defer { removeTestDirectory(directory, context: "commit rollback") }
        let runtime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: RuntimeRoutingFaviconFetcher(responses: [:])
        )
        let partition = SumiFaviconPartition.regular(UUID())
        let oldPageURL = try XCTUnwrap(URL(string: "https://rollback.example/old"))
        let newPageURL = try XCTUnwrap(URL(string: "https://new-rollback.example/new"))

        try runtime.payloadIngestion.storeExternalPayload(
            SumiFaviconTestImages.pngData(width: 16, height: 16),
            faviconURL: oldPageURL.appendingPathComponent("old.png"),
            documentURL: oldPageURL,
            partition: partition
        )
        let oldSelection = try XCTUnwrap(
            runtime.images.cachedSelection(for: oldPageURL, partition: partition)
        )
        let partitionDirectory = directory.appendingPathComponent(
            partition.storageComponent,
            isDirectory: true
        )
        let metadataURL = partitionDirectory.appendingPathComponent("metadata.json")
        let durableOldMetadata = try Data(contentsOf: metadataURL)
        try FileManager.default.removeItem(at: metadataURL)
        try FileManager.default.createDirectory(
            at: metadataURL,
            withIntermediateDirectories: false
        )

        XCTAssertThrowsError(
            try runtime.payloadIngestion.storeExternalPayload(
                SumiFaviconTestImages.pngData(width: 32, height: 32),
                faviconURL: newPageURL.appendingPathComponent("new.png"),
                documentURL: newPageURL,
                partition: partition
            )
        )

        let restoredSelection = try XCTUnwrap(
            runtime.images.cachedSelection(for: oldPageURL, partition: partition)
        )
        XCTAssertEqual(restoredSelection.blobID, oldSelection.blobID)
        XCTAssertEqual(restoredSelection.revision, oldSelection.revision)
        XCTAssertNil(runtime.images.cachedSelection(for: newPageURL, partition: partition))
        let blobFiles = try FileManager.default.contentsOfDirectory(
            at: partitionDirectory.appendingPathComponent("blobs", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(blobFiles.map(\.lastPathComponent), ["\(oldSelection.blobID).png"])
        XCTAssertFalse(durableOldMetadata.isEmpty)
    }

    func testLifecycleNotificationFlushesCoalescedMetadata() async throws {
        let directory = temporaryDirectory(named: "LifecycleFlush")
        defer { removeTestDirectory(directory, context: "lifecycle flush") }
        let notificationCenter = NotificationCenter()
        let runtime = SumiFaviconRuntime(
            rootDirectory: directory,
            fetcher: RuntimeRoutingFaviconFetcher(responses: [:]),
            notificationCenter: notificationCenter
        )
        let partition = SumiFaviconPartition.regular(UUID())
        let pageURL = try XCTUnwrap(URL(string: "https://flush.example/page"))

        runtime.coldFetches.schedule(
            pageURL: pageURL,
            partition: partition,
            priority: .backgroundPrefetch
        )
        await runtime.coldFetches.drainForTests(cancel: false)
        notificationCenter.post(name: NSApplication.willResignActiveNotification, object: nil)

        let metadataURL = directory
            .appendingPathComponent(partition.storageComponent, isDirectory: true)
            .appendingPathComponent("metadata.json")
        let metadata = try String(contentsOf: metadataURL, encoding: .utf8)
        XCTAssertTrue(metadata.contains("flush.example"))
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiFaviconV2\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func removeTestDirectory(_ directory: URL, context: String) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            XCTFail("Failed to remove \(context) test directory: \(error)")
        }
    }
}

private actor RuntimeCancellationAwareFaviconFetcher: SumiFaviconNetworkFetching {
    private var didStart = false
    private var didCancel = false
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cancellationCount = 0

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitUntilCancelled() async {
        guard !didCancel else { return }
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    func fetch(url _: URL, context _: SumiFaviconFetchContext) async -> SumiFaviconFetchResult {
        didStart = true
        let startWaiters = startWaiters
        self.startWaiters.removeAll()
        startWaiters.forEach { $0.resume() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard Task.isCancelled == false else {
                    continuation.resume()
                    return
                }
                fetchContinuation = continuation
            }
        } onCancel: {
            Task { await self.cancelFetch() }
        }
        return .cancelled
    }

    private func cancelFetch() {
        guard didCancel == false else { return }
        cancellationCount += 1
        didCancel = true
        let fetchContinuation = fetchContinuation
        self.fetchContinuation = nil
        fetchContinuation?.resume()
        let cancellationWaiters = cancellationWaiters
        self.cancellationWaiters.removeAll()
        cancellationWaiters.forEach { $0.resume() }
    }
}

private actor RuntimeControlledSuccessfulFaviconFetcher: SumiFaviconNetworkFetching {
    private let imageData: Data
    private var didStart = false
    private var didComplete = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completionWaiters: [CheckedContinuation<Void, Never>] = []

    init(imageData: Data) {
        self.imageData = imageData
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitUntilCompleted() async {
        guard !didComplete else { return }
        await withCheckedContinuation { completionWaiters.append($0) }
    }

    func fetch(url _: URL, context _: SumiFaviconFetchContext) async -> SumiFaviconFetchResult {
        didStart = true
        let startWaiters = startWaiters
        self.startWaiters.removeAll()
        startWaiters.forEach { $0.resume() }
        await withCheckedContinuation { releaseContinuation = $0 }
        didComplete = true
        let completionWaiters = completionWaiters
        self.completionWaiters.removeAll()
        completionWaiters.forEach { $0.resume() }
        return .success(
            SumiFaviconFetchResponse(
                data: imageData,
                mimeType: "image/png",
                statusCode: 200
            )
        )
    }
}

private actor RuntimeRoutingFaviconFetcher: SumiFaviconNetworkFetching {
    private let responses: [String: SumiFaviconFetchResult]
    private(set) var requestedURLs: [URL] = []

    init(responses: [String: SumiFaviconFetchResult]) {
        self.responses = responses
    }

    func fetch(url: URL, context _: SumiFaviconFetchContext) async -> SumiFaviconFetchResult {
        requestedURLs.append(url)
        return responses[url.absoluteString] ?? .failure(.notFound)
    }
}
