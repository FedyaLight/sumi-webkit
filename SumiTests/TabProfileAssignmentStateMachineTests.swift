import XCTest

@testable import Sumi

@MainActor
final class TabProfileAssignmentStateMachineTests: XCTestCase {
    func testNewIntentInvalidatesEarlierPendingIntent() {
        let transaction = TabProfileAssignmentStateMachine()
        let first = transaction.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: URL(string: "https://first.example")!,
            requiresStructuralPersistence: false
        )
        let second = transaction.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: URL(string: "https://second.example")!,
            requiresStructuralPersistence: true
        )

        XCTAssertFalse(transaction.isCurrent(first))
        XCTAssertTrue(transaction.isCurrent(second))
        XCTAssertGreaterThan(second.revision, first.revision)
    }

    func testCommitChangesCurrentProfileAndSettlesPendingIntent() {
        let transaction = TabProfileAssignmentStateMachine()
        let desiredProfileID = UUID()
        let intent = transaction.begin(
            desiredProfileID: desiredProfileID,
            resolvedProfileID: desiredProfileID,
            targetURL: URL(string: "https://commit.example")!,
            requiresStructuralPersistence: true
        )

        XCTAssertTrue(transaction.commit(intent))
        XCTAssertEqual(transaction.currentProfileID, desiredProfileID)
        XCTAssertFalse(transaction.hasUnsettledAssignment)
        XCTAssertFalse(transaction.commit(intent))
    }

    func testStagedIntentRemainsUnsettledUntilPhysicalSettlementFinishes() {
        let transaction = TabProfileAssignmentStateMachine()
        let desiredProfileID = UUID()
        let intent = transaction.begin(
            desiredProfileID: desiredProfileID,
            resolvedProfileID: desiredProfileID,
            targetURL: URL(string: "https://stage.example")!,
            requiresStructuralPersistence: false
        )

        XCTAssertTrue(transaction.stage(intent))
        XCTAssertTrue(transaction.isCurrentStaged(intent))
        XCTAssertTrue(transaction.hasUnsettledAssignment)
        XCTAssertTrue(transaction.finish(intent))
        XCTAssertFalse(transaction.hasUnsettledAssignment)
        XCTAssertEqual(transaction.currentProfileID, desiredProfileID)
    }

    func testRollbackRestoresExactExpectedProfile() {
        let transaction = TabProfileAssignmentStateMachine()
        let originalProfileID = UUID()
        XCTAssertTrue(transaction.replaceCurrentProfileID(originalProfileID))
        let intent = transaction.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: URL(string: "https://rollback.example")!,
            requiresStructuralPersistence: true
        )

        XCTAssertTrue(transaction.stage(intent))
        XCTAssertTrue(transaction.rollback(intent))
        XCTAssertEqual(transaction.currentProfileID, originalProfileID)
        XCTAssertFalse(transaction.hasUnsettledAssignment)
        XCTAssertFalse(transaction.rollback(intent))
    }

    func testExternalProfileChangeInvalidatesPendingIntent() {
        let transaction = TabProfileAssignmentStateMachine()
        let intent = transaction.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: URL(string: "https://stale.example")!,
            requiresStructuralPersistence: false
        )

        XCTAssertTrue(transaction.replaceCurrentProfileID(UUID()))

        XCTAssertFalse(transaction.isCurrent(intent))
        XCTAssertFalse(transaction.stage(intent))
        transaction.abort(intent)
        XCTAssertFalse(transaction.hasUnsettledAssignment)
    }

    func testExternalProfileABAInvalidatesPendingIntentPermanently() {
        let transaction = TabProfileAssignmentStateMachine()
        let originalProfileID = UUID()
        let replacementProfileID = UUID()
        XCTAssertTrue(transaction.replaceCurrentProfileID(originalProfileID))
        let intent = transaction.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: URL(string: "https://aba.example")!,
            requiresStructuralPersistence: false
        )

        XCTAssertTrue(transaction.replaceCurrentProfileID(replacementProfileID))
        XCTAssertTrue(transaction.replaceCurrentProfileID(originalProfileID))

        XCTAssertFalse(transaction.isCurrent(intent))
        XCTAssertFalse(transaction.stage(intent))
        XCTAssertFalse(transaction.hasUnsettledAssignment)
    }

    func testExternalReplacementIsRejectedDuringStagedSettlement() {
        let transaction = TabProfileAssignmentStateMachine()
        let desiredProfileID = UUID()
        let intent = transaction.begin(
            desiredProfileID: desiredProfileID,
            resolvedProfileID: desiredProfileID,
            targetURL: URL(string: "https://settling.example")!,
            requiresStructuralPersistence: false
        )
        XCTAssertTrue(transaction.stage(intent))

        XCTAssertFalse(transaction.replaceCurrentProfileID(UUID()))
        XCTAssertTrue(transaction.isCurrentStaged(intent))
        XCTAssertEqual(transaction.currentProfileID, desiredProfileID)
        XCTAssertTrue(transaction.finish(intent))
    }

    func testSameValueExternalAssignmentTombstonesPendingIntent() {
        let transaction = TabProfileAssignmentStateMachine()
        let profileID = UUID()
        XCTAssertTrue(transaction.replaceCurrentProfileID(profileID))
        let intent = transaction.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: URL(string: "https://same-value.example")!,
            requiresStructuralPersistence: false
        )

        XCTAssertTrue(transaction.replaceCurrentProfileID(profileID))

        XCTAssertFalse(transaction.isCurrent(intent))
        XCTAssertFalse(transaction.hasUnsettledAssignment)
    }

    func testStaleAbortCannotClearNewerPendingIntent() {
        let transaction = TabProfileAssignmentStateMachine()
        let stale = transaction.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: URL(string: "https://stale-abort.example")!,
            requiresStructuralPersistence: false
        )
        let current = transaction.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: URL(string: "https://current.example")!,
            requiresStructuralPersistence: false
        )

        transaction.abort(stale)

        XCTAssertTrue(transaction.isCurrent(current))
        XCTAssertTrue(transaction.hasUnsettledAssignment)
    }

    func testTabProfileSetterFailsClosedDuringStagedSettlement() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let originalProfileID = UUID()
        tab.profileId = originalProfileID
        let desiredProfileID = UUID()
        let intent = tab.profileAssignment.begin(
            desiredProfileID: desiredProfileID,
            resolvedProfileID: desiredProfileID,
            targetURL: tab.url,
            requiresStructuralPersistence: false
        )
        XCTAssertTrue(tab.profileAssignment.stage(intent))

        tab.profileId = UUID()

        XCTAssertEqual(tab.profileId, desiredProfileID)
        XCTAssertTrue(tab.profileAssignment.isCurrentStaged(intent))
        XCTAssertTrue(tab.profileAssignment.finish(intent))
    }
}
