@testable import Sumi
import SwiftData
import XCTest

@available(macOS 15.5, *)
@MainActor
final class InstalledExtensionCatalogTests: XCTestCase {
    func testFailedFetchPreservesAuthoritativeCatalogReadinessToolbarPinsRevisionAndDurability() throws {
        let harness = try makeHarness()
        let existing = makeRecord(id: "existing-extension")
        harness.manager.installedExtensionCollection.upsert(
            existing,
            durability: .volatileExactRuntime
        )
        let revision = harness.manager.installedExtensionCollection.recordRevision(
            for: existing.id
        )
        harness.manager.markExtensionRuntimePublicationReady()
        harness.manager.pinnedToolbarExtensionIDsByProfile[harness.profileKey] = [
            existing.id,
        ]

        let enabled = harness.manager.installedExtensionCatalog.publish(
            .init(
                didFetchPersistedMetadata: false,
                records: [],
                enabledEntities: []
            )
        )

        XCTAssertTrue(enabled.isEmpty)
        XCTAssertEqual(
            harness.manager.installedExtensionCollection.records.map(\.id),
            [existing.id]
        )
        XCTAssertEqual(
            harness.manager.installedExtensionCollection.recordRevision(
                for: existing.id
            ),
            revision
        )
        XCTAssertEqual(
            harness.manager.installedExtensionCollection.recordDurability(
                for: existing.id
            ),
            .volatileExactRuntime
        )
        XCTAssertTrue(harness.manager.extensionsLoaded)
        XCTAssertEqual(harness.manager.pinnedToolbarExtensionIDs, [existing.id])
        XCTAssertEqual(
            harness.manager.pinnedToolbarExtensionIDsByProfile[harness.profileKey],
            [existing.id]
        )
    }

    func testSuccessfulNonemptySnapshotPublishesAllRecordsAndReturnsOnlyEnabledEntities() throws {
        let harness = try makeHarness()
        let enabled = makeRecord(id: "enabled-extension")
        let disabled = makeRecord(id: "disabled-extension", isEnabled: false)
        harness.manager.pinnedToolbarExtensionIDsByProfile[harness.profileKey] = [
            disabled.id,
        ]
        let enabledEntity = ExtensionEntity(record: enabled)

        let entitiesToLoad = harness.manager.installedExtensionCatalog.publish(
            .init(
                didFetchPersistedMetadata: true,
                records: [disabled, enabled],
                enabledEntities: [enabledEntity]
            )
        )

        XCTAssertEqual(entitiesToLoad.map(\.id), [enabled.id])
        XCTAssertEqual(
            Set(harness.manager.installedExtensionCollection.records.map(\.id)),
            Set([enabled.id, disabled.id])
        )
        XCTAssertTrue(harness.manager.extensionsLoaded)
        XCTAssertEqual(
            harness.manager.pinnedToolbarExtensionIDs,
            [disabled.id]
        )
        XCTAssertEqual(
            harness.manager.pinnedToolbarExtensionIDsByProfile[harness.profileKey],
            [disabled.id]
        )
    }

    func testFailedInitialFetchDoesNotPublishReadiness() throws {
        let harness = try makeHarness()
        XCTAssertFalse(harness.manager.extensionsLoaded)

        _ = harness.manager.installedExtensionCatalog.publish(
            .init(
                didFetchPersistedMetadata: false,
                records: [],
                enabledEntities: []
            )
        )

        XCTAssertFalse(harness.manager.extensionsLoaded)
    }

