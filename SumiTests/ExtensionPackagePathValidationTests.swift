import SwiftData
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionPackagePathValidationTests: XCTestCase {
    func testCatalogDropsDirectoryRecordOutsideBrowserStorage() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent(
            "OutsidePackage",
            isDirectory: true
        )
        try makeManifest(at: outside)
        let record = makeRecord(packagePath: outside.path)
        try fixture.store.persist(record: record)

        let loaded = fixture.store.loadInstalledExtensionMetadata { _ in }

        XCTAssertTrue(loaded.records.isEmpty)
        XCTAssertTrue(loaded.enabledEntities.isEmpty)
        XCTAssertNil(try fixture.store.extensionEntity(for: record.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testCatalogDropsSymlinkEscapeWithoutTouchingTarget() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent(
            "OutsidePackage",
            isDirectory: true
        )
        try makeManifest(at: outside)
        let escaped = fixture.extensions.appendingPathComponent(
            "escaped@example.com",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: escaped,
            withDestinationURL: outside
        )
        let record = makeRecord(packagePath: escaped.path)
        try fixture.store.persist(record: record)

        let loaded = fixture.store.loadInstalledExtensionMetadata { _ in }

        XCTAssertTrue(loaded.records.isEmpty)
        XCTAssertNil(try fixture.store.extensionEntity(for: record.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    private func makeFixture() throws -> (
        root: URL,
        extensions: URL,
        container: ModelContainer,
        store: ExtensionInstallationMetadataStore
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let extensions = root.appendingPathComponent(
            "Extensions",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: extensions,
            withIntermediateDirectories: true
        )
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return (
            root,
            extensions,
            container,
            ExtensionInstallationMetadataStore(
                context: container.mainContext,
                extensionsDirectory: extensions
            )
        )
    }

    private func makeManifest(at root: URL) throws {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Outside",
            "version": "1.0",
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appendingPathComponent("manifest.json")
        )
    }

    private func makeRecord(packagePath: String) -> InstalledExtension {
        InstalledExtension(
            id: "outside.example",
            name: "Outside",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(timeIntervalSince1970: 1),
            lastUpdateDate: Date(timeIntervalSince1970: 2),
            packagePath: packagePath,
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "source",
            manifestRootFingerprint: "manifest",
            sourceBundlePath: packagePath,
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
                "name": "Outside",
                "version": "1.0",
            ]
        )
    }
}
