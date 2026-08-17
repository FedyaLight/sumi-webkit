import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class PersistenceFixtureTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        temporaryDirectories.removeAll()
    }

    override func tearDown() {
        for directory in temporaryDirectories {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                // A failed cleanup is harmless and the system temporary root
                // remains the final owner.
            }
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testSplitArchiveRejectsFutureVersion() throws {
        XCTAssertThrowsError(
            try TabPersistenceCodec().decodeSplitGroupArchive(
                from: fixtureData("tabs/split-groups-unsupported-v3.json")
            )
        )
    }

    func testLogicalBackupFixturesReadV1AndRejectFutureAndMalformed()
        throws {
        let service = SumiBackupService()
        let archive = try service.readBackup(
            from: fixtureData("backups/logical-backup-v1.sumibackup")
        )
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.data.profiles.map(\.name), ["Fixture Profile"])

        for fixtureName in [
            "backups/logical-backup-unsupported-v2.sumibackup",
            "backups/logical-backup-malformed.sumibackup",
        ] {
            XCTAssertThrowsError(
                try service.readBackup(from: fixtureData(fixtureName))
            ) { error in
                XCTAssertTrue(error is SumiImportExportError)
            }
        }
    }

    func testFaviconMetadataFixturesReadV2AndRejectFutureAndMalformed()
        throws {
        let codec = SumiFaviconMetadataCodec()
        XCTAssertEqual(
            try codec.decode(
                fixtureData("favicons/metadata-v2.json")
            ).schemaVersion,
            2
        )
        XCTAssertThrowsError(
            try codec.decode(
                fixtureData("favicons/metadata-unsupported-v3.json")
            )
        ) { error in
            XCTAssertEqual(
                error as? SumiFaviconMetadataCodec.DecodingError,
                .unsupportedSchemaVersion(3)
            )
        }
        XCTAssertThrowsError(
            try codec.decode(
                fixtureData("favicons/metadata-malformed.json")
            )
        )
    }

    @MainActor
    func testBoostFixturesReadShippedStoreAndPreserveMalformedBytes()
        throws {
        let loadedDirectory = try makeTemporaryDirectory()
        try copyFixture(
            "boosts/boosts-shipped-unversioned.json",
            to: loadedDirectory.appendingPathComponent("boosts.json")
        )
        let store = SumiBoostStore(rootDirectory: loadedDirectory)
        let profileID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000501"
        )!
        XCTAssertEqual(
            store.activeBoost(
                for: URL(string: "https://fixture.example/")!,
                profileId: profileID
            )?.data.boostName,
            "Fixture Boost"
        )

        let malformedDirectory = try makeTemporaryDirectory()
        let malformedURL = malformedDirectory.appendingPathComponent(
            "boosts.json"
        )
        try copyFixture("boosts/boosts-malformed.json", to: malformedURL)
        let original = try Data(contentsOf: malformedURL)
        let malformedStore = SumiBoostStore(
            rootDirectory: malformedDirectory
        )
        XCTAssertTrue(
            malformedStore.boosts(
                for: URL(string: "https://fixture.example/")!,
                profileId: profileID
            ).isEmpty
        )
        XCTAssertEqual(try Data(contentsOf: malformedURL), original)
        XCTAssertEqual(
            try Data(
                contentsOf: malformedURL.appendingPathExtension("unreadable")
            ),
            original
        )
    }

    func testAdblockManifestFixturesReadCurrentAndRejectFutureSchema()
        async throws {
        let directory = try makeTemporaryDirectory()
        let activeURL = directory.appendingPathComponent(
            "active-generation.json"
        )
        let archive = AdblockGenerationArchive(rootDirectory: directory)

        try copyFixture("adblock/manifest-v6.json", to: activeURL)
        let manifest = try await archive.activeManifest()
        XCTAssertEqual(
            manifest?.schemaVersion,
            AdblockCompiledGenerationManifest.currentSchemaVersion
        )

        for fixtureName in [
            "adblock/manifest-unsupported-v7.json",
        ] {
            try FileManager.default.removeItem(at: activeURL)
            try copyFixture(fixtureName, to: activeURL)
            do {
                _ = try await archive.activeManifest()
                XCTFail("Expected \(fixtureName) to fail closed")
            } catch {
                XCTAssertEqual(
                    try Data(contentsOf: activeURL),
                    try fixtureData(fixtureName)
                )
            }
        }
    }
}

private extension PersistenceFixtureTests {
    func fixtureURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Fixtures/Persistence/\(relativePath)",
                isDirectory: false
            )
    }

    func fixtureData(_ relativePath: String) throws -> Data {
        try Data(contentsOf: fixtureURL(relativePath))
    }

    func copyFixture(_ relativePath: String, to destination: URL) throws {
        try FileManager.default.copyItem(
            at: fixtureURL(relativePath),
            to: destination
        )
    }

    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiPersistenceFixtureTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }
}
