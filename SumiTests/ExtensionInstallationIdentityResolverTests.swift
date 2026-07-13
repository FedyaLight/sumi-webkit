import XCTest
import SwiftData

@testable import Sumi

@MainActor
final class ExtensionInstallationIdentityResolverTests: XCTestCase {
    func testFreshSourceWithoutDeclaredIdentityUsesFreshID() throws {
        let resolution = try ExtensionInstallationIdentityResolver.resolve(
            .init(
                sourceBundleURL: URL(fileURLWithPath: "/tmp/fresh"),
                declaredExtensionID: nil,
                sourceKind: .directory,
                safariRuntimeIdentity: nil,
                freshExtensionID: "fresh-id",
                persistedIdentities: []
            )
        )

        XCTAssertEqual(resolution.extensionID, "fresh-id")
        XCTAssertNil(resolution.existingExtensionID)
    }

    func testDeclaredIdentityFindsExistingRecordFromMovedSource() throws {
        let resolution = try ExtensionInstallationIdentityResolver.resolve(
            .init(
                sourceBundleURL: URL(fileURLWithPath: "/tmp/new-source"),
                declaredExtensionID: "com.example.extension",
                sourceKind: .directory,
                safariRuntimeIdentity: nil,
                freshExtensionID: "unused",
                persistedIdentities: [
                    .init(
                        extensionID: "com.example.extension",
                        sourceBundlePath: "/tmp/old-source",
                        sourceKind: .directory,
                        safariRuntimeIdentity: nil
                    )
                ]
            )
        )

        XCTAssertEqual(resolution.extensionID, "com.example.extension")
        XCTAssertEqual(
            resolution.existingExtensionID,
            "com.example.extension"
        )
    }

