import UniformTypeIdentifiers
import XCTest

@testable import Sumi

@MainActor
final class DownloadManagerTests: XCTestCase {
    func testDefaultDownloadsDirectoryUsesTestIsolationUnderXCTest() {
        XCTAssertEqual(
            DownloadsDirectoryResolver.resolvedDownloadsDirectory().lastPathComponent,
            "SumiDownloads"
        )
    }

    func testTestIsolationIgnoresPersistedDownloadsSettings() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let userDownloadsURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        let settings = SumiSettingsService(userDefaults: harness.defaults)

        settings.downloadsAlwaysAskWhereToSave = true
        settings.setDownloadsDirectory(userDownloadsURL)

        XCTAssertNil(settings.resolvedDownloadsDirectoryURL())
        XCTAssertFalse(settings.downloadsDestinationPreference.alwaysAskWhereToSave)
        XCTAssertNil(settings.downloadsDestinationPreference.customDirectoryURL)
        XCTAssertEqual(settings.downloadsDirectoryDisplayName, "SumiDownloads")
    }

    func testTransportSuccessCompletesOneTransaction() async throws {
        let harness = DownloadTestHarness()
        let transport = TestDownloadTransport()
        let sourceURL = URL(string: "https://example.com/archive.zip")!
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: transport,
            originalURL: sourceURL,
            suggestedFilename: "archive.zip"
        ))

        let temporaryURL = await transport.chooseDestination(filename: "archive.zip")
        XCTAssertEqual(temporaryURL, item.tempURL)
        XCTAssertEqual(transport.startCount, 1)
        XCTAssertEqual(item.state, .downloading)

        transport.finish()
        try await waitForState(.completed, item: item)

        XCTAssertEqual(item.destinationURL?.lastPathComponent, "archive.zip")
        XCTAssertEqual(harness.finalizer.finalizeCount, 1)
        XCTAssertEqual(harness.manager.activeDownloadCount, 0)
        XCTAssertEqual(harness.destinations.released.count, 1)
    }

    func testDataSaveUsesSameTransactionAndFinalizationPorts() async throws {
        let harness = DownloadTestHarness()

        harness.manager.saveDownloadedData(
            Data("report".utf8),
            suggestedFilename: "report.txt",
            mimeType: "text/plain",
            originatingURL: URL(string: "https://example.com/report.txt")!
        )
        let item = try XCTUnwrap(harness.manager.items.first)
        try await waitForState(.completed, item: item)

        XCTAssertEqual(harness.destinations.reserveCount, 1)
        XCTAssertEqual(harness.finalizer.finalizeCount, 1)
        XCTAssertEqual(item.completedUnitCount, 6)
    }

    func testCompletedDownloadActionsRouteThroughWorkspacePort() async throws {
        let harness = DownloadTestHarness()
        let transport = TestDownloadTransport()
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: transport,
            originalURL: URL(string: "https://example.com/open.txt")!,
            suggestedFilename: "open.txt",
            openIntent: .systemDefault
        ))
        _ = await transport.chooseDestination(filename: "open.txt")
        transport.finish()
        try await waitForState(.completed, item: item)

        harness.manager.open(item)
        harness.manager.reveal(item)
        harness.manager.openDownloadsFolder()
        let destinationURL = try XCTUnwrap(item.destinationURL)

        XCTAssertEqual(harness.workspace.automaticallyOpened, [destinationURL])
        XCTAssertEqual(harness.workspace.opened, [destinationURL])
        XCTAssertEqual(harness.workspace.revealed, [destinationURL])
        XCTAssertEqual(harness.workspace.folderOpenCount, 1)
    }

    func testCancellationWaitsForTransportAndRejectsLaterFinish() async throws {
        let harness = DownloadTestHarness()
        let transport = TestDownloadTransport()
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: transport,
            originalURL: URL(string: "https://example.com/cancel.bin")!,
            suggestedFilename: "cancel.bin"
        ))
        _ = await transport.chooseDestination(filename: "cancel.bin")

        harness.manager.cancel(item)
        XCTAssertEqual(transport.cancelCount, 1)
        XCTAssertEqual(item.state, .downloading)

        transport.finishCancellation()
        try await waitForState(.cancelled, item: item)
        transport.finish()

        XCTAssertEqual(item.state, .cancelled)
        XCTAssertEqual(harness.finalizer.finalizeCount, 0)
        XCTAssertEqual(harness.progress.publications.first?.stopCount, 1)
    }

    func testTransportFailurePreservesResumeDataAndRetryability() throws {
        let harness = DownloadTestHarness()
        let transport = TestDownloadTransport()
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: transport,
            originalURL: URL(string: "https://example.com/failure.bin")!,
            suggestedFilename: "failure.bin"
        ))
        let resumeData = Data([1, 2, 3])

        transport.fail(resumeData: resumeData)

        XCTAssertEqual(item.state, .failed)
        XCTAssertEqual(item.error?.resumeData, resumeData)
        XCTAssertTrue(item.canRetry)
        XCTAssertEqual(harness.finalizer.finalizeCount, 0)
    }

    func testFinalizerFailureBecomesMoveFailureAndRemovesTemporaryFile() async throws {
        let finalizer = TestDownloadFinalizer(outcome: .failure("disk full"))
        let harness = DownloadTestHarness(finalizer: finalizer)
        let transport = TestDownloadTransport()
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: transport,
            originalURL: URL(string: "https://example.com/finalize.bin")!,
            suggestedFilename: "finalize.bin"
        ))
        let destination = await transport.chooseDestination(filename: "finalize.bin")
        let temporaryURL = try XCTUnwrap(destination)

        transport.finish()
        try await waitForState(.failed, item: item)

        XCTAssertEqual(item.error?.errorDescription, "disk full")
        XCTAssertEqual(finalizer.finalizeCount, 1)
        try await waitUntil { finalizer.removedURLs.contains(temporaryURL) }
    }

    func testDestinationAllocatorAvoidsDiskAndInFlightCollisions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadCollision-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        try Data().write(to: directory.appendingPathComponent("report.txt"))
        let fileManager = TestDownloadAllocationFileManager()
        let allocator = SumiDownloadDestinationAllocator(fileManager: fileManager)
        let preference = SumiDownloadDestinationPreference(
            alwaysAskWhereToSave: false,
            customDirectoryURL: directory
        )
        let request = DownloadDestinationRequest(
            suggestedFilename: "report.txt",
            response: nil,
            sourceURL: URL(string: "https://example.com/report.txt")!,
            preference: preference
        )

        let firstReservation = await allocator.reserve(request)
        let secondReservation = await allocator.reserve(request)
        let first = try XCTUnwrap(firstReservation)
        let second = try XCTUnwrap(secondReservation)

        XCTAssertEqual(first.fileName, "report 1.txt")
        XCTAssertEqual(second.fileName, "report 2.txt")
        XCTAssertNotEqual(first.tempURL, second.tempURL)

        try Data([1]).write(to: first.tempURL)
        let renewedReservation = await allocator.renewTemporaryDestination(
            for: first
        )
        let renewed = try XCTUnwrap(renewedReservation)
        XCTAssertNotEqual(renewed.tempURL, first.tempURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renewed.tempURL.path))

        allocator.release(first)
        let thirdReservation = await allocator.reserve(request)
        let third = try XCTUnwrap(thirdReservation)
        XCTAssertEqual(third.fileName, "report 3.txt")
        XCTAssertGreaterThan(fileManager.recordedFilesystemAccessCount, 0)
        XCTAssertFalse(fileManager.accessedFromMainThread)

        allocator.release(renewed)
        allocator.release(second)
        allocator.release(third)
    }

    func testRetryTransportIsAttachedOnceAndFirstAttachmentRetainsAuthority() throws {
        let harness = DownloadTestHarness()
        let firstRetry = TestDownloadRetryTransport()
        let duplicateRetry = TestDownloadRetryTransport()

        XCTAssertTrue(harness.manager.attachRetryTransport(firstRetry))
        XCTAssertFalse(harness.manager.attachRetryTransport(duplicateRetry))

        let transport = TestDownloadTransport()
        let item = try XCTUnwrap(harness.manager.addDownload(
            transport: transport,
            originalURL: URL(string: "https://example.com/retry-once.bin")!,
            suggestedFilename: "retry-once.bin"
        ))
        transport.fail(resumeData: Data([1]))

        harness.manager.retry(item)

        XCTAssertEqual(firstRetry.requests.count, 1)
        XCTAssertTrue(duplicateRetry.requests.isEmpty)
        XCTAssertEqual(firstRetry.transport.startCount, 1)
    }

    func testOrphanCleanupIsDeferredUntilFirstDestinationAllocationAndRunsOnce() async {
        let cleaner = TestDownloadOrphanCleaner()
        let allocator = SumiDownloadDestinationAllocator(
            fileManager: TestDownloadAllocationFileManager(),
            orphanCleaner: cleaner
        )
        let preference = SumiDownloadDestinationPreference(
            alwaysAskWhereToSave: false,
            customDirectoryURL: URL(
                fileURLWithPath: "/tmp/deferred-downloads",
                isDirectory: true
            )
        )
        let firstRequest = DownloadDestinationRequest(
            suggestedFilename: "first.bin",
            response: nil,
            sourceURL: URL(string: "https://example.com/first.bin")!,
            preference: preference
        )
        let secondRequest = DownloadDestinationRequest(
            suggestedFilename: "second.bin",
            response: nil,
            sourceURL: URL(string: "https://example.com/second.bin")!,
            preference: preference
        )

        XCTAssertEqual(cleaner.callCount, 0)
        await Task.yield()
        XCTAssertEqual(cleaner.callCount, 0)

        let first = await allocator.reserve(firstRequest)
        XCTAssertEqual(cleaner.callCount, 1)
        XCTAssertEqual(cleaner.preferences, [preference])

        let second = await allocator.reserve(secondRequest)

        XCTAssertEqual(cleaner.callCount, 1)
        if let first {
            allocator.release(first)
        }
        if let second {
            allocator.release(second)
        }
    }

    func testOrphanCleanerRemovesOnlyIncompleteFilesAtLifecycleDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadOrphans-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        let orphan = directory.appendingPathComponent("partial.bin.sumiload")
        let completed = directory.appendingPathComponent("completed.bin")
        try Data([1]).write(to: orphan)
        try Data([2]).write(to: completed)

        await SumiDownloadOrphanCleaner(fileManager: .default).removeOrphanedDownloads(
            preference: SumiDownloadDestinationPreference(
                alwaysAskWhereToSave: false,
                customDirectoryURL: directory
            )
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: completed.path))
    }

    func testUnavailableCompositionFailsClosedAndIsInert() async {
        let manager = DownloadManager.unavailable()
        let transport = TestDownloadTransport()

        XCTAssertFalse(manager.isAvailable)
        XCTAssertNil(manager.addDownload(
            transport: transport,
            originalURL: URL(string: "https://example.com/unavailable.bin")!,
            suggestedFilename: "unavailable.bin"
        ))
        manager.saveDownloadedData(
            Data([1]),
            suggestedFilename: "ignored.bin",
            mimeType: nil,
            originatingURL: URL(string: "https://example.com/ignored.bin")!
        )

        XCTAssertEqual(transport.cancelCount, 1)
        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertEqual(manager.activeDownloadCount, 0)
        XCTAssertNil(manager.combinedProgressFraction)
    }

    func testDangerousDownloadTypesAreNotAutoOpenedByPolicy() {
        let identity = SumiDownloadContentIdentity.resolve(
            mimeType: nil,
            filename: "Invoice.app"
        )
        let resolved = SumiDownloadPolicyResolver.resolve(
            origin: .responseForcedDownload,
            identity: identity,
            handler: SumiContentHandlerRecord(
                contentType: UTType.applicationBundle.identifier,
                displayName: "Application",
                handler: .useSystemDefault,
                applicationURL: nil
            ),
            fallback: .ask
        )

        XCTAssertTrue(identity.requiresOpeningConfirmation)
        XCTAssertEqual(resolved, .prompt(canPersistChoice: false))
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
