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

    func testIconPathPrefersLargestManifestIconBeforeActionIcon() throws {
        let directory = try temporaryExtensionDirectory()
        try writeEmptyFile("icons/16.png", in: directory)
        try writeEmptyFile("icons/48.png", in: directory)
        try writeEmptyFile("icons/128.png", in: directory)
        try writeEmptyFile("action/512.png", in: directory)

        let manifest: [String: Any] = [
            "icons": [
                "16": "icons/16.png",
                "48": "icons/48.png",
                "128": "icons/128.png",
            ],
            "action": [
                "default_icon": [
                    "512": "action/512.png",
                ],
            ],
        ]

        XCTAssertEqual(
            ExtensionUtils.iconPath(in: directory, manifest: manifest),
            directory.appendingPathComponent("icons/128.png").path
        )
    }

    func testIconPathFallsBackToActionDefaultIconWhenManifestIconsAreMissing() throws {
        let directory = try temporaryExtensionDirectory()
        try writeEmptyFile("action/32.png", in: directory)

        let manifest: [String: Any] = [
            "icons": [
                "128": "missing-128.png",
            ],
            "action": [
                "default_icon": [
                    "128": "missing-action-128.png",
                    "32": "action/32.png",
                ],
            ],
        ]

        XCTAssertEqual(
            ExtensionUtils.iconPath(in: directory, manifest: manifest),
            directory.appendingPathComponent("action/32.png").path
        )
    }

    func testIconPathAcceptsExtensionRootAbsoluteManifestIconPath() throws {
        let directory = try temporaryExtensionDirectory()
        try writeEmptyFile("assets/protonpass-icon-128.png", in: directory)

        let manifest: [String: Any] = [
            "icons": [
                "128": "/assets/protonpass-icon-128.png",
            ],
        ]

        XCTAssertEqual(
            ExtensionUtils.iconPath(in: directory, manifest: manifest),
            directory.appendingPathComponent("assets/protonpass-icon-128.png").path
        )
    }

    func testStoredExtensionIconPathFallsBackToManifestWhenPersistedIconPathIsMissing() throws {
        let directory = try temporaryExtensionDirectory()
        try writeEmptyFile("assets/protonpass-icon-128.png", in: directory)
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Proton Pass",
            "version": "1.0",
            "icons": [
                "128": "/assets/protonpass-icon-128.png",
            ],
        ]
        let record = try makeInstalledRecord(
            manifestVersion: 3,
            id: "me.proton.pass.catalyst.safari-extension",
            packagePath: directory.path,
            iconPath: nil,
            manifest: manifest
        )

        XCTAssertEqual(
            ExtensionUtils.iconPath(for: record),
            directory.appendingPathComponent("assets/protonpass-icon-128.png").path
        )
    }

    func testExtensionOwnedURLIconPathUsesInstalledExtensionID() throws {
        let directory = try temporaryExtensionDirectory()
        try writeEmptyFile("icons/128.png", in: directory)
        let iconPath = directory.appendingPathComponent("icons/128.png").path
        let record = try makeInstalledRecord(
            manifestVersion: 3,
            id: "extension-id",
            iconPath: iconPath
        )

        XCTAssertEqual(
            ExtensionUtils.iconPath(
                forExtensionOwnedURL: URL(string: "safari-web-extension://extension-id/onboarding.html"),
                installedExtensions: [record]
            ),
            iconPath
        )
        XCTAssertNil(
            ExtensionUtils.iconPath(
                forExtensionOwnedURL: URL(string: "safari-web-extension://other-extension/onboarding.html"),
                installedExtensions: [record]
            )
        )
    }

    func testExtensionOwnedURLIconPathDecodesSumiScopedWebKitHost() throws {
        let directory = try temporaryExtensionDirectory()
        try writeEmptyFile("icons/128.png", in: directory)
        let iconPath = directory.appendingPathComponent("icons/128.png").path
        let record = try makeInstalledRecord(
            manifestVersion: 3,
            id: "com.1password.safari.extension",
            iconPath: iconPath
        )
        let scopedIdentifier = "3135281a-0e69-48bd-b2c6-5b4171e9400c:\(record.id)"
        let host = "ext-" + scopedIdentifier.utf8.map {
            String(format: "%02x", $0)
        }.joined()

        XCTAssertEqual(
            ExtensionUtils.iconPath(
                forExtensionOwnedURL: URL(string: "webkit-extension://\(host)/app/app.html#/page/welcome"),
                installedExtensions: [record]
            ),
            iconPath
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

    @available(macOS 15.5, *)
    @MainActor
    func testInstallationMetadataStoreRefreshesPersistedMetadata() throws {
        let directory = try temporaryExtensionDirectory()
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Store-owned Metadata",
            "version": "2.0",
            "background": [
                "page": "background.html",
                "persistent": true,
            ],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
            ]],
        ]
        let staleRecord = try makeInstalledRecord(
            manifestVersion: 2,
            id: "metadata-store-refresh",
            packagePath: directory.path,
            manifest: manifest
        )
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        container.mainContext.insert(ExtensionEntity(record: staleRecord))
        try container.mainContext.save()

        let store = ExtensionInstallationMetadataStore(context: container.mainContext)
        var traces: [String] = []
        let result = store.loadInstalledExtensionMetadata { traces.append($0) }

        XCTAssertTrue(result.didFetchPersistedMetadata)
        XCTAssertEqual(result.records.map(\.id), [staleRecord.id])
        XCTAssertEqual(result.enabledEntities.map(\.id), [staleRecord.id])
        XCTAssertEqual(result.records.first?.backgroundModel, .persistentPage)
        XCTAssertTrue(result.records.first?.hasBackground == true)
        XCTAssertTrue(
            traces.contains { $0.contains("Refreshed extension metadata") }
        )

        let entity = try XCTUnwrap(try store.extensionEntity(for: staleRecord.id))
        XCTAssertEqual(entity.backgroundModelRawValue, "persistent_page")
        XCTAssertTrue(entity.hasBackground)
    }

    @available(macOS 15.5, *)
    @MainActor
    func testLoadInstalledMetadataFetchFailurePreservesPinnedToolbarIDs() throws {
        let profile = Profile(name: "Pinned Toolbar Profile")
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration()
        )
        let profileKey = ExtensionManager.pinnedToolbarProfileKey(for: profile.id)
        manager.pinnedToolbarExtensionIDsByProfile[profileKey] = ["missing-extension"]
        manager.pinnedToolbarExtensionIDs = ["missing-extension"]

        _ = manager.applyInstalledExtensionMetadataLoadResult(
            .init(
                didFetchPersistedMetadata: false,
                records: [],
                enabledEntities: []
            )
        )

        XCTAssertTrue(manager.installedExtensions.isEmpty)
        XCTAssertEqual(manager.pinnedToolbarExtensionIDs, ["missing-extension"])
        XCTAssertEqual(
            manager.pinnedToolbarExtensionIDsByProfile[profileKey],
            ["missing-extension"]
        )
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

    private func makeInstalledRecord(
        manifestVersion: Int,
        id: String = UUID().uuidString,
        packagePath: String? = nil,
        iconPath: String? = nil,
        manifest overrideManifest: [String: Any]? = nil
    ) throws -> InstalledExtensionRecord {
        let directory: URL
        if let packagePath {
            directory = URL(fileURLWithPath: packagePath, isDirectory: true)
        } else {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            addTeardownBlock {
                try? FileManager.default.removeItem(at: directory)
            }
        }

        let manifest: [String: Any] = overrideManifest ?? [
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
            id: id,
            name: "Test Extension",
            version: "1.0",
            manifestVersion: manifestVersion,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: directory.path,
            iconPath: iconPath,
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

    private func temporaryExtensionDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func writeEmptyFile(_ relativePath: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url, options: [.atomic])
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
