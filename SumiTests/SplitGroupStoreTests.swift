@testable import Sumi
import SumiDomain
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
            .shortcutPin(
                sharedID,
                returnPlacement: .essential(profileId: UUID(), index: 0)
            ),
            .shortcutPin(
                UUID(),
                returnPlacement: .essential(profileId: UUID(), index: 1)
            ),
        ]))
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
        let harness = MutationHarness(groups: [current])

        XCTAssertFalse(
            harness.service.replace(original, with: staleReplacement)
        )
        XCTAssertEqual(harness.store.groups, [current])
        XCTAssertEqual(harness.transactionCount, 0)
        XCTAssertEqual(harness.announceCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertEqual(harness.dirtyCount, 0)
        XCTAssertEqual(harness.persistenceCount, 0)
    }

    func testSuccessfulReplacementPublishesAndPersistsExactlyOnce() throws {
        let original = try XCTUnwrap(group([
            .regularTab(UUID()),
            .regularTab(UUID()),
        ]))
        let replacement = try XCTUnwrap(
            original.changingLayout(to: .horizontal)
        )
        let harness = MutationHarness(groups: [original])

        XCTAssertTrue(harness.service.replace(original, with: replacement))

        XCTAssertEqual(harness.store.groups, [replacement])
        XCTAssertEqual(harness.transactionCount, 1)
        XCTAssertEqual(harness.announceCount, 1)
        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertEqual(harness.dirtyCount, 1)
        XCTAssertEqual(harness.persistenceCount, 1)
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
        let harness = MutationHarness(groups: [existing])

        XCTAssertFalse(harness.service.insert(conflicting))
        XCTAssertEqual(harness.store.groups, [existing])
        XCTAssertEqual(harness.transactionCount, 0)
    }

    private func group(
        _ members: [SumiDomain.SplitMember],
        layoutKind: SumiDomain.SplitLayoutKind = .vertical
    ) -> SumiDomain.SplitGroup? {
        SumiDomain.SplitGroup.make(
            members: members,
            layoutKind: layoutKind
        )
    }
}

@MainActor
private final class MutationHarness {
    let store = SplitGroupStore()
    private(set) var transactionCount = 0
    private(set) var announceCount = 0
    private(set) var publishCount = 0
    private(set) var dirtyCount = 0
    private(set) var persistenceCount = 0

    lazy var service = SplitGroupMutationService(
        store: store,
        withStructuralTransaction: { [weak self] operation in
            self?.transactionCount += 1
            operation()
        },
        beforeStructuralPublication: { action in action() },
        announceChange: { [weak self] in self?.announceCount += 1 },
        requestStructuralPublish: { [weak self] _ in self?.publishCount += 1 },
        markStructurallyDirty: { [weak self] in self?.dirtyCount += 1 },
        schedulePersistence: { [weak self] in self?.persistenceCount += 1 }
    )

    init(groups: [SumiDomain.SplitGroup]) {
        store.replaceAll(with: groups)
    }
}
