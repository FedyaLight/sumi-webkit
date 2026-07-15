@testable import Sumi
import SwiftData
import XCTest

@available(macOS 15.5, *)
@MainActor
final class InstalledExtensionCatalogTests: XCTestCase {
    func testFailedFetchPreservesAuthoritativeCatalogReadinessToolbarPinsRevisionAndDurability() throws {
        let harness = try makeHarness()
        let existing = makeRecord(id: "existing-extension")
        harness.inspection.actionSurfaces.installedExtensions.upsert(
            existing,
            durability: .volatileExactRuntime
        )
        let revision = harness.inspection.actionSurfaces.installedExtensions.recordRevision(
            for: existing.id
        )
        harness.inspection.actionSurfaces.publication.markRuntimePublicationReady()
        harness.setPinnedToolbarExtensionIDs([existing.id])

        let enabled = harness.inspection.installation.catalog.publish(
            .init(
                didFetchPersistedMetadata: false,
                records: [],
                enabledEntities: []
            )
        )

        XCTAssertTrue(enabled.isEmpty)
        XCTAssertEqual(
            harness.inspection.actionSurfaces.installedExtensions.records.map(\.id),
            [existing.id]
        )
        XCTAssertEqual(
            harness.inspection.actionSurfaces.installedExtensions.recordRevision(
                for: existing.id
            ),
            revision
        )
        XCTAssertEqual(
            harness.inspection.actionSurfaces.installedExtensions.recordDurability(
                for: existing.id
            ),
            .volatileExactRuntime
        )
        XCTAssertTrue(harness.inspection.actionSurfaces.publication.extensionsLoaded)
        XCTAssertEqual(harness.inspection.actionSurfaces.publication.pinnedToolbarExtensionIDs, [existing.id])
        XCTAssertEqual(
            harness.inspection.actionSurfaces.toolbarPinning.pinnedToolbarExtensionIDsByProfile[harness.profileKey],
            [existing.id]
        )
    }

    func testSuccessfulNonemptySnapshotPublishesAllRecordsAndReturnsOnlyEnabledEntities() throws {
        let harness = try makeHarness()
        let enabled = makeRecord(id: "enabled-extension")
        let disabled = makeRecord(id: "disabled-extension", isEnabled: false)
        harness.setPinnedToolbarExtensionIDs([disabled.id])
        let enabledEntity = ExtensionEntity(record: enabled)

        let entitiesToLoad = harness.inspection.installation.catalog.publish(
            .init(
                didFetchPersistedMetadata: true,
                records: [disabled, enabled],
                enabledEntities: [enabledEntity]
            )
        )

        XCTAssertEqual(entitiesToLoad.map(\.id), [enabled.id])
        XCTAssertEqual(
            Set(harness.inspection.actionSurfaces.installedExtensions.records.map(\.id)),
            Set([enabled.id, disabled.id])
        )
        XCTAssertTrue(harness.inspection.actionSurfaces.publication.extensionsLoaded)
        XCTAssertEqual(
            harness.inspection.actionSurfaces.publication.pinnedToolbarExtensionIDs,
            [disabled.id]
        )
        XCTAssertEqual(
            harness.inspection.actionSurfaces.toolbarPinning.pinnedToolbarExtensionIDsByProfile[harness.profileKey],
            [disabled.id]
        )
    }

    func testFailedInitialFetchDoesNotPublishReadiness() throws {
        let harness = try makeHarness()
        XCTAssertFalse(harness.inspection.actionSurfaces.publication.extensionsLoaded)

        _ = harness.inspection.installation.catalog.publish(
            .init(
                didFetchPersistedMetadata: false,
                records: [],
                enabledEntities: []
            )
        )

        XCTAssertFalse(harness.inspection.actionSurfaces.publication.extensionsLoaded)
    }

