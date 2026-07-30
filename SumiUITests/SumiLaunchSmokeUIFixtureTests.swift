import Darwin
import Foundation
import XCTest

@MainActor
final class SumiLaunchSmokeUIFixtureTests: SumiLaunchSmokeUITestCase {
    func testBundledFixtureResolvesWithExactFamilyAndHashes() throws {
        let family = try SumiSmokeStoreFixture.resolveBundledFamily()
        let bundle = Bundle(for: SumiLaunchSmokeUITestCase.self)

        XCTAssertEqual(family.manifest.version, 1)
        XCTAssertEqual(family.manifest.family, SumiSmokeStoreFixture.expectedFamily)
        XCTAssertEqual(family.manifest.files.map(\.name), SumiSmokeStoreFixture.expectedFileNames)
        XCTAssertEqual(family.manifest.provenance.sourceFamily, "unified-database")
        XCTAssertTrue(
            family.fileURLs.allSatisfy { $0.deletingLastPathComponent() == bundle.resourceURL },
            "UI smoke fixture files must resolve from the built SumiUITests resource bundle"
        )
        try family.verifyIntegrity()
    }

    func testFixtureResolutionRejectsPartialAndTamperedFamilies() throws {
        let bundledFamily = try SumiSmokeStoreFixture.resolveBundledFamily()

        let partialDirectory = try makeMutableFixtureCopy(of: bundledFamily, prefix: "Partial")
        try FileManager.default.removeItem(
            at: partialDirectory.appendingPathComponent("Sumi.sqlite")
        )
        XCTAssertThrowsError(
            try SumiSmokeStoreFixture.resolveFamily(resourceDirectoryURL: partialDirectory)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("partial or unexpected"))
        }

        let tamperedDirectory = try makeMutableFixtureCopy(of: bundledFamily, prefix: "Tampered")
        let tamperedStoreURL = tamperedDirectory.appendingPathComponent("Sumi.sqlite")
        var bytes = try Data(contentsOf: tamperedStoreURL)
        bytes[0] ^= 0xff
        try bytes.write(to: tamperedStoreURL)
        XCTAssertThrowsError(
            try SumiSmokeStoreFixture.resolveFamily(resourceDirectoryURL: tamperedDirectory)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("SHA-256"))
        }
    }

    func testPreparedStoresAreFreshAndIsolated() throws {
        let firstStoreURL = try prepareSmokeStoreURL()
        let secondStoreURL = try prepareSmokeStoreURL()

        XCTAssertNotEqual(firstStoreURL.deletingLastPathComponent(), secondStoreURL.deletingLastPathComponent())
        try executeSQLite(
            sql: """
            UPDATE spaces
            SET name = 'Mutated First Scratch'
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.personalSpace)';
            """,
            storeURL: firstStoreURL
        )

        XCTAssertEqual(try smokeSpaceName(in: firstStoreURL), "Mutated First Scratch")
        XCTAssertEqual(try smokeSpaceName(in: secondStoreURL), "Personal")
    }

    func testScratchSeedingLeavesBundledSourceImmutable() throws {
        let family = try SumiSmokeStoreFixture.resolveBundledFamily()
        let hashesBefore = try family.hashes()
        let storeURL = try prepareSmokeStoreURL()

        try executeSQLite(
            sql: """
            UPDATE spaces
            SET name = 'Scratch Only'
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.personalSpace)';
            """,
            storeURL: storeURL
        )

        XCTAssertEqual(try family.hashes(), hashesBefore)
        try family.verifyIntegrity()
    }

    func testPreparationIgnoresAmbientDeveloperStore() throws {
        let isolatedHome = try makeSmokeScratchDirectory(prefix: "AmbientHome")
        smokeAppSupportDirectories.append(isolatedHome)
        let decoyStoreURL = isolatedHome
            .appendingPathComponent("Library/Application Support/com.sumi.browser", isDirectory: true)
            .appendingPathComponent("Sumi.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(
            at: decoyStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let decoyBytes = Data("must-not-be-read".utf8)
        try decoyBytes.write(to: decoyStoreURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: decoyStoreURL.path
        )
        var restoredDecoyPermissions = false

        let previousHome = ProcessInfo.processInfo.environment["HOME"]
        let previousFixedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]
        setenv("HOME", isolatedHome.path, 1)
        setenv("CFFIXED_USER_HOME", isolatedHome.path, 1)
        defer {
            if !restoredDecoyPermissions {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: decoyStoreURL.path
                )
            }
            restoreEnvironmentVariable("HOME", value: previousHome)
            restoreEnvironmentVariable("CFFIXED_USER_HOME", value: previousFixedHome)
        }

        let storeURL = try prepareSmokeStoreURL()

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: decoyStoreURL.path
        )
        restoredDecoyPermissions = true
        XCTAssertEqual(try Data(contentsOf: decoyStoreURL), decoyBytes)
        XCTAssertFalse(storeURL.path.hasPrefix(isolatedHome.path))
        XCTAssertEqual(try smokeSpaceName(in: storeURL), "Personal")
    }

    func testScratchSeedUsesDeterministicSmokeIdentifiers() throws {
        let storeURL = try prepareSmokeStoreURL()
        let seededIDs = try sqliteRows(
            sql: """
            SELECT lower(hex(id)) AS value FROM spaces
            UNION ALL
            SELECT lower(hex(id)) AS value FROM folders
            UNION ALL
            SELECT lower(hex(id)) AS value FROM tabs
            ORDER BY value;
            """,
            storeURL: storeURL
        ).compactMap { $0["value"] }

        XCTAssertEqual(
            seededIDs,
            [
                SumiSmokeFixtureIDs.personalSpace,
                SumiSmokeFixtureIDs.topLevelLauncher,
                SumiSmokeFixtureIDs.regularTab,
                SumiSmokeFixtureIDs.secondaryRegularTab,
                SumiSmokeFixtureIDs.folder,
                SumiSmokeFixtureIDs.folderLauncher,
                SumiSmokeFixtureIDs.essential,
            ].sorted()
        )
        XCTAssertEqual(
            try requiredScalar(
                sql: """
                SELECT COUNT(*) AS value
                FROM (
                    SELECT position FROM spaces
                    UNION ALL
                    SELECT position FROM folders
                    UNION ALL
                    SELECT position FROM tabs
                )
                WHERE position < 0;
                """,
                storeURL: storeURL,
                description: "Unable to validate smoke fixture positions"
            ),
            "0",
            "The smoke fixture must satisfy production's nonnegative position invariant"
        )
    }

    private func makeMutableFixtureCopy(
        of family: SumiSmokeStoreFixtureFamily,
        prefix: String
    ) throws -> URL {
        let directory = try makeSmokeScratchDirectory(prefix: "SumiSmokeFixture\(prefix)")
        smokeAppSupportDirectories.append(directory)
        _ = try family.copyVerifiedFamily(to: directory)
        try FileManager.default.copyItem(
            at: family.manifestURL,
            to: directory.appendingPathComponent(SumiSmokeStoreFixture.manifestFileName)
        )
        return directory
    }

    private func smokeSpaceName(in storeURL: URL) throws -> String {
        try requiredScalar(
            sql: """
            SELECT name AS value
            FROM spaces
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.personalSpace)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Deterministic Personal smoke space is missing"
        )
    }

    private func restoreEnvironmentVariable(_ name: String, value: String?) {
        if let value {
            setenv(name, value, 1)
        } else {
            unsetenv(name)
        }
    }
}
