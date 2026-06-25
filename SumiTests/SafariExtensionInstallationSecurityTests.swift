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
            let directory = try ExtensionUtils.extensionDirectory(
                forExtensionID: extensionId,
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
                try ExtensionUtils.extensionDirectory(
                    forExtensionID: extensionId,
                    under: root
                ),
                "Expected unsafe extension id to be rejected: \(extensionId)"
            )
        }
    }

    func testInstallRejectsMaliciousGeckoIDBeforeMovingOutsideExtensionsRoot()
        async throws
    {
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
        let escapedDestination = ExtensionUtils.extensionsDirectory()
            .appendingPathComponent(maliciousID, isDirectory: true)
            .standardizedFileURL
        addTeardownBlock {
            try? FileManager.default.removeItem(at: escapedDestination)
        }

        do {
            _ = try await manager.performInstallation(
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
        XCTAssertFalse(manager.installedExtensions.contains { $0.id == maliciousID })
    }

    func testInstallKeepsLegitimateGeckoIDInsideExtensionsRoot() async throws {
        let container = try makeTestContainer()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: Profile(name: "Legitimate ID Profile")
        )
        let extensionId = "addon-\(UUID().uuidString)@example.com"
        let expectedDirectory = try ExtensionUtils.extensionDirectory(
            forExtensionID: extensionId,
            under: ExtensionUtils.extensionsDirectory()
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: expectedDirectory)
        }
        let source = try makeUnpackedExtension(
            name: "LegitimateGeckoID",
            geckoId: extensionId
        )

        let installed = try await manager.performInstallation(
            from: source,
            enableOnInstall: false
        )

        XCTAssertEqual(installed.id, extensionId)
        XCTAssertEqual(
            URL(fileURLWithPath: installed.packagePath, isDirectory: true)
                .standardizedFileURL.path,
            expectedDirectory.standardizedFileURL.path
        )
    }

    func testOptionalNativeMessagingIsNotPregrantedOnInstall() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Optional Native Messaging Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let installed = try await manager.performInstallation(
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

        XCTAssertFalse(ExtensionManager.manifestDeclaresNativeMessaging(installed.manifest))
        XCTAssertFalse(
            manager.isGrantedPermissionStatus(
                context.permissionStatus(for: .nativeMessaging)
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
        let installed = try await manager.performInstallation(
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

        XCTAssertTrue(ExtensionManager.manifestDeclaresNativeMessaging(installed.manifest))
        XCTAssertEqual(
            context.permissionStatus(for: .nativeMessaging),
            .grantedExplicitly
        )
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
