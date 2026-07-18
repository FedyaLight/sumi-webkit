import Foundation
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class ProfileRetirementPersistenceTests: XCTestCase {
    func testUnavailableLedgerFailsClosed() throws {
        let ledger = ProfileReferenceAdmissionLedger.failClosed()
        let profile = Profile(name: "Unavailable")
        XCTAssertFalse(ledger.isReferenceAllowed(profile.id))
        XCTAssertNil(ledger.admitReference(to: profile.id))

        XCTAssertThrowsError(
            try ledger.reserve(profile: profile, fallbackID: UUID())
        ) { error in
            XCTAssertEqual(
                error as? ProfileReferenceAdmissionLedgerError,
                .unavailable
            )
        }
    }

    func testReferenceMutationLeaseSerializesRetirementReservation() throws {
        let fixture = try makeFixture()
        let lease = try fixture.ledger.beginReferenceMutation(
            to: [fixture.profile.id, fixture.fallback.id]
        )

        XCTAssertTrue(fixture.ledger.validate(lease))
        XCTAssertThrowsError(
            try fixture.ledger.reserve(
                profile: fixture.profile,
                fallbackID: fixture.fallback.id
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileReferenceAdmissionLedgerError,
                .mutationInProgress
            )
        }
        XCTAssertTrue(fixture.ledger.endReferenceMutation(lease))

        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(fixture.ledger.validate(token))
    }

    func testNestedReferenceMutationScopesKeepRetirementSealedUntilAllEnd()
        throws {
        let fixture = try makeFixture()
        let profileLease = try fixture.ledger.beginReferenceMutation(
            to: [fixture.profile.id]
        )
        let fallbackLease = try fixture.ledger.beginReferenceMutation(
            to: [fixture.profile.id, fixture.fallback.id]
        )

        XCTAssertFalse(
            fixture.ledger.validate(
                profileLease,
                covers: [fixture.fallback.id]
            )
        )
        XCTAssertTrue(
            fixture.ledger.validate(
                fallbackLease,
                covers: [fixture.profile.id, fixture.fallback.id]
            )
        )
        XCTAssertTrue(fixture.ledger.endReferenceMutation(profileLease))
        XCTAssertFalse(fixture.ledger.endReferenceMutation(profileLease))
        XCTAssertTrue(fixture.ledger.validate(fallbackLease))
        XCTAssertThrowsError(
            try fixture.ledger.reserve(
                profile: fixture.profile,
                fallbackID: fixture.fallback.id
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileReferenceAdmissionLedgerError,
                .mutationInProgress
            )
        }
        XCTAssertTrue(fixture.ledger.endReferenceMutation(fallbackLease))

        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(fixture.ledger.validate(token))
    }

    func testRetirementMigrationMutationLeaseRemainsExclusive() throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        let migrationLease = try fixture.ledger
            .beginRetirementReferenceMigration(to: [fixture.fallback.id])

        XCTAssertThrowsError(
            try fixture.ledger.beginReferenceMutation(
                to: [fixture.fallback.id]
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileReferenceAdmissionLedgerError,
                .mutationInProgress
            )
        }
        XCTAssertThrowsError(
            try fixture.ledger.beginRetirementReferenceMigration(
                to: [fixture.fallback.id]
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileReferenceAdmissionLedgerError,
                .mutationInProgress
            )
        }
        XCTAssertTrue(
            fixture.ledger.endReferenceMutation(migrationLease)
        )
    }

    func testReferenceMutationLeaseRejectsActiveRetirement() throws {
        let fixture = try makeFixture()
        _ = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )

        XCTAssertThrowsError(
            try fixture.ledger.beginReferenceMutation(to: [fixture.fallback.id])
        ) { error in
            XCTAssertEqual(
                error as? ProfileReferenceAdmissionLedgerError,
                .retirementInProgress(fixture.profile.id)
            )
        }
    }

    func testReservationPersistsCanonicalSnapshotAndBlocksReferencesAfterReload() throws {
        let fixture = try makeFixture()
        let receipt = try XCTUnwrap(
            fixture.ledger.admitReference(to: fixture.profile.id)
        )

        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )

        XCTAssertFalse(fixture.ledger.validate(receipt))
        XCTAssertFalse(fixture.ledger.isReferenceAllowed(fixture.profile.id))
        let record = try XCTUnwrap(fixture.ledger.record(for: token))
        XCTAssertEqual(
            record.snapshot,
            ProfileRetirementSnapshot(
                id: fixture.profile.id,
                name: "Persisted name",
                index: 3
            )
        )
        XCTAssertEqual(record.fallbackProfileID, fixture.fallback.id)
        XCTAssertEqual(record.phase, .reserved)
        XCTAssertEqual(record.nextCleanupStep, .websiteData)

        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )
        XCTAssertFalse(reloaded.isReferenceAllowed(fixture.profile.id))
        XCTAssertTrue(reloaded.validate(token))
        XCTAssertEqual(reloaded.record(for: token), record)
    }

    func testCancellationReopensAdmissionWithoutRevivingOldReceiptsOrTokens() throws {
        let fixture = try makeFixture()
        let beforeReservation = try XCTUnwrap(
            fixture.ledger.admitReference(to: fixture.profile.id)
        )
        let staleToken = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.cancel(staleToken))

        let afterCancellation = try XCTUnwrap(
            fixture.ledger.admitReference(to: fixture.profile.id)
        )
        XCTAssertFalse(fixture.ledger.validate(beforeReservation))
        XCTAssertTrue(fixture.ledger.validate(afterCancellation))

        let currentToken = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertNotEqual(currentToken, staleToken)
        XCTAssertFalse(try fixture.ledger.cancel(staleToken))
        XCTAssertFalse(try fixture.ledger.beginCleaning(staleToken))
        XCTAssertTrue(fixture.ledger.validate(currentToken))
        XCTAssertFalse(fixture.ledger.validate(afterCancellation))
    }

    func testReservationRejectsMissingOrRetiringFallbackAndConcurrentRetirement() throws {
        let fixture = try makeFixture()
        let thirdID = UUID()
        let context = fixture.context
        context.insert(
            ProfileEntity(
                id: thirdID,
                name: "Third",
                index: 2
            )
        )
        try context.save()
        let third = Profile(id: thirdID, name: "Third")
        let missingFallbackID = UUID()

        XCTAssertThrowsError(
            try fixture.ledger.reserve(
                profile: fixture.profile,
                fallbackID: missingFallbackID
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileRetirementStoreError,
                .fallbackProfileNotFound(missingFallbackID)
            )
        }

        let currentToken = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertThrowsError(
            try fixture.ledger.reserve(
                profile: third,
                fallbackID: fixture.profile.id
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileRetirementStoreError,
                .fallbackProfileIsRetiring(fixture.profile.id)
            )
        }
        XCTAssertThrowsError(
            try fixture.ledger.reserve(
                profile: third,
                fallbackID: fixture.fallback.id
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileRetirementStoreError,
                .anotherRetirementInProgress(fixture.profile.id)
            )
        }
        XCTAssertTrue(fixture.ledger.validate(currentToken))
    }

    func testLogicalDeletionAndCleanupProgressSurviveLedgerReload() throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )

        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        let committed = try fixture.ledger.commitLogicalDeletion(token)
        XCTAssertTrue(committed)
        XCTAssertNil(try profileEntity(fixture.profile.id, in: fixture.container))
        XCTAssertEqual(fixture.ledger.record(for: token)?.phase, .logicallyDeleted)
        XCTAssertTrue(try fixture.ledger.beginCleaning(token))
        XCTAssertFalse(
            try fixture.ledger.completeCleanupStep(.favicons, using: token)
        )
        XCTAssertTrue(
            try fixture.ledger.completeCleanupStep(.websiteData, using: token)
        )

        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )
        XCTAssertEqual(reloaded.record(for: token)?.phase, .cleaning)
        XCTAssertEqual(
            reloaded.record(for: token)?.nextCleanupStep,
            .applicationData
        )
        XCTAssertTrue(
            try reloaded.completeCleanupStep(.applicationData, using: token)
        )
        XCTAssertTrue(try reloaded.completeCleanupStep(.favicons, using: token))
        XCTAssertEqual(reloaded.record(for: token)?.nextCleanupStep, .permissions)
    }

    func testLogicalDeletionRollsForwardWhenProfileRowIsAlreadyMissing() throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))

        let profileID = token.profileID
        let predicate = #Predicate<ProfileEntity> {
            $0.id == profileID
        }
        let entity = try XCTUnwrap(
            fixture.context.fetch(
                FetchDescriptor<ProfileEntity>(predicate: predicate)
            ).first
        )
        fixture.context.delete(entity)
        try fixture.context.save()

        XCTAssertTrue(try fixture.ledger.commitLogicalDeletion(token))
        XCTAssertEqual(
            fixture.ledger.record(for: token)?.phase,
            .logicallyDeleted
        )
    }

    func testMalformedRetirementIsQuarantinedWithoutDisablingLedger() throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        let profileID = token.profileID
        let predicate = #Predicate<ProfileRetirementEntity> {
            $0.profileID == profileID
        }
        let entity = try XCTUnwrap(
            fixture.context.fetch(
                FetchDescriptor<ProfileRetirementEntity>(predicate: predicate)
            ).first
        )
        entity.phaseRawValue = "future-invalid-phase"
        try fixture.context.save()

        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )

        XCTAssertTrue(reloaded.isAvailable)
        XCTAssertFalse(reloaded.isReferenceAllowed(token.profileID))
        XCTAssertEqual(reloaded.blockedProfileIDs, Set([token.profileID]))
        XCTAssertEqual(
            reloaded.quarantinedRetirements.map(\.profileID),
            [token.profileID]
        )
    }

    func testMissingFallbackPreventsLogicalDeletionAndDurablePhaseAdvance() throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))

        let context = fixture.context
        let fallbackID = fixture.fallback.id
        let predicate = #Predicate<ProfileEntity> { $0.id == fallbackID }
        let fallbackEntity = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<ProfileEntity>(predicate: predicate)
            ).first
        )
        context.delete(fallbackEntity)
        try context.save()

        XCTAssertFalse(try fixture.ledger.commitLogicalDeletion(token))
        XCTAssertNotNil(try profileEntity(fixture.profile.id, in: fixture.container))
        XCTAssertFalse(try fixture.ledger.cancel(token))
        XCTAssertEqual(
            fixture.ledger.record(for: token)?.phase,
            .migratingReferences
        )
        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )
        XCTAssertEqual(reloaded.record(for: token)?.phase, .migratingReferences)
    }

    func testCompletedRetirementRetainsTombstoneAndRejectsUUIDReuse() throws {
        let fixture = try makeFixture()
        let preRetirementReceipt = try XCTUnwrap(
            fixture.ledger.admitReference(to: fixture.profile.id)
        )
        let retiredToken = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(
            try fixture.ledger.beginReferenceMigration(retiredToken)
        )
        XCTAssertTrue(
            try fixture.ledger.commitLogicalDeletion(retiredToken)
        )
        XCTAssertTrue(try fixture.ledger.beginCleaning(retiredToken))
        for step in ProfileRetirementCleanupStep.allCases where step != .completed {
            XCTAssertTrue(
                try fixture.ledger.completeCleanupStep(step, using: retiredToken)
            )
        }
        XCTAssertTrue(try fixture.ledger.markRetired(retiredToken))
        XCTAssertTrue(fixture.ledger.validate(retiredToken))
        XCTAssertEqual(fixture.ledger.record(for: retiredToken)?.phase, .retired)
        XCTAssertFalse(fixture.ledger.isReferenceAllowed(fixture.profile.id))
        XCTAssertFalse(fixture.ledger.validate(preRetirementReceipt))

        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )
        XCTAssertEqual(reloaded.record(for: retiredToken)?.phase, .retired)
        XCTAssertFalse(reloaded.isReferenceAllowed(fixture.profile.id))
        XCTAssertNil(reloaded.admitReference(to: fixture.profile.id))
    }

    private func makeFixture() throws -> Fixture {
        let schema = Schema([
            ProfileEntity.self,
            ProfileRetirementEntity.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profileID = UUID()
        let fallbackID = UUID()
        let context = ModelContext(container)
        context.insert(
            ProfileEntity(
                id: profileID,
                name: "Persisted name",
                index: 3
            )
        )
        context.insert(
            ProfileEntity(
                id: fallbackID,
                name: "Fallback",
                index: 0
            )
        )
        try context.save()

        let ledgerContext = ModelContext(container)
        return try Fixture(
            container: container,
            context: ledgerContext,
            profile: Profile(id: profileID, name: "Runtime name"),
            fallback: Profile(id: fallbackID, name: "Fallback"),
            ledger: ProfileReferenceAdmissionLedger(context: ledgerContext)
        )
    }

    private func profileEntity(
        _ profileID: UUID,
        in container: ModelContainer
    ) throws -> ProfileEntity? {
        let context = ModelContext(container)
        let predicate = #Predicate<ProfileEntity> { $0.id == profileID }
        return try context.fetch(
            FetchDescriptor<ProfileEntity>(predicate: predicate)
        ).first
    }
}

@MainActor
private struct Fixture {
    let container: ModelContainer
    let context: ModelContext
    let profile: Profile
    let fallback: Profile
    let ledger: ProfileReferenceAdmissionLedger
}
