import Foundation
import XCTest

@testable import Sumi

@MainActor
final class SharedFaviconStorageTests: XCTestCase {
    func testRegularProfilesShareOnePartitionAndPrivateProfilesDoNot() {
        XCTAssertEqual(
            SumiFaviconPartition.regular(),
            SumiFaviconPartition.regular()
        )
        XCTAssertNotEqual(
            SumiFaviconPartition.privateEphemeral(UUID()),
            SumiFaviconPartition.privateEphemeral(UUID())
        )
    }

    func testUpgradeDiscardsOnlyLegacyRegularCaches() throws {
        let database = try SumiDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SharedFaviconStorageTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyPartition = SumiFaviconPartition(
            profileIdentifier: UUID().uuidString,
            isPrivate: false
        )
        let sharedPartition = SumiFaviconPartition.regular()
        let legacyDirectory = root.appendingPathComponent(
            legacyPartition.storageComponent,
            isDirectory: true
        )
        let sharedDirectory = root.appendingPathComponent(
            sharedPartition.storageComponent,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sharedDirectory,
            withIntermediateDirectories: true
        )
        let legacyKey = "favicon.metadata.\(legacyPartition.storageComponent)"
        let sharedKey = "favicon.metadata.\(sharedPartition.storageComponent)"
        try database.transaction {
            try $0.documents.save(Data("legacy".utf8), forKey: legacyKey)
            try $0.documents.save(Data("shared".utf8), forKey: sharedKey)
        }

        SumiFaviconSystem.discardLegacyRegularPartitions(
            database: database,
            rootDirectory: root
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyDirectory.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sharedDirectory.path)
        )
        XCTAssertNil(
            try database.read { try $0.documents.data(forKey: legacyKey) }
        )
        XCTAssertEqual(
            try database.read { try $0.documents.data(forKey: sharedKey) },
            Data("shared".utf8)
        )
    }

    func testDeletingRegularProfileDoesNotClearSharedFavicons() throws {
        let database = try SumiDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SharedFaviconProfileDeletionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let system = SumiFaviconSystem(
            database: database,
            rootDirectory: root,
            fetcher: RoutingFaviconNetworkFetcher(responses: [:])
        )
        let profile = Profile(name: "Regular")
        let pageURL = try XCTUnwrap(URL(string: "https://shared.example/page"))
        let imageData = try SumiFaviconTestImages.pngData(width: 64, height: 64)
        let partition = system.partition(profile: profile)

        try system.runtime.payloadIngestion.storeExternalPayload(
            imageData,
            faviconURL: pageURL.appendingPathComponent("favicon.png"),
            documentURL: pageURL,
            partition: partition
        )
        try system.clearFaviconPartition(for: profile)

        XCTAssertNotNil(
            system.runtime.images.cachedSelection(
                for: pageURL,
                partition: partition
            )
        )
    }
}
