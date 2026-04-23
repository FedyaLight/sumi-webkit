import XCTest

@testable import Sumi

@MainActor
final class DownloadListCoordinatorTests: XCTestCase {
    func testSessionStartsEmptyAndCalculatesActiveProgress() throws {
        let coordinator = DownloadListCoordinator()
        XCTAssertTrue(coordinator.items.isEmpty)

        let item = DownloadItem(
            downloadURL: URL(string: "https://example.com/a.txt")!,
            fileName: "a.txt",
            state: .pending
        )
        let progress = DownloadProgress(totalUnitCount: 100)
        coordinator.track(item, progress: progress)
        progress.updateProgress(totalUnitCount: 100, completedUnitCount: 40)
        progress.throughput = 8
        progress.estimatedTimeRemaining = 7
        coordinator.didUpdateProgress(progress, for: item)

        XCTAssertEqual(coordinator.activeCount, 1)
        XCTAssertEqual(coordinator.combinedProgressFraction ?? 0, 0.4, accuracy: 0.001)
        XCTAssertEqual(item.throughput, 8)
        XCTAssertEqual(item.estimatedTimeRemaining, 7)
    }

    func testFinishAndFailureTransitionsKeepInactiveStateForCurrentSession() throws {
        let coordinator = DownloadListCoordinator()
        let item = DownloadItem(
            downloadURL: URL(string: "https://example.com/b.txt")!,
            fileName: "b.txt",
            destinationURL: try makeExistingFile(named: "b.txt"),
            state: .pending,
            completedUnitCount: 0,
            totalUnitCount: 4
        )
        let progress = DownloadProgress(totalUnitCount: 4)
        coordinator.track(item, progress: progress)
        progress.updateProgress(totalUnitCount: 4, completedUnitCount: 4)
        coordinator.didUpdateProgress(progress, for: item)
        coordinator.didFinish(item, finalURL: try makeExistingFile(named: "b-final.txt"))

        XCTAssertEqual(item.state, .completed)
        XCTAssertEqual(coordinator.activeCount, 0)
        XCTAssertEqual(coordinator.items.first?.state, .completed)

        let failed = DownloadItem(
            downloadURL: URL(string: "https://example.com/c.txt")!,
            fileName: "c.txt",
            state: .downloading
        )
        coordinator.track(failed, progress: DownloadProgress(totalUnitCount: -1))
        coordinator.didFail(
            failed,
            error: .failed(message: "Failed", resumeData: Data([9]), isRetryable: true)
        )

        XCTAssertEqual(failed.state, .failed)
        XCTAssertTrue(failed.canRetry)
    }

    func testRuntimeProgressDrivesStartingFinishingAndIsClearedWhenInactive() throws {
        let coordinator = DownloadListCoordinator()
        let item = DownloadItem(
            downloadURL: URL(string: "https://example.com/progress.bin")!,
            fileName: "progress.bin"
        )
        let progress = DownloadProgress(totalUnitCount: 100)

        coordinator.track(item, progress: progress)

        XCTAssertTrue(item.progress === progress)
        XCTAssertEqual(item.state, .downloading)
        XCTAssertEqual(item.statusText, "Starting download…")
        XCTAssertEqual(coordinator.combinedProgressFraction, 0)

        progress.updateProgress(totalUnitCount: 100, completedUnitCount: 100)
        coordinator.didUpdateProgress(progress, for: item)

        XCTAssertEqual(item.statusText, "Finishing download…")
        XCTAssertEqual(coordinator.combinedProgressFraction, 1)

        coordinator.didFinish(item, finalURL: try makeExistingFile(named: "progress.bin"))

        XCTAssertNil(item.progress)
        XCTAssertEqual(item.state, .completed)
        XCTAssertEqual(coordinator.activeCount, 0)
    }

    func testActiveStatusTextUsesCompactByteProgressFormat() throws {
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
        XCTAssertFalse(statusText.split(separator: "/").first?.contains("B") == true)
        XCTAssertFalse(statusText.split(separator: "/").first?.contains("Б") == true)
    }

    func testClearInactiveDownloadsKeepsActiveAndCleansFailedTemporaryFilesOnly() throws {
        let coordinator = DownloadListCoordinator()
        let completedURL = try makeExistingFile(named: "complete.txt")
        let failedTempURL = try makeExistingFile(named: "failed.txt.sumiload")
        let cancelledTempURL = try makeExistingFile(named: "cancelled.txt.sumiload")
        let completed = DownloadItem(
            downloadURL: URL(string: "https://example.com/complete.txt")!,
            fileName: "complete.txt",
            destinationURL: completedURL,
            state: .completed
        )
        let active = DownloadItem(
            downloadURL: URL(string: "https://example.com/active.txt")!,
            fileName: "active.txt",
            state: .downloading
        )
        let failed = DownloadItem(
            downloadURL: URL(string: "https://example.com/failed.txt")!,
            fileName: "failed.txt",
            tempURL: failedTempURL,
            state: .failed,
            error: .failed(message: "Failed", resumeData: nil, isRetryable: false)
        )
        let cancelled = DownloadItem(
            downloadURL: URL(string: "https://example.com/cancelled.txt")!,
            fileName: "cancelled.txt",
            tempURL: cancelledTempURL,
            state: .cancelled,
            error: .cancelled
        )

        coordinator.track(completed, progress: DownloadProgress(totalUnitCount: 1))
        coordinator.didFinish(completed, finalURL: completedURL)
        coordinator.track(active, progress: DownloadProgress(totalUnitCount: -1))
        coordinator.track(failed, progress: DownloadProgress(totalUnitCount: -1))
        coordinator.didFail(
            failed,
            error: .failed(message: "Failed", resumeData: nil, isRetryable: false)
        )
        coordinator.track(cancelled, progress: DownloadProgress(totalUnitCount: -1))
        coordinator.didFail(cancelled, error: .cancelled)

        coordinator.clearInactiveDownloads()

        XCTAssertEqual(coordinator.items.map(\.id), [active.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: completedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedTempURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledTempURL.path))
    }

    private func makeExistingFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(name.utf8).write(to: url)
        return url
    }
}