    func testVolatileReconciliationFailurePreservesExactLiveSnapshotAndDefersPublication() throws {
        let harness = try makeHarness()
        let exactLiveRecord = makeRecord(id: "exact-live-extension")
        harness.inspection.actionSurfaces.installedExtensions.upsert(
            exactLiveRecord,
            durability: .volatileExactRuntime
        )
        let revision = harness.inspection.actionSurfaces.installedExtensions.recordRevision(
            for: exactLiveRecord.id
        )
        harness.setPinnedToolbarExtensionIDs([exactLiveRecord.id])
        let persistence = FailingCatalogPersistence()
        var didPublishReadiness = false
        let catalog = InstalledExtensionCatalog(
            environment: .init(
                metadataStore: harness.inspection.installation.metadata,
                installedRecords: harness.inspection.actionSurfaces.installedExtensions,
                volatileRecords: ExtensionVolatileInstallationRecordReconciler(
                    persistence: persistence,
                    installedRecords: harness.inspection.actionSurfaces.installedExtensions
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
        XCTAssertFalse(harness.inspection.actionSurfaces.publication.extensionsLoaded)
        XCTAssertEqual(
            harness.inspection.actionSurfaces.installedExtensions.records.map(\.id),
            [exactLiveRecord.id]
        )
        XCTAssertEqual(
            harness.inspection.actionSurfaces.installedExtensions.recordRevision(
                for: exactLiveRecord.id
            ),
            revision
        )
        XCTAssertEqual(
            harness.inspection.actionSurfaces.installedExtensions.recordDurability(
                for: exactLiveRecord.id
            ),
            .volatileExactRuntime
        )
        XCTAssertEqual(
            harness.inspection.actionSurfaces.publication.pinnedToolbarExtensionIDs,
            [exactLiveRecord.id]
        )
        XCTAssertEqual(
            harness.inspection.actionSurfaces.toolbarPinning.pinnedToolbarExtensionIDsByProfile[harness.profileKey],
            [exactLiveRecord.id]
        )
    }

    func testSuccessfulEmptySnapshotClearsCatalogPublishesReadinessAndReconcilesPins() throws {
        let harness = try makeHarness()
        let existing = makeRecord(id: "removed-extension")
        harness.inspection.actionSurfaces.installedExtensions.setAll([existing])
        harness.inspection.actionSurfaces.publication.resetRuntimePublicationReadiness()
        harness.setPinnedToolbarExtensionIDs([existing.id])

        let enabled = harness.inspection.installation.catalog.publish(
            .init(
                didFetchPersistedMetadata: true,
                records: [],
                enabledEntities: []
            )
        )

        XCTAssertTrue(enabled.isEmpty)
        XCTAssertTrue(harness.inspection.actionSurfaces.installedExtensions.records.isEmpty)
        XCTAssertTrue(harness.inspection.actionSurfaces.publication.extensionsLoaded)
        XCTAssertTrue(harness.inspection.actionSurfaces.publication.pinnedToolbarExtensionIDs.isEmpty)
        XCTAssertTrue(
            harness.inspection.actionSurfaces.toolbarPinning.pinnedToolbarExtensionIDsByProfile[harness.profileKey]?.isEmpty == true
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
        let inspection = ExtensionManagerInspectionCapture()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration(),
            extensionPreferences: preferences,
            testInspectionDidAssemble: inspection.install
        )
        // Construction performs a real successful empty load. Reset readiness
        // so each test can establish the pre-publication state it owns.
        inspection.inspection.actionSurfaces.publication.resetRuntimePublicationReadiness()
        return Harness(
            manager: manager,
            inspection: inspection.inspection,
            profileKey: ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(
                for: profile.id
            )
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
        let inspection: ExtensionManagerTestInspection
        let profileKey: String

        @MainActor
        func setPinnedToolbarExtensionIDs(_ ids: [String]) {
            var idsByProfile = inspection.actionSurfaces.toolbarPinning
                .pinnedToolbarExtensionIDsByProfile
            idsByProfile[profileKey] = ids
            inspection.actionSurfaces.toolbarPinning
                .replacePinnedToolbarExtensionIDsByProfile(idsByProfile)
        }
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