    func testExistingSourceCannotSilentlyChangeDeclaredIdentity() {
        XCTAssertThrowsError(
            try ExtensionInstallationIdentityResolver.resolve(
                .init(
                    sourceBundleURL: URL(fileURLWithPath: "/tmp/source"),
                    declaredExtensionID: "com.example.sibling",
                    sourceKind: .directory,
                    safariRuntimeIdentity: nil,
                    freshExtensionID: "unused",
                    persistedIdentities: [
                        .init(
                            extensionID: "com.example.original",
                            sourceBundlePath: "/tmp/source",
                            sourceKind: .directory,
                            safariRuntimeIdentity: nil
                        ),
                        .init(
                            extensionID: "com.example.sibling",
                            sourceBundlePath: "/tmp/sibling",
                            sourceKind: .directory,
                            safariRuntimeIdentity: nil
                        ),
                    ]
                )
            )
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "changed its declared extension identity"
                ),
                error.localizedDescription
            )
        }
    }

    func testDuplicatePersistedSourceIdentityIsRejected() {
        XCTAssertThrowsError(
            try ExtensionInstallationIdentityResolver.resolve(
                .init(
                    sourceBundleURL: URL(fileURLWithPath: "/tmp/source"),
                    declaredExtensionID: nil,
                    sourceKind: .directory,
                    safariRuntimeIdentity: nil,
                    freshExtensionID: "unused",
                    persistedIdentities: [
                        .init(
                            extensionID: "first",
                            sourceBundlePath: "/tmp/source",
                            sourceKind: .directory,
                            safariRuntimeIdentity: nil
                        ),
                        .init(
                            extensionID: "second",
                            sourceBundlePath: "/tmp/source/../source",
                            sourceKind: .directory,
                            safariRuntimeIdentity: nil
                        ),
                    ]
                )
            )
        )
    }

    func testDeclaredIdentityCannotTakeOverDifferentPackageKind() {
        XCTAssertThrowsError(
            try ExtensionInstallationIdentityResolver.resolve(
                .init(
                    sourceBundleURL: URL(fileURLWithPath: "/tmp/unpacked"),
                    declaredExtensionID: "com.example.safari",
                    sourceKind: .directory,
                    safariRuntimeIdentity: nil,
                    freshExtensionID: "unused",
                    persistedIdentities: [
                        .init(
                            extensionID: "com.example.safari",
                            sourceBundlePath: "/tmp/existing.appex",
                            sourceKind: .safariAppExtension,
                            safariRuntimeIdentity: "com.example.safari (TEAM)"
                        )
                    ]
                )
            )
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("different package kind"),
                error.localizedDescription
            )
        }
    }

    func testMovedSafariSourceRequiresSameSigningIdentity() {
        XCTAssertThrowsError(
            try ExtensionInstallationIdentityResolver.resolve(
                .init(
                    sourceBundleURL: URL(fileURLWithPath: "/tmp/new.appex"),
                    declaredExtensionID: "com.example.safari",
                    sourceKind: .safariAppExtension,
                    safariRuntimeIdentity: "com.example.safari (NEWTEAM)",
                    freshExtensionID: "unused",
                    persistedIdentities: [
                        .init(
                            extensionID: "com.example.safari",
                            sourceBundlePath: "/tmp/old.appex",
                            sourceKind: .safariAppExtension,
                            safariRuntimeIdentity: "com.example.safari (OLDTEAM)"
                        )
                    ]
                )
            )
        )
    }

    func testSourceAdmissionRejectsOverlapAndReleasesExactClaim() throws {
        let admission = ExtensionInstallationAdmission()
        let source = URL(fileURLWithPath: "/tmp/source")
        let claim = try XCTUnwrap(admission.begin(sourceBundleURL: source))

        XCTAssertNil(
            admission.begin(
                sourceBundleURL: URL(fileURLWithPath: "/tmp/./source")
            )
        )
        XCTAssertTrue(admission.finish(claim))
        XCTAssertNotNil(admission.begin(sourceBundleURL: source))
    }

    @available(macOS 15.5, *)
    func testPersistedIdentityUsesStoredSafariSigningAnchor() throws {
        let container = try makeModelContainer()
        let entity = ExtensionEntity(
            record: makeRecord(
                safariRuntimeIdentity: "com.example.safari (ORIGINALTEAM)"
            )
        )
        container.mainContext.insert(entity)
        try container.mainContext.save()

        let identities = try ExtensionInstallationMetadataStore(
            context: container.mainContext
        ).persistedInstallationIdentities()

        XCTAssertEqual(identities.count, 1)
        XCTAssertEqual(
            identities.first?.safariRuntimeIdentity,
            "com.example.safari (ORIGINALTEAM)"
        )
        XCTAssertEqual(
            InstalledExtensionRecord(from: entity)?.safariRuntimeIdentity,
            "com.example.safari (ORIGINALTEAM)"
        )
    }

    @available(macOS 15.5, *)
    func testPersistCannotReplaceStoredSafariSigningAnchor() throws {
        let container = try makeModelContainer()
        let store = ExtensionInstallationMetadataStore(
            context: container.mainContext
        )
        try store.persist(
            record: makeRecord(
                safariRuntimeIdentity: "com.example.safari (ORIGINALTEAM)"
            )
        )

        try store.persist(
            record: makeRecord(
                safariRuntimeIdentity: "com.example.safari (DIFFERENTTEAM)"
            )
        )

        let entity = try XCTUnwrap(
            try store.extensionEntity(for: "com.example.safari")
        )
        XCTAssertEqual(
            entity.safariRuntimeIdentity,
            "com.example.safari (ORIGINALTEAM)"
        )
        XCTAssertEqual(
            try store.persistedInstallationIdentities().first?
                .safariRuntimeIdentity,
            "com.example.safari (ORIGINALTEAM)"
        )
    }

    @available(macOS 15.5, *)
    func testLegacySafariRecordWithoutStoredAnchorRemainsReadable() throws {
        let container = try makeModelContainer()
        let entity = ExtensionEntity(
            record: makeRecord(safariRuntimeIdentity: nil)
        )
        container.mainContext.insert(entity)
        try container.mainContext.save()

        let record = try XCTUnwrap(InstalledExtensionRecord(from: entity))
        let identities = try ExtensionInstallationMetadataStore(
            context: container.mainContext
        ).persistedInstallationIdentities()

        XCTAssertNil(record.safariRuntimeIdentity)
        XCTAssertEqual(identities.first?.extensionID, record.id)
        XCTAssertEqual(identities.first?.sourceKind, .safariAppExtension)
    }

    @available(macOS 15.5, *)
    private func makeModelContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeRecord(
        safariRuntimeIdentity: String?
    ) -> InstalledExtensionRecord {
        InstalledExtensionRecord(
            id: "com.example.safari",
            name: "Safari Extension",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(timeIntervalSince1970: 1),
            lastUpdateDate: Date(timeIntervalSince1970: 2),
            packagePath: "/tmp/unavailable-extension-resources",
            iconPath: nil,
            sourceKind: .safariAppExtension,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "source-fingerprint",
            manifestRootFingerprint: "manifest-fingerprint",
            sourceBundlePath: "/tmp/unavailable-extension.appex",
            safariRuntimeIdentity: safariRuntimeIdentity,
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
            manifest: [
                "manifest_version": 3,
                "name": "Safari Extension",
                "version": "1.0",
            ]
        )
    }
}
