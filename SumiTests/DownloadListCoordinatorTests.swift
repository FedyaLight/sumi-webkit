import Combine
import XCTest

@testable import Sumi

@MainActor
final class DownloadListCoordinatorTests: XCTestCase {
    func testCoordinatorPublishesSynchronousTransitionsOnce() throws {
        let harness = DownloadTestHarness()
        var publicationCount = 0
        let publication = harness.manager.$items
            .dropFirst()
            .sink { _ in publicationCount += 1 }
        let firstTransport = TestDownloadTransport()
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: firstTransport,
            originalURL: URL(string: "https://example.com/once.bin")!,
            suggestedFilename: "once.bin"
        ))

        XCTAssertEqual(publicationCount, 1)

        firstTransport.fail(resumeData: Data([1]))
        publicationCount = 0
        XCTAssertTrue(
            harness.manager.attachRetryTransport(TestDownloadRetryTransport())
        )
        harness.manager.retry(item)
        XCTAssertEqual(publicationCount, 1)

        let saveHarness = DownloadTestHarness()
        var savePublicationCount = 0
        let savePublication = saveHarness.manager.$items
            .dropFirst()
            .sink { _ in savePublicationCount += 1 }
        saveHarness.manager.saveDownloadedData(
            Data([1]),
            suggestedFilename: "saved.bin",
            mimeType: nil,
            originatingURL: URL(string: "https://example.com/saved.bin")!
        )
        XCTAssertEqual(savePublicationCount, 1)

        let clearHarness = DownloadTestHarness()
        let failedTransport = TestDownloadTransport()
        let failedItem = try XCTUnwrap(clearHarness.manager.addDownload(
            transport: failedTransport,
            originalURL: URL(string: "https://example.com/clear.bin")!,
            suggestedFilename: "clear.bin"
        ))
        failedTransport.fail()
        XCTAssertEqual(failedItem.state, .failed)
        var clearPublicationCount = 0
        let clearPublication = clearHarness.manager.$items
            .dropFirst()
            .sink { _ in clearPublicationCount += 1 }
        clearHarness.manager.clearInactiveDownloads()
        XCTAssertEqual(clearPublicationCount, 1)

        withExtendedLifetime((publication, savePublication, clearPublication)) {}
    }

    func testCoordinatorEventSinkIsAttachedExactlyOnce() {
        let harness = DownloadTestHarness()

        XCTAssertFalse(
            harness.coordinator.attachEventSink(
                TestDownloadListCoordinatorEventSink()
            )
        )
    }

    func testCoordinatorEventSinkCannotRebindAfterWeakSinkIsReleased() {
        let coordinator = DownloadListCoordinator(
            transactionFactory: DownloadTransactionFactory(
                destinations: TestDownloadDestinationAllocator(),
                finalizer: TestDownloadFinalizer(),
                progressPublisher: TestDownloadProgressPublisher()
            ),
            promptPresenter: TestDownloadPromptPresenter()
        )
        weak var releasedSink: TestDownloadListCoordinatorEventSink?

        do {
            let firstSink = TestDownloadListCoordinatorEventSink()
            releasedSink = firstSink
            XCTAssertTrue(coordinator.attachEventSink(firstSink))
        }

        XCTAssertNil(releasedSink)
        XCTAssertFalse(
            coordinator.attachEventSink(TestDownloadListCoordinatorEventSink())
        )
    }

    func testEventDrivenProgressPublishesAggregateState() async throws {
        let harness = DownloadTestHarness()
        let transport = TestDownloadTransport(totalUnitCount: 100)
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: transport,
            originalURL: URL(string: "https://example.com/progress.bin")!,
            suggestedFilename: "progress.bin"
        ))
        _ = await transport.chooseDestination(filename: "progress.bin")
        let publication = try XCTUnwrap(harness.progress.publications.first)

        publication.emit(completed: 40, total: 100, throughput: 8, remaining: 7)

        XCTAssertEqual(harness.manager.activeDownloadCount, 1)
        XCTAssertEqual(harness.manager.combinedProgressFraction ?? 0, 0.4, accuracy: 0.001)
        XCTAssertEqual(item.completedUnitCount, 40)
        XCTAssertEqual(item.throughput, 8)
        XCTAssertEqual(item.estimatedTimeRemaining, 7)
    }

    func testRetryRejectsStaleProgressAndCompletionFromOldAttempt() async throws {
        let harness = DownloadTestHarness()
        let firstTransport = TestDownloadTransport(totalUnitCount: 100)
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: firstTransport,
            originalURL: URL(string: "https://example.com/retry.bin")!,
            suggestedFilename: "retry.bin"
        ))
        let firstDestination = await firstTransport.chooseDestination(filename: "retry.bin")
        let firstTemporaryURL = try XCTUnwrap(firstDestination)
        let firstPublication = try XCTUnwrap(harness.progress.publications.first)
        firstTransport.fail(resumeData: Data([1]))
        let receipt = try XCTUnwrap(harness.coordinator.makeRetryReceipt(for: item))
        let secondTransport = TestDownloadTransport(totalUnitCount: 100)

        XCTAssertTrue(harness.coordinator.attachRetry(
            transport: secondTransport,
            to: item,
            receipt: receipt
        ))
        let secondDestination = await secondTransport.chooseDestination(filename: "retry.bin")
        let secondTemporaryURL = try XCTUnwrap(secondDestination)
        let secondPublication = try XCTUnwrap(harness.progress.publications.last)
        secondPublication.emit(completed: 20, total: 100)

        XCTAssertEqual(
            harness.finalizer.removedURLs.filter { $0 == firstTemporaryURL }.count,
            1
        )
        XCTAssertFalse(harness.finalizer.removedURLs.contains(secondTemporaryURL))

        firstPublication.emit(completed: 95, total: 100)
        firstTransport.finish()

        XCTAssertEqual(item.state, .downloading)
        XCTAssertEqual(item.completedUnitCount, 20)
        XCTAssertEqual(harness.finalizer.finalizeCount, 0)
        XCTAssertEqual(harness.destinations.renewCount, 1)
        XCTAssertNotEqual(firstTemporaryURL, secondTemporaryURL)
        XCTAssertEqual(item.destinationURL?.lastPathComponent, "retry.bin")
        XCTAssertEqual(
            harness.finalizer.removedURLs.filter { $0 == firstTemporaryURL }.count,
            1
        )
        XCTAssertFalse(harness.finalizer.removedURLs.contains(secondTemporaryURL))

        secondTransport.finish()
        try await waitForState(.completed, item: item)
        XCTAssertEqual(harness.finalizer.finalizeCount, 1)
    }

    func testNonResumableTransportFailureReleasesAndRemovesPartialFile() async throws {
        let harness = DownloadTestHarness()
        let transport = TestDownloadTransport()
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: transport,
            originalURL: URL(string: "https://example.com/partial.bin")!,
            suggestedFilename: "partial.bin"
        ))
        let destination = await transport.chooseDestination(filename: "partial.bin")
        let temporaryURL = try XCTUnwrap(destination)

        transport.fail()
        try await waitForState(.failed, item: item)
        try await waitUntil { harness.finalizer.removedURLs.contains(temporaryURL) }

        XCTAssertFalse(item.canRetry)
        XCTAssertEqual(harness.destinations.released.count, 1)
    }

    func testDestinationRejectionCancelsTransactionWithoutStartingFinalization() async throws {
        let harness = DownloadTestHarness()
        harness.destinations.rejectsReservation = true
        let transport = TestDownloadTransport()
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: transport,
            originalURL: URL(string: "https://example.com/rejected.bin")!,
            suggestedFilename: "rejected.bin"
        ))

        let destination = await transport.chooseDestination(filename: "rejected.bin")
        XCTAssertNil(destination)

        XCTAssertEqual(item.state, .cancelled)
        XCTAssertEqual(harness.finalizer.finalizeCount, 0)
        XCTAssertEqual(harness.progress.publications.first?.stopCount, 1)
    }

    func testClearInactiveRemovesHistoryButKeepsActiveTransaction() async throws {
        let harness = DownloadTestHarness()
        let failedTransport = TestDownloadTransport()
        let failed = try XCTUnwrap(harness.manager.addDownload(
            transport: failedTransport,
            originalURL: URL(string: "https://example.com/failed.bin")!,
            suggestedFilename: "failed.bin"
        ))
        _ = await failedTransport.chooseDestination(filename: "failed.bin")
        failedTransport.fail(resumeData: Data([1]))
        let activeTransport = TestDownloadTransport()
        let active = try XCTUnwrap(harness.manager.addDownload(
            transport: activeTransport,
            originalURL: URL(string: "https://example.com/active.bin")!,
            suggestedFilename: "active.bin"
        ))

        harness.manager.clearInactiveDownloads()

        XCTAssertEqual(harness.manager.items.map(\.id), [active.id])
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(harness.manager.activeDownloadCount, 1)
    }

    func testActiveStatusTextUsesCompactByteProgressFormat() {
        let item = DownloadItem(
            downloadURL: URL(string: "https://example.com/compact.bin")!,
            fileName: "compact.bin",
            state: .downloading,
            completedUnitCount: 25_800_000,
            totalUnitCount: 164_500_000
        )

        let statusText = item.activeStatusText

        XCTAssertTrue(statusText.contains("/"))
        XCTAssertFalse(statusText.contains(" of "))
        XCTAssertNotEqual(statusText.split(separator: "/").first?.contains("B"), true)
        XCTAssertNotEqual(statusText.split(separator: "/").first?.contains("Б"), true)
    }

    private func waitForState(
        _ state: DownloadState,
        item: DownloadItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await waitUntil(file: file, line: line) { item.state == state }
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}
