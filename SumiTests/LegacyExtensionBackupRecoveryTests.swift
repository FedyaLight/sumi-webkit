import SwiftData
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class LegacyExtensionBackupRecoveryTests: XCTestCase {
    func testMissingDurableRootRestoresOnlyMatchingBackup() throws {
        let fixture = try makeFixture()
        let matching = try fixture.makeBackup(manifestName: "Durable")
        let stale = try fixture.makeBackup(manifestName: "Stale")

        let result = fixture.recovery.recover(
            fixture.package(fingerprint: matching.fingerprint)
        )

        XCTAssertEqual(result.validationDisposition, .proceed)
        XCTAssertTrue(result.quarantinedURLs.isEmpty)
        XCTAssertEqual(
            try legacyRecoveryTestManifestName(at: fixture.durableRoot),
            "Durable"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: matching.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale.url.path))
    }

    func testMismatchedDurableRootIsQuarantinedBeforeBackupRestore() throws {
        let fixture = try makeFixture()
        try writeLegacyRecoveryTestManifest(
            name: "Interrupted",
            to: fixture.durableRoot
        )
        let matching = try fixture.makeBackup(manifestName: "Durable")

        let result = fixture.recovery.recover(
            fixture.package(fingerprint: matching.fingerprint)
        )

        XCTAssertEqual(result.validationDisposition, .proceed)
        XCTAssertEqual(result.quarantinedURLs.count, 1)
        XCTAssertEqual(
            try legacyRecoveryTestManifestName(at: fixture.durableRoot),
            "Durable"
        )
        XCTAssertEqual(
            try legacyRecoveryTestManifestName(
                at: try XCTUnwrap(result.quarantinedURLs.first)
            ),
            "Interrupted"
        )
    }

    func testMatchingDurableRootQuarantinesAllStaleBackups() throws {
        let fixture = try makeFixture()
        let durableFingerprint = try writeLegacyRecoveryTestManifest(
            name: "Durable",
            to: fixture.durableRoot
        )
        _ = try fixture.makeBackup(manifestName: "Durable")
        _ = try fixture.makeBackup(manifestName: "Stale")

        let result = fixture.recovery.recover(
            fixture.package(fingerprint: durableFingerprint)
        )

        XCTAssertEqual(result.validationDisposition, .proceed)
        XCTAssertEqual(result.quarantinedURLs.count, 2)
        XCTAssertEqual(
            try legacyRecoveryTestManifestName(at: fixture.durableRoot),
            "Durable"
        )
    }

    func testAmbiguousMatchingBackupsPreserveFilesystemAndDeferValidation()
        throws {
        let fixture = try makeFixture()
        let first = try fixture.makeBackup(manifestName: "Durable")
        let second = try fixture.makeBackup(manifestName: "Durable")

        let result = fixture.recovery.recover(
            fixture.package(fingerprint: first.fingerprint)
        )

        XCTAssertEqual(result.validationDisposition, .deferUntilNextLaunch)
        XCTAssertTrue(result.quarantinedURLs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.durableRoot.path)
        )
    }

    func testNoMatchingBackupDoesNotReplaceMismatchedCurrentRoot() throws {
        let fixture = try makeFixture()
        try writeLegacyRecoveryTestManifest(
            name: "Interrupted",
            to: fixture.durableRoot
        )
        let durableFingerprint = ExtensionPackageFingerprint.string(
            "missing durable manifest"
        )
        let stale = try fixture.makeBackup(manifestName: "Stale")

        let result = fixture.recovery.recover(
            fixture.package(fingerprint: durableFingerprint)
        )

        XCTAssertEqual(result.validationDisposition, .deferUntilNextLaunch)
        XCTAssertTrue(result.quarantinedURLs.isEmpty)
        XCTAssertEqual(
            try legacyRecoveryTestManifestName(at: fixture.durableRoot),
            "Interrupted"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale.url.path))
    }

    func testSymlinkBackupIsIgnoredWithoutTouchingItsTarget() throws {
        let fixture = try makeFixture()
        let outside = fixture.root.appendingPathComponent(
            "Outside",
            isDirectory: true
        )
        let durableFingerprint = try writeLegacyRecoveryTestManifest(
            name: "Durable",
            to: outside
        )
        let alias = fixture.backupURL()
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: outside
        )

        let result = fixture.recovery.recover(
            fixture.package(fingerprint: durableFingerprint)
        )

        XCTAssertEqual(result.validationDisposition, .deferUntilNextLaunch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: alias.path))
        XCTAssertEqual(
            try legacyRecoveryTestManifestName(at: outside),
            "Durable"
        )
    }

    func testMetadataLoadRecoversBeforeRejectingMissingLegacyRoot() throws {
        let fixture = try makeFixture()
        let matching = try fixture.makeBackup(manifestName: "Durable")
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = ExtensionInstallationMetadataStore(
            context: container.mainContext,
            extensionsDirectory: fixture.extensionsRoot
        )
        try store.persist(
            record: fixture.record(fingerprint: matching.fingerprint)
        )

        let loaded = store.loadInstalledExtensionMetadata { _ in }

        XCTAssertEqual(loaded.records.map(\.id), [fixture.extensionID])
        XCTAssertEqual(
            try legacyRecoveryTestManifestName(at: fixture.durableRoot),
            "Durable"
        )
        XCTAssertNotNil(try store.extensionEntity(for: fixture.extensionID))
    }

    func testAmbiguousRecoveryPreservesDurableMetadataWithoutPublication()
        throws {
        let fixture = try makeFixture()
        let first = try fixture.makeBackup(manifestName: "Durable")
        _ = try fixture.makeBackup(manifestName: "Durable")
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = ExtensionInstallationMetadataStore(
            context: container.mainContext,
            extensionsDirectory: fixture.extensionsRoot
        )
        try store.persist(
            record: fixture.record(fingerprint: first.fingerprint)
        )

        let loaded = store.loadInstalledExtensionMetadata { _ in }

        XCTAssertTrue(loaded.records.isEmpty)
        XCTAssertNotNil(try store.extensionEntity(for: fixture.extensionID))
    }

    func testNoMatchPreservesMismatchedRootAndMetadataWithoutPublication()
        throws {
        let fixture = try makeFixture()
        try writeLegacyRecoveryTestManifest(
            name: "Interrupted",
            to: fixture.durableRoot
        )
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = ExtensionInstallationMetadataStore(
            context: container.mainContext,
            extensionsDirectory: fixture.extensionsRoot
        )
        let durableFingerprint = ExtensionPackageFingerprint.string(
            "missing durable manifest"
        )
        try store.persist(
            record: fixture.record(fingerprint: durableFingerprint)
        )

        let loaded = store.loadInstalledExtensionMetadata { _ in }

        XCTAssertTrue(loaded.records.isEmpty)
        XCTAssertNotNil(try store.extensionEntity(for: fixture.extensionID))
        XCTAssertEqual(
            try legacyRecoveryTestManifestName(at: fixture.durableRoot),
            "Interrupted"
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let extensionsRoot = root.appendingPathComponent(
            "Extensions",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: extensionsRoot,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                XCTFail("Failed to remove fixture: \(error)")
            }
        }
        return Fixture(root: root, extensionsRoot: extensionsRoot)
    }

    private struct Fixture {
        let root: URL
        let extensionsRoot: URL
        let extensionID = "legacy@example.com"

        var durableRoot: URL {
            extensionsRoot.appendingPathComponent(
                extensionID,
                isDirectory: true
            )
        }

        var recovery: LegacyExtensionBackupRecovery {
            LegacyExtensionBackupRecovery(
                layout: ExtensionPackageLayout(extensionsRoot: extensionsRoot)
            )
        }

        func backupURL() -> URL {
            extensionsRoot.appendingPathComponent(
                "backup_\(extensionID)_\(UUID().uuidString)",
                isDirectory: true
            )
        }

        func makeBackup(manifestName: String) throws
            -> (url: URL, fingerprint: String) {
            let url = backupURL()
            let fingerprint = try writeLegacyRecoveryTestManifest(
                name: manifestName,
                to: url
            )
            return (url, fingerprint)
        }

        func package(fingerprint: String)
            -> LegacyExtensionBackupRecovery.DurablePackage {
            .init(
                extensionID: extensionID,
                packagePath: durableRoot.path,
                manifestRootFingerprint: fingerprint,
                sourceKind: .directory
            )
        }

        func record(fingerprint: String) -> InstalledExtension {
            InstalledExtension(
                id: extensionID,
                name: "Durable",
                version: "1.0",
                manifestVersion: 3,
                description: nil,
                isEnabled: true,
                installDate: Date(timeIntervalSince1970: 1),
                lastUpdateDate: Date(timeIntervalSince1970: 2),
                packagePath: durableRoot.path,
                iconPath: nil,
                sourceKind: .directory,
                backgroundModel: .none,
                incognitoMode: .spanning,
                sourcePathFingerprint: "source",
                manifestRootFingerprint: fingerprint,
                sourceBundlePath: durableRoot.path,
                optionsPagePath: nil,
                defaultPopupPath: nil,
                hasBackground: false,
                hasAction: false,
                hasOptionsPage: false,
                hasContentScripts: false,
                hasExtensionPages: false,
                activationSummary: .init(
                    matchPatternStrings: [],
                    broadScope: false,
                    hasContentScripts: false,
                    hasAction: false,
                    hasOptionsPage: false,
                    hasExtensionPages: false
                ),
                manifest: [
                    "manifest_version": 3,
                    "name": "Durable",
                    "version": "1.0",
                ]
            )
        }
    }
}

private func legacyRecoveryTestManifestName(at packageRoot: URL) throws
    -> String {
    let data = try Data(
        contentsOf: packageRoot.appendingPathComponent("manifest.json")
    )
    let manifest = try XCTUnwrap(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    return try XCTUnwrap(manifest["name"] as? String)
}

@discardableResult
private func writeLegacyRecoveryTestManifest(
    name: String,
    to packageRoot: URL
) throws -> String {
    try FileManager.default.createDirectory(
        at: packageRoot,
        withIntermediateDirectories: true
    )
    let data = try JSONSerialization.data(
        withJSONObject: [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
        ],
        options: [.sortedKeys]
    )
    try data.write(to: packageRoot.appendingPathComponent("manifest.json"))
    return ExtensionPackageFingerprint.data(data)
}
