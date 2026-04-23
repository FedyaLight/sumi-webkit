import XCTest

@testable import Sumi

@MainActor
final class DownloadManagerTests: XCTestCase {
    func testDefaultDownloadsDirectoryUsesTestIsolationUnderXCTest() {
        let directory = DownloadsDirectoryResolver.resolvedDownloadsDirectory()

        XCTAssertEqual(directory.lastPathComponent, "SumiDownloads")
    }

    func testSaveDownloadedDataCreatesCompletedItem() throws {
        let manager = DownloadManager()
        let sourceURL = URL(string: "https://example.com/report.txt")!

        manager.saveDownloadedData(
            Data("report".utf8),
            suggestedFilename: "report.txt",
            mimeType: "text/plain",
            originatingURL: sourceURL
        )

        let item = try waitForCompletedItem(in: manager)
        XCTAssertEqual(item.state, .completed)
        XCTAssertEqual(item.downloadURL, sourceURL)
        XCTAssertEqual(manager.activeDownloadCount, 0)
        XCTAssertNil(manager.combinedProgressFraction)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(item.destinationURL).path))
        XCTAssertNil(item.progress)
    }

    func testNewManagerStartsWithEmptySessionAfterPreviousCompletedDownload() throws {
        let firstManager = DownloadManager()
        let sourceURL = URL(string: "https://example.com/session.txt")!

        firstManager.saveDownloadedData(
            Data("session".utf8),
            suggestedFilename: "session-\(UUID().uuidString).txt",
            mimeType: "text/plain",
            originatingURL: sourceURL
        )

        let item = try waitForCompletedItem(in: firstManager)
        let destinationURL = try XCTUnwrap(item.destinationURL)

        let secondManager = DownloadManager()

        XCTAssertTrue(secondManager.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testExternalDownloadLifecycleUsesRuntimeProgress() throws {
        let manager = DownloadManager()
        let sourceURL = URL(string: "https://example.com/archive.zip")!
        let sourceProgress = Progress(totalUnitCount: 100)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tmp")
        try Data(repeating: 1, count: 100).write(to: temporaryURL)

        let item = manager.beginExternalDownload(
            originalURL: sourceURL,
            websiteURL: sourceURL,
            suggestedFilename: "archive.zip",
            sourceProgress: sourceProgress
        )

        XCTAssertNotNil(item.progress)
        XCTAssertEqual(item.statusText, "Starting download…")
        XCTAssertEqual(manager.activeDownloadCount, 1)

        sourceProgress.completedUnitCount = 100
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        XCTAssertEqual(item.statusText, "Finishing download…")

        manager.finishExternalDownload(item, temporaryURL: temporaryURL, response: nil)
        let completed = try waitForCompletedItem(in: manager)

        XCTAssertEqual(completed.state, .completed)
        XCTAssertNil(completed.progress)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(completed.destinationURL).path))
    }

    func testClearInactiveDownloadsRemovesHistoryButKeepsActiveAndFiles() throws {
        let manager = DownloadManager()
        let completedSourceURL = URL(string: "https://example.com/clear-complete.txt")!
        manager.saveDownloadedData(
            Data("complete".utf8),
            suggestedFilename: "clear-complete-\(UUID().uuidString).txt",
            mimeType: "text/plain",
            originatingURL: completedSourceURL
        )
        let completed = try waitForCompletedItem(in: manager)
        let completedURL = try XCTUnwrap(completed.destinationURL)
        let active = manager.beginExternalDownload(
            originalURL: URL(string: "https://example.com/active.bin")!,
            websiteURL: nil,
            suggestedFilename: "active-\(UUID().uuidString).bin",
            sourceProgress: Progress(totalUnitCount: -1)
        )

        XCTAssertTrue(manager.hasInactiveDownloads)

        manager.clearInactiveDownloads()

        XCTAssertEqual(manager.items.map(\.id), [active.id])
        XCTAssertFalse(manager.hasInactiveDownloads)
        XCTAssertEqual(manager.activeDownloadCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: completedURL.path))
    }

    func testStartupRemovesOrphanedIncompleteDownloads() throws {
        let directory = DownloadsDirectoryResolver.resolvedDownloadsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let orphanURL = directory
            .appendingPathComponent("orphan-\(UUID().uuidString).txt")
            .appendingPathExtension(DownloadFileUtilities.incompleteDownloadExtension)
        try Data("orphan".utf8).write(to: orphanURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanURL.path))

        _ = DownloadManager()

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }

    func testUniqueDestinationAvoidsExistingFiles() throws {
        let filename = "collision-\(UUID().uuidString).txt"
        let first = DownloadFileUtilities.uniqueDestination(for: filename)
        try FileManager.default.createDirectory(
            at: first.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("first".utf8).write(to: first)

        let second = DownloadFileUtilities.uniqueDestination(for: filename)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, first.deletingPathExtension().lastPathComponent + " 1.txt")
    }

    private func waitForCompletedItem(in manager: DownloadManager) throws -> DownloadItem {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let item = manager.items.first, item.state == .completed {
                return item
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return try XCTUnwrap(manager.items.first)
    }
}
