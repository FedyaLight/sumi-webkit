import Foundation
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class ProfileReferenceAdmittedModelTransactionTests: XCTestCase {
    func testReservationAfterStagePreservesExactRollbackEvidence() throws {
        let fixture = try makeFixture()
        let receipt = try XCTUnwrap(
            fixture.ledger.admitReference(to: fixture.profile.id)
        )
        var isStaged = false
        var didRollback = false
        let model = TestWebViewReplacementModelTransaction(
            stage: {
                isStaged = true
                _ = try fixture.ledger.reserve(
                    profile: fixture.profile,
                    fallbackID: fixture.fallback.id
                )
            },
            stagedModelIsExact: { isStaged },
            rollback: {
                didRollback = true
                isStaged = false
            }
        )
        let admitted = ProfileReferenceAdmittedModelTransaction(
            model: model,
            admissions: fixture.ledger,
            receipt: receipt
        )

        try admitted.stage()

        XCTAssertTrue(admitted.stagedModelIsExact())
        XCTAssertFalse(admitted.canClaimTerminalModel())
        try admitted.rollback()
        XCTAssertTrue(didRollback)
    }

    func testModelOnlySettlementRollsBackWhenReservationInvalidatesStage() throws {
        let fixture = try makeFixture()
        let receipt = try XCTUnwrap(
            fixture.ledger.admitReference(to: fixture.profile.id)
        )
        var isStaged = false
        var didPublishRollback = false
        let model = TestWebViewReplacementModelTransaction(
            stage: {
                isStaged = true
                _ = try fixture.ledger.reserve(
                    profile: fixture.profile,
                    fallbackID: fixture.fallback.id
                )
            },
            stagedModelIsExact: { isStaged },
            rollback: { isStaged = false },
            publishRollback: { didPublishRollback = true }
        )
        let admitted = ProfileReferenceAdmittedModelTransaction(
            model: model,
            admissions: fixture.ledger,
            receipt: receipt
        )

        let outcome = ProfileTransitionModelOnlySettlement.execute(
            .transaction(admitted)
        )

        XCTAssertEqual(outcome, .rolledBackCommitValidation)
        XCTAssertTrue(didPublishRollback)
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Schema([
                ProfileEntity.self,
                ProfileRetirementEntity.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Retiring")
        let fallback = Profile(name: "Fallback")
        let context = ModelContext(container)
        context.insert(
            ProfileEntity(
                id: profile.id,
                name: profile.name,
                index: 0
            )
        )
        context.insert(
            ProfileEntity(
                id: fallback.id,
                name: fallback.name,
                index: 1
            )
        )
        try context.save()
        return try Fixture(
            profile: profile,
            fallback: fallback,
            ledger: ProfileReferenceAdmissionLedger(context: context)
        )
    }
}

@MainActor
private struct Fixture {
    let profile: Profile
    let fallback: Profile
    let ledger: ProfileReferenceAdmissionLedger
}
