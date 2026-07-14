import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionInstallationSecurityTests: XCTestCase {
    private var scratchDirectory: URL!

    override func setUpWithError() throws {
        scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let scratchDirectory {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        scratchDirectory = nil
    }

    func testExtensionIDDirectoryRequiresSingleSafePathComponent() throws {
        let root = scratchDirectory.appendingPathComponent("Extensions", isDirectory: true)
        let validIDs = [
            "com.example.extension",
            "addon@example.com",
            "{01234567-89ab-cdef-0123-456789abcdef}",
            "chrome_ext-1",
        ]

        for extensionId in validIDs {
            let directory = try ExtensionPathSafety.extensionDirectory(
                for: extensionId,
                under: root
            )

            XCTAssertEqual(
                directory.deletingLastPathComponent().standardizedFileURL.path,
                root.standardizedFileURL.path
            )
            XCTAssertEqual(directory.lastPathComponent, extensionId)
        }

        for extensionId in [
            "",
            ".",
            "..",
            "../escape",
            "nested/id",
            "nested\\id",
            "bad:id",
            " id",
            "id ",
            "line\nbreak",
        ] {
            XCTAssertThrowsError(
                try ExtensionPathSafety.extensionDirectory(
                    for: extensionId,
                    under: root
                ),
                "Expected unsafe extension id to be rejected: \(extensionId)"
            )
        }
    }

    func testInstallRejectsMaliciousGeckoIDBeforeMovingOutsideExtensionsRoot()
        async throws {
        let container = try makeTestContainer()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: Profile(name: "Malicious ID Profile")
        )
        let escapedLeaf = "sumi-security-\(UUID().uuidString)"
        let maliciousID = "../\(escapedLeaf)"
        let source = try makeUnpackedExtension(
            name: "MaliciousGeckoID",
            geckoId: maliciousID
        )
        let escapedDestination = ExtensionPathSafety.extensionsDirectory()
            .appendingPathComponent(maliciousID, isDirectory: true)
            .standardizedFileURL
        addTeardownBlock {
            try? FileManager.default.removeItem(at: escapedDestination)
        }

        do {
            _ = try await manager.extensionInstaller.install(
                from: source,
                enableOnInstall: false
            )
            XCTFail("Installation should reject unsafe gecko IDs")
        } catch let error as ExtensionError {
            XCTAssertTrue(
                error.localizedDescription.contains("safe path component")
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: escapedDestination.path))
        XCTAssertFalse(manager.installedExtensionCollection.records.contains { $0.id == maliciousID })
    }

    func testInstallKeepsLegitimateGeckoIDInsideExtensionsRoot() async throws {
        let container = try makeTestContainer()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: Profile(name: "Legitimate ID Profile")
        )
        let extensionId = "addon-\(UUID().uuidString)@example.com"
        let source = try makeUnpackedExtension(
            name: "LegitimateGeckoID",
            geckoId: extensionId
        )

        let installed = try await manager.extensionInstaller.install(
            from: source,
            enableOnInstall: false
        )

        XCTAssertEqual(installed.id, extensionId)
        let installedPackage = URL(
            fileURLWithPath: installed.packagePath,
            isDirectory: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: installedPackage)
        }
        XCTAssertEqual(
            ExtensionPackageLayout(
                extensionsRoot: ExtensionPathSafety.extensionsDirectory()
            ).packageRootKind(installedPackage),
            .managedGeneration
        )
    }

    func testSafariAppexInstallPrefersBundleIdentifierOverManifestGeckoID() async throws {
        let container = try makeTestContainer()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: Profile(name: "Safari Bundle ID Profile")
        )
        let bundleIdentifier = "com.example.safari.\(UUID().uuidString.lowercased())"
        let geckoId = "gecko-\(UUID().uuidString.lowercased())@example.com"
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Safari Bundle ID",
            "version": "1.0",
            "browser_specific_settings": [
                "gecko": [
                    "id": geckoId,
                ],
            ],
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "SafariBundleID",
                bundleIdentifier: bundleIdentifier,
                displayName: "Safari Bundle ID",
                resourceFiles: [
                    .init(relativePath: "manifest.json", data: manifestData),
                ]
            )
        )

        let installed = try await manager.extensionInstaller.install(
            from: appexURL,
            enableOnInstall: false
        )

        XCTAssertEqual(installed.id, bundleIdentifier)
        XCTAssertNotEqual(installed.id, geckoId)
    }

    func testOptionalNativeMessagingIsNotPregrantedOnInstall() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Optional Native Messaging Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let installed = try await manager.extensionInstaller.install(
            from: try makeUnpackedExtension(
                name: "OptionalNativeMessaging",
                geckoId: "optional-native-\(UUID().uuidString)@example.com",
                optionalPermissions: ["nativeMessaging"]
            ),
            enableOnInstall: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: installed.packagePath, isDirectory: true)
            )
        }

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )

        XCTAssertFalse(
            WebExtensionRuntimeCompatibilityPolicy
                .declaresNativeMessaging(installed.manifest)
        )
        XCTAssertFalse(
            ExtensionPermissionStatusResolver.isGranted(
                context.permissionStatus(for: .nativeMessaging)
            )
        )
    }

    func testOptionalPermissionsAreNotPregrantedUnderTests() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Optional Permissions Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let installed = try await manager.extensionInstaller.install(
            from: try makeUnpackedExtension(
                name: "OptionalTabs",
                geckoId: "optional-tabs-\(UUID().uuidString)@example.com",
                optionalPermissions: ["tabs"]
            ),
            enableOnInstall: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: installed.packagePath, isDirectory: true)
            )
        }

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let storagePermission = WKWebExtension.Permission(rawValue: "storage")
        let tabsPermission = WKWebExtension.Permission(rawValue: "tabs")

        XCTAssertEqual(context.permissionStatus(for: storagePermission), .grantedExplicitly)
        XCTAssertFalse(
            ExtensionPermissionStatusResolver.isGranted(
                context.permissionStatus(for: tabsPermission)
            )
        )
    }

    func testRequiredNativeMessagingStillPregrantsOnInstall() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Required Native Messaging Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let installed = try await manager.extensionInstaller.install(
            from: try makeUnpackedExtension(
                name: "RequiredNativeMessaging",
                geckoId: "required-native-\(UUID().uuidString)@example.com",
                permissions: ["nativeMessaging"]
            ),
            enableOnInstall: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: installed.packagePath, isDirectory: true)
            )
        }

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )

        XCTAssertTrue(
            WebExtensionRuntimeCompatibilityPolicy
                .declaresNativeMessaging(installed.manifest)
        )
        XCTAssertEqual(
            context.permissionStatus(for: .nativeMessaging),
            .grantedExplicitly
        )
    }

    func testFailedReinstallRestoresPackageAndPersistedRecord() async throws {
        let container = try makeTestContainer()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: Profile(name: "Rollback Profile")
        )
        let extensionID = "rollback-\(UUID().uuidString)@example.com"
        let originalSource = try makeUnpackedExtension(
            name: "RollbackOriginal",
            geckoId: extensionID
        )
        let originalMarker = originalSource.appendingPathComponent("marker.txt")
        try Data("original".utf8).write(to: originalMarker)

        let original = try await manager.extensionInstaller.install(
            from: originalSource,
            enableOnInstall: false
        )
        let installedRoot = URL(
            fileURLWithPath: original.packagePath,
            isDirectory: true
        )
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: installedRoot.path) {
                try FileManager.default.removeItem(at: installedRoot)
            }
        }

        let replacementSource = try makeUnpackedExtension(
            name: "RollbackReplacement",
            geckoId: extensionID
        )
        try Data("replacement".utf8).write(
            to: replacementSource.appendingPathComponent("marker.txt")
        )
        manager.testHooks.beforePersistInstalledRecord = { _ in
            throw ExtensionError.installationFailed("injected persistence failure")
        }
        defer { manager.testHooks.beforePersistInstalledRecord = nil }

        do {
            _ = try await manager.extensionInstaller.install(
                from: replacementSource,
                enableOnInstall: false
            )
            XCTFail("Reinstall should fail at the persistence boundary")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("injected persistence failure"))
        }

        let restoredMarker = try Data(
            contentsOf: installedRoot.appendingPathComponent("marker.txt")
        )
        XCTAssertEqual(restoredMarker, Data("original".utf8))
        XCTAssertEqual(
            manager.installedExtensionCollection.records.first(where: { $0.id == extensionID })?.name,
            original.name
        )
        let persisted = try XCTUnwrap(
            manager.installationMetadataStore.extensionEntity(for: extensionID)
        )
        XCTAssertEqual(persisted.name, original.name)
    }

    func testEnableWithoutRuntimeProfileRollsBackEnabledState() async throws {
        let container = try makeTestContainer()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: nil
        )
        let installed = try await manager.extensionInstaller.install(
            from: try makeUnpackedExtension(
                name: "EnableRollback",
                geckoId: "enable-rollback-\(UUID().uuidString)@example.com"
            ),
            enableOnInstall: false
        )
        let installedRoot = URL(
            fileURLWithPath: installed.packagePath,
            isDirectory: true
        )
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: installedRoot.path) {
                try FileManager.default.removeItem(at: installedRoot)
            }
        }

        do {
            _ = try await manager.installedExtensionLifecycle.enable(installed.id)
            XCTFail("Enable should fail without a runtime profile")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("profile is unavailable"))
        }

        let entity = try XCTUnwrap(
            manager.installationMetadataStore.extensionEntity(for: installed.id)
        )
        XCTAssertFalse(entity.isEnabled)
        XCTAssertFalse(
            try XCTUnwrap(
                manager.installedExtensionCollection.records.first(where: { $0.id == installed.id })
            ).isEnabled
        )
    }

    func testRuntimeCompatibilityPolicyClassifiesWebKitTarget() {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "WebKit Runtime Policy",
            "version": "1.0",
            "permissions": ["scripting", "nativeMessaging"],
            "browser_specific_settings": [
                "safari": [:],
            ],
        ]

        XCTAssertTrue(
            WebExtensionRuntimeCompatibilityPolicy.declaresNativeMessaging(
                manifest
            )
        )
        // WebKit's native browser.scripting implementation is verified by
        // SafariExtensionScriptingRuntimeTests, so Safari-target manifests
        // must not mark it unsupported (Proton Pass bootstraps its autofill
        // client through it). Legacy MV2 injection APIs stay unsupported.
        let unsupportedAPIs = WebExtensionRuntimeCompatibilityPolicy
            .unsupportedAPIs(for: manifest)
        XCTAssertFalse(unsupportedAPIs.contains("browser.scripting.executeScript"))
        XCTAssertFalse(unsupportedAPIs.contains("browser.scripting.insertCSS"))
        XCTAssertTrue(unsupportedAPIs.contains("browser.tabs.executeScript"))
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeUnpackedExtension(
        name: String,
        geckoId: String,
        permissions: [String] = ["storage"],
        optionalPermissions: [String] = []
    ) throws -> URL {
        let directory = scratchDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "permissions": permissions,
            "browser_specific_settings": [
                "gecko": [
                    "id": geckoId,
                ],
            ],
        ]
        if optionalPermissions.isEmpty == false {
            manifest["optional_permissions"] = optionalPermissions
        }

        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(
                to: directory.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )

        return directory
    }
}
