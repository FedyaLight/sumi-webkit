import SwiftData
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationRecordTransactionTests: XCTestCase {
    func testCommitPersistsBeforePublishingCandidate() throws {
        let events = EventLog()
        let collection = makeCollection(events: events)
        let persistence = RecordPersistenceStub(events: events)
        let transaction = ExtensionInstallationRecordTransaction(
            persistence: persistence,
            installedRecords: collection
        )
        let candidate = makeRecord(name: "Candidate")

        try transaction.commitCandidate(
            candidate,
            replacing: .init(extensionID: candidate.id, originalRecord: nil)
        )

        XCTAssertEqual(events.values, ["persist:Candidate", "publish"])
        XCTAssertEqual(collection.records.first?.name, "Candidate")
        XCTAssertEqual(
            collection.recordDurability(for: candidate.id),
            .durable
        )
    }

    func testFreshPersistenceFailureRestoresAbsenceWithoutPublication() {
        let events = EventLog()
        let collection = makeCollection(events: events)
        let persistence = RecordPersistenceStub(events: events)
        persistence.persistError = TestError.persistence
        let transaction = ExtensionInstallationRecordTransaction(
            persistence: persistence,
            installedRecords: collection
        )
        let candidate = makeRecord(name: "Candidate")

        XCTAssertThrowsError(
            try transaction.commitCandidate(
                candidate,
                replacing: .init(
                    extensionID: candidate.id,
                    originalRecord: nil
                )
            )
        )

        XCTAssertEqual(events.values, ["persist:Candidate", "restore:nil"])
        XCTAssertTrue(collection.records.isEmpty)
    }

    func testReplacementPersistenceFailureRestoresOriginalWithoutPublication() {
        let events = EventLog()
        let collection = makeCollection(events: events)
        let original = makeRecord(name: "Original")
        collection.upsert(original)
        events.values.removeAll()
        let persistence = RecordPersistenceStub(events: events)
        persistence.persistError = TestError.persistence
        let transaction = ExtensionInstallationRecordTransaction(
            persistence: persistence,
            installedRecords: collection
        )

        XCTAssertThrowsError(
            try transaction.commitCandidate(
                makeRecord(name: "Candidate"),
                replacing: .init(
                    extensionID: original.id,
                    originalRecord: original
                )
            )
        )

        XCTAssertEqual(
            events.values,
            ["persist:Candidate", "restore:Original"]
        )
        XCTAssertEqual(collection.records.first?.name, "Original")
    }

    func testExactRuntimePersistenceFailurePublishesTypedVolatileCandidate() {
        let events = EventLog()
        let collection = makeCollection(events: events)
        let original = makeRecord(name: "Original")
        collection.upsert(original)
        events.values.removeAll()
        let persistence = RecordPersistenceStub(events: events)
        persistence.persistError = TestError.persistence
        let transaction = ExtensionInstallationRecordTransaction(
            persistence: persistence,
            installedRecords: collection
        )

        let result = transaction.reconcileCandidateWithExactRuntime(
            makeRecord(name: "Candidate"),
            replacing: .init(
                extensionID: original.id,
                originalRecord: original
            )
        )

        guard case .volatileCandidatePublished(let failure) = result else {
            return XCTFail("Expected an explicit volatile reconciliation")
        }
        XCTAssertTrue(
            failure.localizedDescription.contains("persistence failed")
        )
        XCTAssertEqual(
            events.values,
            ["persist:Candidate", "restore:Original", "publish"]
        )
        XCTAssertEqual(collection.records.first?.name, "Candidate")
        XCTAssertEqual(
            collection.recordDurability(for: original.id),
            .volatileExactRuntime
        )
    }

    func testRealMetadataReplacementIsRestoredAfterPostSaveFailure() throws {
        let container = try makeContainer()
        let store = ExtensionInstallationMetadataStore(
            context: container.mainContext
        )
        let original = makeRecord(name: "Original")
        try store.persist(record: original)
        let collection = InstalledExtensionCollection()
        collection.connectRecordChanges {}
        collection.upsert(original)
        let transaction = ExtensionInstallationRecordTransaction(
            persistence: PersistThenThrowRecordStore(base: store),
            installedRecords: collection
        )

        XCTAssertThrowsError(
            try transaction.commitCandidate(
                makeRecord(name: "Candidate"),
                replacing: .init(
                    extensionID: original.id,
                    originalRecord: original
                )
            )
        )

        let persisted = try XCTUnwrap(
            store.extensionEntity(for: original.id)
        )
        XCTAssertEqual(persisted.name, "Original")
        XCTAssertEqual(persisted.manifestRootFingerprint, "Original")
        XCTAssertEqual(collection.records.first?.name, "Original")
    }

    func testRealMetadataFreshEntityIsDeletedAfterPostSaveFailure() throws {
        let container = try makeContainer()
        let store = ExtensionInstallationMetadataStore(
            context: container.mainContext
        )
        let collection = InstalledExtensionCollection()
        collection.connectRecordChanges {}
        let candidate = makeRecord(name: "Candidate")
        let transaction = ExtensionInstallationRecordTransaction(
            persistence: PersistThenThrowRecordStore(base: store),
            installedRecords: collection
        )

        XCTAssertThrowsError(
            try transaction.commitCandidate(
                candidate,
                replacing: .init(
                    extensionID: candidate.id,
                    originalRecord: nil
                )
            )
        )

        XCTAssertNil(try store.extensionEntity(for: candidate.id))
        XCTAssertTrue(collection.records.isEmpty)
    }

    func testVolatileRecordMustPersistBeforeBecomingDurable() throws {
        let events = EventLog()
        let collection = makeCollection(events: events)
        let candidate = makeRecord(name: "Candidate")
        collection.upsert(candidate, durability: .volatileExactRuntime)
        events.values.removeAll()
        let persistence = RecordPersistenceStub(events: events)
        persistence.persistError = TestError.persistence
        let reconciler = ExtensionVolatileInstallationRecordReconciler(
            persistence: persistence,
            installedRecords: collection
        )

        XCTAssertThrowsError(try reconciler.reconcile(candidate.id))
        XCTAssertEqual(
            collection.recordDurability(for: candidate.id),
            .volatileExactRuntime
        )

        persistence.persistError = nil
        try reconciler.reconcile(candidate.id)

        XCTAssertEqual(events.values, ["persist:Candidate", "persist:Candidate"])
        XCTAssertEqual(collection.recordDurability(for: candidate.id), .durable)
    }

    func testReconcileAllPersistsEveryVolatileCandidate() throws {
        let events = EventLog()
        let collection = makeCollection(events: events)
        let first = makeRecord(id: "first", name: "First")
        let second = makeRecord(id: "second", name: "Second")
        collection.upsert(first, durability: .volatileExactRuntime)
        collection.upsert(second, durability: .volatileExactRuntime)
        events.values.removeAll()
        let reconciler = ExtensionVolatileInstallationRecordReconciler(
            persistence: RecordPersistenceStub(events: events),
            installedRecords: collection
        )

        try reconciler.reconcileAll()

        XCTAssertEqual(events.values, ["persist:First", "persist:Second"])
        XCTAssertEqual(collection.recordDurability(for: first.id), .durable)
        XCTAssertEqual(collection.recordDurability(for: second.id), .durable)
    }

    private func makeCollection(events: EventLog) -> InstalledExtensionCollection {
        let collection = InstalledExtensionCollection()
        collection.connectRecordChanges { events.values.append("publish") }
        return collection
    }

    private func makeRecord(
        id: String = "com.example.transaction",
        name: String
    ) -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: name,
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(timeIntervalSince1970: 1),
            lastUpdateDate: Date(timeIntervalSince1970: 2),
            packagePath: "/tmp/com.example.transaction",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "source",
            manifestRootFingerprint: name,
            sourceBundlePath: "/tmp/source",
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
                "name": name,
                "version": "1.0",
            ]
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RecordPersistenceStub:
    ExtensionInstallationRecordPersisting {
    var persistError: (any Error)?
    var restoreError: (any Error)?
    private let events: EventLog

    init(events: EventLog) {
        self.events = events
    }

    func persist(record: InstalledExtension) throws {
        events.values.append("persist:\(record.name)")
        if let persistError { throw persistError }
    }

    func restore(
        originalRecord: InstalledExtension?,
        extensionID: String
    ) throws {
        events.values.append("restore:\(originalRecord?.name ?? "nil")")
        if let restoreError { throw restoreError }
        _ = extensionID
    }
}

private final class EventLog {
    var values: [String] = []
}

private enum TestError: Error {
    case persistence
}

@available(macOS 15.5, *)
@MainActor
private final class PersistThenThrowRecordStore:
    ExtensionInstallationRecordPersisting {
    private let base: ExtensionInstallationMetadataStore

    init(base: ExtensionInstallationMetadataStore) {
        self.base = base
    }

    func persist(record: InstalledExtension) throws {
        try base.persist(record: record)
        throw TestError.persistence
    }

    func restore(
        originalRecord: InstalledExtension?,
        extensionID: String
    ) throws {
        try base.restore(
            originalRecord: originalRecord,
            extensionID: extensionID
        )
    }
}
