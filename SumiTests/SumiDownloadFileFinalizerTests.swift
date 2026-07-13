import CoreServices
import XCTest

@testable import Sumi

final class SumiDownloadFileFinalizerTests: XCTestCase {
    func testFinalizeAppliesWebDownloadQuarantineBeforeMove() async throws {
        let sourceURL = URL(string: "https://example.com/archive.zip")!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiDownloadFileFinalizerTests-\(UUID().uuidString)", isDirectory: true)
        let temporaryURL = directory.appendingPathComponent("archive.tmp")
        let destinationURL = directory.appendingPathComponent("archive.zip")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("archive".utf8).write(to: temporaryURL)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }

        let finalizer = SumiDownloadFileFinalizer(fileManager: .default)
        let finalized = try await finalizer.finalize(
            temporaryURL: temporaryURL,
            destinationURL: destinationURL,
            sourceURL: sourceURL
        )

        XCTAssertEqual(finalized.url, destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))

        let properties = try finalized.url
            .resourceValues(forKeys: [.quarantinePropertiesKey])
            .quarantineProperties
        XCTAssertEqual(properties?[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)
    }

    func testFinalizeNeverOverwritesDestinationThatAppearsAfterAllocation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiDownloadFileFinalizerTests-\(UUID().uuidString)", isDirectory: true)
        let temporaryURL = directory.appendingPathComponent("archive.tmp")
        let destinationURL = directory.appendingPathComponent("archive.zip")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: temporaryURL)
        try Data("existing".utf8).write(to: destinationURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try await SumiDownloadFileFinalizer(fileManager: .default).finalize(
                temporaryURL: temporaryURL,
                destinationURL: destinationURL,
                sourceURL: nil
            )
            XCTFail("Expected collision failure")
        } catch is SumiDownloadFileFinalizationError {
            XCTAssertEqual(try Data(contentsOf: destinationURL), Data("existing".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryURL.path))
        }
    }
}
