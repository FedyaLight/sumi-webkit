import AppKit
import XCTest

@testable import Sumi

final class DownloadProgressTests: XCTestCase {
    func testDeterminateProgressTracksCounts() {
        let progress = DownloadProgress(totalUnitCount: 100)

        progress.updateProgress(totalUnitCount: 100, completedUnitCount: 25)

        XCTAssertEqual(progress.totalUnitCount, 100)
        XCTAssertEqual(progress.completedUnitCount, 25)
        XCTAssertEqual(progress.fractionCompleted, 0.25, accuracy: 0.001)
    }

    func testIndeterminateProgressStaysIndeterminate() {
        let progress = DownloadProgress(totalUnitCount: -1)

        progress.updateProgress(totalUnitCount: -1, completedUnitCount: 2048)

        XCTAssertEqual(progress.totalUnitCount, -1)
        XCTAssertEqual(progress.completedUnitCount, 2048)
    }

    func testCompletionCanReachFullProgress() {
        let progress = DownloadProgress(totalUnitCount: 42)

        progress.updateProgress(totalUnitCount: 42, completedUnitCount: 42)

        XCTAssertEqual(progress.fractionCompleted, 1.0, accuracy: 0.001)
    }

    func testThroughputAndEtaAreDelayedForInitialUpdate() {
        let progress = DownloadProgress(totalUnitCount: 10_000)

        progress.updateProgress(totalUnitCount: 10_000, completedUnitCount: 1_000)

        XCTAssertNil(progress.throughput)
        XCTAssertNil(progress.estimatedTimeRemaining)
    }

    @MainActor
    func testDownloadPresentationProgressCopiesAndTransfersFlyMetadata() {
        let progress = DownloadProgress(totalUnitCount: 100)
        let icon = NSWorkspace.shared.icon(for: .data)
        let rect = NSRect(x: 10, y: 20, width: 64, height: 64)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("presentation.sumiload")

        progress.fileDownloadingSourceURL = URL(string: "https://example.com/file.zip")
        progress.flyToImage = icon
        progress.fileIcon = icon
        progress.fileIconOriginalRect = rect

        let presenter = DownloadFileProgressPresenter(progress: progress)
        presenter.displayProgress(at: tempURL)

        let published = presenter.fileProgress
        XCTAssertEqual(published?.fileURL, tempURL)
        XCTAssertEqual(published?.fileDownloadingSourceURL, progress.fileDownloadingSourceURL)
        XCTAssertNotNil(published?.flyToImage)
        XCTAssertNotNil(published?.fileIcon)
        XCTAssertEqual(published?.fileIconOriginalRect, rect)
        XCTAssertNil(progress.flyToImage)
        XCTAssertNil(progress.fileIconOriginalRect)
    }
}
