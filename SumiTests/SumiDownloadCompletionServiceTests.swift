import CoreServices
import XCTest

@testable import Sumi

final class SumiDownloadCompletionServiceTests: XCTestCase {
    func testFinalizeAppliesWebDownloadQuarantineBeforeMove() throws {
        let sourceURL = URL(string: "https://example.com/archive.zip")!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiDownloadCompletionServiceTests-\(UUID().uuidString)", isDirectory: true)
        let temporaryURL = directory.appendingPathComponent("archive.tmp")
        let destinationURL = directory.appendingPathComponent("archive.zip")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("archive".utf8).write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let finalURL = try SumiDownloadCompletionService.finalizeDownloadedFile(
            temporaryURL: temporaryURL,
            destinationURL: destinationURL,
            sourceURL: sourceURL
        )

        XCTAssertEqual(finalURL, destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))

        let properties = try finalURL
            .resourceValues(forKeys: [.quarantinePropertiesKey])
            .quarantineProperties
        XCTAssertEqual(properties?[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)
    }
}
