import Combine
@testable import Sumi
import SumiDomain
import SumiWebRuntime
import XCTest

@MainActor
final class SplitGroupStoreTests: XCTestCase {
    func testTypedMemberIndexDoesNotConflateTabAndPinUUIDs() throws {
        let sharedID = UUID()
        let regularGroup = try XCTUnwrap(group([
            .regularTab(sharedID),
            .regularTab(UUID()),
        ]))
        let shortcutGroup = try XCTUnwrap(group([
            .shortcutPin(sharedID),
            .shortcutPin(UUID()),
        ], container: .shortcutSidebar(
            spaceId: UUID(),
            profileId: nil,
            folderId: nil,
            index: 0
        )))
        let store = SplitGroupStore()

        store.replaceAll(with: [regularGroup, shortcutGroup])

        XCTAssertEqual(
            store.group(containing: .regularTab(sharedID))?.id,
            regularGroup.id
        )
        XCTAssertEqual(
            store.group(containing: .shortcutPin(sharedID))?.id,
            shortcutGroup.id
        )
    }

    func testStoreRebuildsEveryIndexWhenReplacingAll() throws {
        let firstMemberID = UUID()
        let first = try XCTUnwrap(group([
            .regularTab(firstMemberID),
            .regularTab(UUID()),
        ]))
        let secondMemberID = UUID()
        let second = try XCTUnwrap(group([
            .regularTab(secondMemberID),
            .regularTab(UUID()),
        ]))
        let store = SplitGroupStore()

        store.replaceAll(with: [first])
        store.replaceAll(with: [second])

        XCTAssertNil(store.group(id: first.id))
        XCTAssertNil(store.group(containing: .regularTab(firstMemberID)))
        XCTAssertEqual(store.group(id: second.id), second)
        XCTAssertEqual(store.index(of: second.id), 0)
    }

    func testMutationRejectsStaleExpectedSnapshotWithoutSideEffects() throws {
        let original = try XCTUnwrap(group([
            .regularTab(UUID()),
            .regularTab(UUID()),
        ]))
        let current = try XCTUnwrap(original.changingLayout(to: .horizontal))
        let staleReplacement = try XCTUnwrap(
            original.changingLayout(to: .grid)
        )
        let harness = try MutationHarness(groups: [current])

        XCTAssertFalse(
            harness.service.replace(original, with: staleReplacement)
        )
        XCTAssertEqual(harness.store.groups, [current])
        XCTAssertEqual(harness.transactionCount, 0)
        XCTAssertEqual(harness.announceCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertFalse(harness.persistenceScheduled)
    }

    func testSuccessfulReplacementPublishesAndPersistsExactlyOnce() throws {
        let original = try XCTUnwrap(group([
            .regularTab(UUID()),
            .regularTab(UUID()),
        ]))
        let replacement = try XCTUnwrap(
            original.changingLayout(to: .horizontal)
        )
        let harness = try MutationHarness(groups: [original])

        XCTAssertTrue(harness.service.replace(original, with: replacement))

        XCTAssertEqual(harness.store.groups, [replacement])
        XCTAssertEqual(harness.transactionCount, 1)
        XCTAssertEqual(harness.announceCount, 1)
        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertTrue(harness.persistenceScheduled)
    }

    func testInsertRejectsMemberOwnedByAnotherGroup() throws {
        let sharedMemberID = UUID()
        let existing = try XCTUnwrap(group([
            .regularTab(sharedMemberID),
            .regularTab(UUID()),
        ]))
        let conflicting = try XCTUnwrap(group([
            .regularTab(sharedMemberID),
            .regularTab(UUID()),
        ]))
        let harness = try MutationHarness(groups: [existing])

        XCTAssertFalse(harness.service.insert(conflicting))
        XCTAssertEqual(harness.store.groups, [existing])
        XCTAssertEqual(harness.transactionCount, 0)
    }

    private func group(
        _ members: [SumiDomain.SplitMember],
        layoutKind: SumiDomain.SplitLayoutKind = .vertical,
        container: SumiDomain.SplitGroupContainer = .regularTabs(spaceId: nil)
    ) -> SumiDomain.SplitGroup? {
        SumiDomain.SplitGroup.make(
            members: members,
            layoutKind: layoutKind,
            container: container
        )
    }
}

@MainActor
private final class MutationHarness {
    private let manager: TabManager
    private let lookup: TabStructuralLookupCoordinator
    private let persistence: TabStructuralPersistenceService
    private var changeObservation: AnyCancellable?
    private(set) var announceCount = 0

    let store: SplitGroupStore
    let service: SplitGroupMutationService
    var transactionCount: Int {
        Int(lookup.mutationRevision)
    }
    var publishCount: Int { transactionCount }
    var persistenceScheduled: Bool {
        persistence.scheduledPersistTask != nil
    }

    init(groups: [SumiDomain.SplitGroup]) throws {
        let container = try makeInMemoryStartupDatabase()
        let manager = TabManager(
            database: container,
            webViewSessions: WebViewSessionRepository(),
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: container
            ),
            loadPersistedState: false
        )
        self.manager = manager
        let lookup = TabStructuralLookupCoordinator(
            eventBus: manager.tabStructureEventBus,
            stateStore: manager.stateStore
        )
        self.lookup = lookup
        persistence = manager.structuralPersistence
        store = manager.stateStore.splitGroups
        service = SplitGroupMutationService(
            store: store,
            publication: TabStructuralMutationPublisher(
                persistence: manager.structuralPersistence,
                faviconService: manager.faviconService,
                lookup: lookup,
                changes: manager.objectWillChange,
                regularTabs: manager.stateStore.regularTabs
            )
        )
        store.replaceAll(with: groups)
        changeObservation = manager.objectWillChange.sink { [weak self] _ in
            self?.announceCount += 1
        }
    }
}
