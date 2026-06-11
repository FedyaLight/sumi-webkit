import SwiftData
import XCTest

@testable import Sumi

final class WebExtensionManifestValidationTests: XCTestCase {
    func testUnpackedDirectoryPolicyRejectsManifestVersionTwo() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 2,
            "name": "Legacy Extension",
            "version": "1.0",
        ])

        XCTAssertThrowsError(
            try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: .unpackedDirectory
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("only manifest version 3 is accepted"))
        }
    }

    func testSafariPolicyAcceptsManifestVersionTwo() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 2,
            "name": "Bitwarden",
            "version": "2024.1.0",
        ])

        let manifest = try ExtensionUtils.validateManifest(
            at: manifestURL,
            policy: .safariWebExtension
        )
        XCTAssertEqual(manifest["manifest_version"] as? Int, 2)
    }

    func testSafariPolicyAcceptsManifestVersionThree() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 3,
            "name": "Raindrop",
            "version": "1.0",
        ])

        let manifest = try ExtensionUtils.validateManifest(
            at: manifestURL,
            policy: .safariWebExtension
        )
        XCTAssertEqual(manifest["manifest_version"] as? Int, 3)
    }

    func testSafariPolicyRejectsUnsupportedManifestVersion() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 1,
            "name": "Ancient Extension",
            "version": "1.0",
        ])

        XCTAssertThrowsError(
            try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: .safariWebExtension
            )
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("manifest_version 1"))
            XCTAssertTrue(
                message.contains(
                    "Safari Web Extensions support manifest_version 2 and 3"
                )
            )
        }
    }

    func testManifestValidationPolicyForSourceKind() {
        XCTAssertEqual(
            WebExtensionManifestValidationPolicy.forSourceKind(.safariAppExtension),
            .safariWebExtension
        )
        XCTAssertEqual(
            WebExtensionManifestValidationPolicy.forSourceKind(.directory),
            .unpackedDirectory
        )
    }

    func testBackgroundModelDetectsManifestVersionTwoPersistentPage() {
        XCTAssertEqual(
            ExtensionUtils.backgroundModel(from: [
                "background": [
                    "page": "background.html",
                    "persistent": true,
                ],
            ]),
            .persistentPage
        )
    }

    func testBackgroundModelDetectsManifestVersionTwoPersistentScripts() {
        XCTAssertEqual(
            ExtensionUtils.backgroundModel(from: [
                "background": [
                    "scripts": ["background.js"],
                    "persistent": true,
                ],
            ]),
            .persistentPage
        )
    }

    func testBackgroundModelDetectsManifestVersionThreeServiceWorker() {
        XCTAssertEqual(
            ExtensionUtils.backgroundModel(from: [
                "background": [
                    "service_worker": "worker.js",
                ],
            ]),
            .serviceWorker
        )
    }

    func testBackgroundModelReturnsNoneWhenManifestHasNoBackground() {
        XCTAssertEqual(
            ExtensionUtils.backgroundModel(from: [:]),
            .none
        )
    }

    @available(macOS 15.5, *)
    @MainActor
    func testLoadInstalledMetadataRefreshesLegacyMV2BackgroundRecord() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "MV2 Background Page",
            "version": "1.0",
            "background": [
                "page": "background.html",
                "persistent": true,
            ],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
            ]],
        ]
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try data.write(to: manifestURL, options: [.atomic])

        let staleRecord = InstalledExtensionRecord(
            id: "mv2-background-page",
            name: "MV2 Background Page",
            version: "1.0",
            manifestVersion: 2,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: directory.path,
            iconPath: nil,
            sourceKind: .safariAppExtension,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "stale",
            manifestRootFingerprint: "stale",
            sourceBundlePath: "/Applications/Test.app/Contents/PlugIns/test.appex",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: false,
            hasOptionsPage: false,
            hasContentScripts: true,
            hasExtensionPages: false,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: ["<all_urls>"],
                broadScope: true,
                hasContentScripts: true,
                hasAction: false,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: manifest
        )

        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        container.mainContext.insert(ExtensionEntity(record: staleRecord))
        try container.mainContext.save()

        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: Profile(name: "Metadata Refresh Profile"),
            browserConfiguration: BrowserConfiguration()
        )

        _ = manager.loadInstalledExtensionMetadata()

        let refreshed = try XCTUnwrap(
            manager.installedExtensions.first { $0.id == staleRecord.id }
        )
        XCTAssertEqual(refreshed.backgroundModel, .persistentPage)
        XCTAssertTrue(refreshed.hasBackground)

        let entity = try XCTUnwrap(try manager.extensionEntity(for: staleRecord.id))
        XCTAssertEqual(entity.backgroundModelRawValue, "persistent_page")
        XCTAssertTrue(entity.hasBackground)
    }

    func testInstalledExtensionMetadataRecordsManifestVersionTwo() throws {
        let record = try makeInstalledRecord(manifestVersion: 2)
        XCTAssertEqual(record.manifestVersion, 2)
    }

    func testManifestVersionTwoShowsLegacyManifestWarning() throws {
        let record = try makeInstalledRecord(manifestVersion: 2)
        XCTAssertTrue(record.legacyManifestMayUseMoreEnergy)
    }

    func testManifestVersionThreeDoesNotShowLegacyManifestWarning() throws {
        let record = try makeInstalledRecord(manifestVersion: 3)
        XCTAssertFalse(record.legacyManifestMayUseMoreEnergy)
    }

    @available(macOS 15.5, *)
    func testSafariAppexManifestVersionTwoPassesValidatorBeforeWebKitLoad() throws {
        let scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }

        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "MV2Safari",
                bundleIdentifier: "com.example.mv2",
                displayName: "MV2 Safari Extension",
                manifestVersion: 2
            )
        )
        let resourcesURL = try SafariAppExtensionResources.resourcesRoot(in: appexURL)
        let manifestURL = resourcesURL.appendingPathComponent("manifest.json")

        XCTAssertNoThrow(
            try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: .safariWebExtension
            )
        )
    }

    private func makeInstalledRecord(manifestVersion: Int) throws -> InstalledExtensionRecord {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let manifest: [String: Any] = [
            "manifest_version": manifestVersion,
            "name": "Test Extension",
            "version": "1.0",
        ]
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try data.write(to: manifestURL, options: [.atomic])

        return InstalledExtensionRecord(
            id: UUID().uuidString,
            name: "Test Extension",
            version: "1.0",
            manifestVersion: manifestVersion,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: directory.path,
            iconPath: nil,
            sourceKind: .safariAppExtension,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "fingerprint",
            manifestRootFingerprint: "manifest-fingerprint",
            sourceBundlePath: "/tmp/example.appex",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: false,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: false,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: false,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: manifest
        )
    }

    private func writeManifest(_ manifest: [String: Any]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("manifest.json")
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: [.atomic])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return url
    }
}
