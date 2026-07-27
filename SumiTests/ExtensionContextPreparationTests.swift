import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextPreparationTests: XCTestCase {
    func testStoredDecisionOverridesManifestGrantDuringPreparation()
        async throws {
        _ = ExtensionManager.registerSafariWebExtensionURLScheme
        let database = try SumiDatabase.inMemory()
        let profileID = UUID()
        let extensionID = "prepared-extension"
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: profileID
        )
        let decisions = ExtensionPermissionDecisionStore(
            database: database,
            profileRuntime: profileRuntime
        )
        let tabsPermission = WKWebExtension.Permission(rawValue: "tabs")
        decisions.persistExtensionPermissionDecision(
            extensionId: extensionID,
            profileId: profileID,
            targetKind: .permission,
            target: tabsPermission.rawValue,
            state: .denied,
            expiresAt: nil
        )
        var policyPersistenceCount = 0
        let preparation = ExtensionContextPreparation(
            siteAccessPolicyStore: .init(database: database),
            installedExtensions: .init(),
            permissionDecisions: decisions,
            siteAccessPolicyDidPersist: {
                policyPersistenceCount += 1
            }
        )
        let fixture = try await makeWebExtension(
            named: "Prepared Extension",
            permissions: [tabsPermission.rawValue]
        )
        let registry = ExtensionContextLoadRegistry()
        let request = ExtensionContextLoadRequest(
            extensionId: extensionID,
            profileId: profileID,
            sourceKind: .directory,
            sourceBundlePath: fixture.directory.path,
            packageRoot: fixture.directory,
            manifest: fixture.manifest,
            operation: .install,
            activationCause: .installation,
            claim: registry.begin(
                for: .init(profileId: profileID, extensionId: extensionID)
            ),
            mutationLease: nil
        )

        let first = preparation.prepare(
            webExtension: fixture.webExtension,
            request: request
        )
        let second = preparation.prepare(
            webExtension: fixture.webExtension,
            request: request
        )

        XCTAssertEqual(
            first.context.permissionStatus(for: tabsPermission),
            .deniedExplicitly
        )
        XCTAssertEqual(
            second.context.permissionStatus(for: tabsPermission),
            .deniedExplicitly
        )
        XCTAssertEqual(policyPersistenceCount, 1)
        let expectedRuntimeIdentifier =
            SafariWebExtensionRuntimeIdentity.webKitStorageIdentifier(
                extensionId: extensionID,
                sourceKind: .directory,
                sourceBundlePath: fixture.directory.path
            )
        XCTAssertEqual(first.runtimeIdentifier, expectedRuntimeIdentifier)
        XCTAssertEqual(first.context.uniqueIdentifier, expectedRuntimeIdentifier)
        XCTAssertEqual(first.context.baseURL.scheme, "safari-web-extension")
    }

    func testPermissionDedupeRequiresExactCurrentContextIdentity()
        async throws {
        let database = try SumiDatabase.inMemory()
        let profileID = UUID()
        let extensionID = "dedupe-extension"
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        let store = ExtensionPermissionDecisionStore(
            database: database,
            profileRuntime: runtime
        )
        let fixture = try await makeWebExtension(named: "Dedupe Extension")
        let context = WKWebExtensionContext(for: fixture.webExtension)
        let replacement = WKWebExtensionContext(for: fixture.webExtension)

        XCTAssertNil(
            store.permissionPromptDedupeKey(
                extensionContext: context,
                targets: ["tabs"]
            )
        )
        _ = runtime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )
        XCTAssertEqual(
            store.permissionPromptDedupeKey(
                extensionContext: context,
                targets: [" Tabs "]
            ),
            "\(profileID.uuidString.lowercased())|\(extensionID)|tabs"
        )

        _ = runtime.setContext(
            replacement,
            extensionId: extensionID,
            profileId: profileID
        )
        XCTAssertNil(
            store.permissionPromptDedupeKey(
                extensionContext: context,
                targets: ["tabs"]
            )
        )
        XCTAssertNotNil(
            store.permissionPromptDedupeKey(
                extensionContext: replacement,
                targets: ["tabs"]
            )
        )
    }

    private func makeWebExtension(
        named name: String,
        permissions: [String] = []
    ) async throws -> (
        webExtension: WKWebExtension,
        directory: URL,
        manifest: [String: Any]
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
        ]
        if permissions.isEmpty == false {
            manifest["permissions"] = permissions
        }
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        return (
            try await WKWebExtension(resourceBaseURL: directory),
            directory,
            manifest
        )
    }
}
