import XCTest

@testable import Sumi

@MainActor
final class DownloadListCoordinatorTests: XCTestCase {
    func testSessionStartsEmptyAndCalculatesActiveProgress() throws {
        let coordinator = DownloadListCoordinator()
        XCTAssertTrue(coordinator.items.isEmpty)

        let item = DownloadItem(
            downloadURL: URL(string: "https://example.com/a.txt")!,
            websiteURL: nil,
            fileName: "a.txt",
            state: .pending
        )
        coordinator.track(item)

        coordinator.didUpdateProgress(
            totalUnitCount: 100,
            completedUnitCount: 40,
            throughput: 8,
            estimatedTimeRemaining: 7,
            for: item
        )

        XCTAssertEqual(coordinator.activeCount, 1)
        XCTAssertEqual(coordinator.combinedProgressFraction ?? 0, 0.4, accuracy: 0.001)
        XCTAssertEqual(item.throughput, 8)
        XCTAssertEqual(item.estimatedTimeRemaining, 7)
    }

    func testFinishAndFailureTransitionsKeepInactiveStateForCurrentSession() throws {
        let coordinator = DownloadListCoordinator()
        let item = DownloadItem(
            downloadURL: URL(string: "https://example.com/b.txt")!,
            websiteURL: nil,
            fileName: "b.txt",
            destinationURL: try makeExistingFile(named: "b.txt"),
            state: .pending,
            completedUnitCount: 0,
            totalUnitCount: 4
        )
        coordinator.track(item)

        coordinator.didUpdateProgress(
            totalUnitCount: 4,
            completedUnitCount: 4,
            throughput: nil,
            estimatedTimeRemaining: nil,
            for: item
        )
        coordinator.didFinish(item, finalURL: try makeExistingFile(named: "b-final.txt"))

        XCTAssertEqual(item.state, .completed)
        XCTAssertEqual(coordinator.activeCount, 0)
        XCTAssertEqual(coordinator.items.first?.state, .completed)

        let failed = DownloadItem(
            downloadURL: URL(string: "https://example.com/c.txt")!,
            websiteURL: nil,
            fileName: "c.txt",
            state: .downloading
        )
        coordinator.track(failed)
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
            websiteURL: nil,
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
            websiteURL: nil,
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
            websiteURL: nil,
            fileName: "complete.txt",
            destinationURL: completedURL,
            state: .completed
        )
        let active = DownloadItem(
            downloadURL: URL(string: "https://example.com/active.txt")!,
            websiteURL: nil,
            fileName: "active.txt",
            state: .downloading
        )
        let failed = DownloadItem(
            downloadURL: URL(string: "https://example.com/failed.txt")!,
            websiteURL: nil,
            fileName: "failed.txt",
            tempURL: failedTempURL,
            state: .failed,
            error: .failed(message: "Failed", resumeData: nil, isRetryable: false)
        )
        let cancelled = DownloadItem(
            downloadURL: URL(string: "https://example.com/cancelled.txt")!,
            websiteURL: nil,
            fileName: "cancelled.txt",
            tempURL: cancelledTempURL,
            state: .cancelled,
            error: .cancelled
        )

        [completed, active, failed, cancelled].forEach(coordinator.track)

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