    func testVolatileReconciliationFailurePreservesExactLiveSnapshotAndDefersPublication() throws {
        let harness = try makeHarness()
        let exactLiveRecord = makeRecord(id: "exact-live-extension")
        harness.manager.installedExtensionCollection.upsert(
            exactLiveRecord,
            durability: .volatileExactRuntime
        )
        let revision = harness.manager.installedExtensionCollection.recordRevision(
            for: exactLiveRecord.id
        )
        harness.manager.pinnedToolbarExtensionIDsByProfile[harness.profileKey] = [
            exactLiveRecord.id,
        ]
        let persistence = FailingCatalogPersistence()
        var didPublishReadiness = false
        let catalog = InstalledExtensionCatalog(
            environment: .init(
                metadataStore: harness.manager.installationMetadataStore,
                installedRecords: harness.manager.installedExtensionCollection,
                volatileRecords: ExtensionVolatileInstallationRecordReconciler(
                    persistence: persistence,
                    installedRecords: harness.manager.installedExtensionCollection
                ),
                liveContextCount: { 0 },
                markCatalogLoaded: { didPublishReadiness = true },
                trace: { _ in }
            )
        )

        let enabled = catalog.load()

        XCTAssertTrue(enabled.isEmpty)
        XCTAssertEqual(persistence.persistedIDs, [exactLiveRecord.id])
        XCTAssertFalse(didPublishReadiness)
        XCTAssertFalse(harness.manager.extensionsLoaded)
        XCTAssertEqual(
            harness.manager.installedExtensionCollection.records.map(\.id),
            [exactLiveRecord.id]
        )
        XCTAssertEqual(
            harness.manager.installedExtensionCollection.recordRevision(
                for: exactLiveRecord.id
            ),
            revision
        )
        XCTAssertEqual(
            harness.manager.installedExtensionCollection.recordDurability(
                for: exactLiveRecord.id
            ),
            .volatileExactRuntime
        )
        XCTAssertEqual(
            harness.manager.pinnedToolbarExtensionIDs,
            [exactLiveRecord.id]
        )
        XCTAssertEqual(
            harness.manager.pinnedToolbarExtensionIDsByProfile[harness.profileKey],
            [exactLiveRecord.id]
        )
    }

    func testSuccessfulEmptySnapshotClearsCatalogPublishesReadinessAndReconcilesPins() throws {
        let harness = try makeHarness()
        let existing = makeRecord(id: "removed-extension")
        harness.manager.installedExtensionCollection.setAll([existing])
        harness.manager.resetExtensionRuntimePublicationReadiness()
        harness.manager.pinnedToolbarExtensionIDsByProfile[harness.profileKey] = [existing.id]

        let enabled = harness.manager.installedExtensionCatalog.publish(
            .init(
                didFetchPersistedMetadata: true,
                records: [],
                enabledEntities: []
            )
        )

        XCTAssertTrue(enabled.isEmpty)
        XCTAssertTrue(harness.manager.installedExtensionCollection.records.isEmpty)
        XCTAssertTrue(harness.manager.extensionsLoaded)
        XCTAssertTrue(harness.manager.pinnedToolbarExtensionIDs.isEmpty)
        XCTAssertTrue(
            harness.manager.pinnedToolbarExtensionIDsByProfile[harness.profileKey]?.isEmpty == true
        )
    }

    private func makeHarness() throws -> Harness {
        let profile = Profile(name: "Catalog Test Profile")
        let suiteName = "SumiTests.InstalledExtensionCatalog.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            preferences.removePersistentDomain(forName: suiteName)
        }
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration(),
            extensionPreferences: preferences
        )
        // Construction performs a real successful empty load. Reset readiness
        // so each test can establish the pre-publication state it owns.
        manager.resetExtensionRuntimePublicationReadiness()
        return Harness(
            manager: manager,
            profileKey: ExtensionManager.pinnedToolbarProfileKey(for: profile.id)
        )
    }

    private func makeRecord(
        id: String,
        isEnabled: Bool = true
    ) -> InstalledExtension {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Catalog Test Extension",
            "version": "1.0",
        ]
        return InstalledExtensionRecord(
            id: id,
            name: "Catalog Test Extension",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: isEnabled,
            installDate: Date(timeIntervalSince1970: 1),
            lastUpdateDate: Date(timeIntervalSince1970: 1),
            packagePath: "/tmp/\(id)",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "source-\(id)",
            manifestRootFingerprint: "manifest-\(id)",
            sourceBundlePath: "/tmp/\(id)",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: true,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: false,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: true,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: manifest
        )
    }

    private struct Harness {
        let manager: ExtensionManager
        let profileKey: String
    }
}

@available(macOS 15.5, *)
@MainActor
private final class FailingCatalogPersistence:
    ExtensionInstallationRecordPersisting {
    private(set) var persistedIDs: [String] = []

    func persist(record: InstalledExtension) throws {
        persistedIDs.append(record.id)
        throw Failure.unavailable
    }

    func restore(
        originalRecord: InstalledExtension?,
        extensionID: String
    ) throws {
        _ = originalRecord
        _ = extensionID
    }

    private enum Failure: Error {
        case unavailable
    }
}
