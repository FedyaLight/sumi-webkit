import Foundation
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class ProfileRetirementStartupRecoveryTests: XCTestCase {
    func testPreflightCancelsReservedRetirementBeforeAsyncRecovery() throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )

        try ProfileRetirementStartupRecovery.cancelReservedReservations(
            in: fixture.ledger
        )

        XCTAssertTrue(fixture.ledger.records().isEmpty)
        XCTAssertFalse(fixture.ledger.validate(token))
        XCTAssertTrue(fixture.ledger.isReferenceAllowed(fixture.profile.id))
        XCTAssertTrue(try profileExists(fixture.profile.id, in: fixture.container))
    }

    func testMigratingRetirementReloadResumesForwardWithoutReexposingProfile()
        async throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        XCTAssertFalse(try fixture.ledger.cancel(token))
        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )
        var phases: [ProfileRetirementPhase] = []
        var completedSteps: [ProfileRetirementCleanupStep] = []
        let recovery = ProfileRetirementStartupRecovery(
            ledger: reloaded,
            migrateReferences: { record in
                phases.append(record.phase)
                XCTAssertEqual(record.token, token)
                XCTAssertFalse(reloaded.isReferenceAllowed(record.snapshot.id))
            },
            prepareCleanup: { record in
                phases.append(record.phase)
            },
            cleanupFactory: { _ in
                ProfileDeletionCleanupOrchestrator(
                    participants: ProfileRetirementCleanupStep.ordered.map { step in
                        StartupRecoveryCleanupParticipant(step: step) {
                            completedSteps.append(step)
                        }
                    }
                )
            }
        )

        _ = try await recovery.recover()

        XCTAssertEqual(phases, [.migratingReferences, .logicallyDeleted])
        XCTAssertEqual(completedSteps, ProfileRetirementCleanupStep.ordered)
        XCTAssertEqual(reloaded.record(for: token)?.phase, .retired)
        XCTAssertFalse(try profileExists(fixture.profile.id, in: fixture.container))
        XCTAssertTrue(try profileExists(fixture.fallback.id, in: fixture.container))
    }

    func testLogicallyDeletedRetirementRunsEveryCleanupStepAndPersistsRetiredTombstone() async throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        XCTAssertTrue(try fixture.ledger.commitLogicalDeletion(token))
        var completedSteps: [ProfileRetirementCleanupStep] = []

        _ = try await makeRecovery(
            ledger: fixture.ledger,
            completedSteps: { completedSteps.append($0) }
        ).recover()

        XCTAssertEqual(completedSteps, ProfileRetirementCleanupStep.ordered)
        XCTAssertEqual(fixture.ledger.record(for: token)?.phase, .retired)
        XCTAssertEqual(fixture.ledger.record(for: token)?.nextCleanupStep, .completed)
        XCTAssertFalse(try profileExists(fixture.profile.id, in: fixture.container))
    }

    func testCleaningRetirementResumesAtDurableNextStep() async throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        XCTAssertTrue(try fixture.ledger.commitLogicalDeletion(token))
        XCTAssertTrue(try fixture.ledger.beginCleaning(token))
        XCTAssertTrue(try fixture.ledger.completeCleanupStep(.websiteData, using: token))
        XCTAssertTrue(try fixture.ledger.completeCleanupStep(.applicationData, using: token))
        XCTAssertTrue(try fixture.ledger.completeCleanupStep(.favicons, using: token))
        var completedSteps: [ProfileRetirementCleanupStep] = []

        _ = try await makeRecovery(
            ledger: fixture.ledger,
            completedSteps: { completedSteps.append($0) }
        ).recover()

        XCTAssertEqual(
            completedSteps,
            [.permissions, .visitedLinks, .persistentDataStore]
        )
        XCTAssertEqual(fixture.ledger.record(for: token)?.phase, .retired)
    }

    func testCleanupPreparationFailureKeepsLogicalDeletionPending() async throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        XCTAssertTrue(try fixture.ledger.commitLogicalDeletion(token))
        var didConstructCleanup = false
        let recovery = ProfileRetirementStartupRecovery(
            ledger: fixture.ledger,
            prepareCleanup: { record in
                XCTAssertEqual(record.token, token)
                throw TestCleanupFailure()
            },
            cleanupFactory: { _ in
                didConstructCleanup = true
                return ProfileDeletionCleanupOrchestrator(participants: [])
            }
        )

        let report = try await recovery.recover()

        XCTAssertTrue(report.hasDeferredRecovery)
        XCTAssertEqual(report.issues.map(\.profileID), [fixture.profile.id])
        XCTAssertFalse(didConstructCleanup)
        XCTAssertEqual(fixture.ledger.record(for: token)?.phase, .logicallyDeleted)
        XCTAssertEqual(
            fixture.ledger.record(for: token)?.nextCleanupStep,
            .websiteData
        )
    }

    func testCleanupFailureKeepsFailedStepAsDurableResumePoint() async throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        XCTAssertTrue(try fixture.ledger.commitLogicalDeletion(token))
        var firstAttempt: [ProfileRetirementCleanupStep] = []

        let report = try await makeRecovery(
            ledger: fixture.ledger,
            failingAt: .permissions,
            completedSteps: { firstAttempt.append($0) }
        ).recover()

        XCTAssertTrue(report.hasDeferredRecovery)
        XCTAssertEqual(firstAttempt, [.websiteData, .applicationData, .favicons])
        XCTAssertEqual(fixture.ledger.record(for: token)?.phase, .cleaning)
        XCTAssertEqual(
            fixture.ledger.record(for: token)?.nextCleanupStep,
            .permissions
        )

        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )
        var resumed: [ProfileRetirementCleanupStep] = []
        _ = try await makeRecovery(
            ledger: reloaded,
            completedSteps: { resumed.append($0) }
        ).recover()

        XCTAssertEqual(resumed, [.permissions, .visitedLinks, .persistentDataStore])
        XCTAssertEqual(reloaded.record(for: token)?.phase, .retired)

        var noOpSteps: [ProfileRetirementCleanupStep] = []
        _ = try await makeRecovery(
            ledger: reloaded,
            completedSteps: { noOpSteps.append($0) }
        ).recover()
        XCTAssertTrue(noOpSteps.isEmpty)
    }

    func testFaviconFailureRemainsTheDurableResumePointUntilRetrySucceeds() async throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        XCTAssertTrue(try fixture.ledger.commitLogicalDeletion(token))
        var firstAttempt: [ProfileRetirementCleanupStep] = []

        let report = try await makeRecovery(
            ledger: fixture.ledger,
            failingAt: .favicons,
            completedSteps: { firstAttempt.append($0) }
        ).recover()

        XCTAssertTrue(report.hasDeferredRecovery)
        XCTAssertEqual(firstAttempt, [.websiteData, .applicationData])
        XCTAssertEqual(
            fixture.ledger.record(for: token)?.nextCleanupStep,
            .favicons
        )

        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )
        var retry: [ProfileRetirementCleanupStep] = []
        _ = try await makeRecovery(
            ledger: reloaded,
            completedSteps: { retry.append($0) }
        ).recover()

        XCTAssertEqual(
            retry,
            [.favicons, .permissions, .visitedLinks, .persistentDataStore]
        )
        XCTAssertEqual(reloaded.record(for: token)?.phase, .retired)
    }

    func testRetiredTombstoneReplaysRuntimeSealWithoutCleanup() async throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        XCTAssertTrue(try fixture.ledger.commitLogicalDeletion(token))
        XCTAssertTrue(try fixture.ledger.beginCleaning(token))
        for step in ProfileRetirementCleanupStep.ordered {
            XCTAssertTrue(
                try fixture.ledger.completeCleanupStep(step, using: token)
            )
        }
        XCTAssertTrue(try fixture.ledger.markRetired(token))
        var preparedPhases: [ProfileRetirementPhase] = []
        var didConstructCleanup = false
        let recovery = ProfileRetirementStartupRecovery(
            ledger: fixture.ledger,
            prepareCleanup: { record in
                preparedPhases.append(record.phase)
            },
            cleanupFactory: { _ in
                didConstructCleanup = true
                return ProfileDeletionCleanupOrchestrator(participants: [])
            }
        )

        _ = try await recovery.recover()

        XCTAssertEqual(preparedPhases, [.retired])
        XCTAssertFalse(didConstructCleanup)
        XCTAssertEqual(fixture.ledger.record(for: token)?.phase, .retired)
    }

    func testReferenceMigrationFailureDefersOnlyBlockedProfile() async throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        var sanitizedProfileIDs: Set<UUID> = []
        let recovery = ProfileRetirementStartupRecovery(
            ledger: fixture.ledger,
            migrateReferences: { record in
                throw ProfileRetirementStartupRecoveryError
                    .referenceMigrationFailed(profileID: record.snapshot.id)
            },
            sanitizeDeferredReferences: { profileIDs in
                sanitizedProfileIDs = profileIDs
                return true
            },
            cleanupFactory: { _ in
                ProfileDeletionCleanupOrchestrator(participants: [])
            }
        )

        let report = try await recovery.recover()

        XCTAssertTrue(report.hasDeferredRecovery)
        XCTAssertEqual(sanitizedProfileIDs, Set([fixture.profile.id]))
        XCTAssertEqual(fixture.ledger.record(for: token)?.phase, .migratingReferences)
        let lease = try fixture.ledger.beginReferenceMutation(
            to: [fixture.fallback.id]
        )
        XCTAssertTrue(fixture.ledger.endReferenceMutation(lease))
        XCTAssertFalse(fixture.ledger.isReferenceAllowed(fixture.profile.id))
    }

    func testProfileManagerLoadDoesNotDeleteSuppressedRetiringProfile() throws {
        let fixture = try makeFixture()
        let token = try fixture.ledger.reserve(
            profile: fixture.profile,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        let context = ModelContext(fixture.container)
        let fallbackID = fixture.fallback.id
        let fallbackPredicate = #Predicate<ProfileEntity> {
            $0.id == fallbackID
        }
        let fallbackEntity = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<ProfileEntity>(predicate: fallbackPredicate)
            ).first
        )
        fallbackEntity.index = 2
        try context.save()
        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )

        let manager = ProfileManager(
            context: ModelContext(fixture.container),
            profileReferenceAdmission: reloaded
        )

        XCTAssertEqual(manager.profiles.map(\.id), [fixture.fallback.id])
        XCTAssertTrue(try profileExists(fixture.profile.id, in: fixture.container))
        let verificationContext = ModelContext(fixture.container)
        let normalizedFallback = try XCTUnwrap(
            verificationContext.fetch(
                FetchDescriptor<ProfileEntity>(predicate: fallbackPredicate)
            ).first
        )
        XCTAssertEqual(normalizedFallback.index, 0)
    }

    private func makeRecovery(
        ledger: ProfileReferenceAdmissionLedger,
        failingAt: ProfileRetirementCleanupStep? = nil,
        completedSteps: @escaping @MainActor (ProfileRetirementCleanupStep) -> Void
    ) -> ProfileRetirementStartupRecovery {
        ProfileRetirementStartupRecovery(
            ledger: ledger,
            cleanupFactory: { _ in
                ProfileDeletionCleanupOrchestrator(
                    participants: ProfileRetirementCleanupStep.ordered.map { step in
                        StartupRecoveryCleanupParticipant(step: step) {
                            guard step != failingAt else {
                                throw TestCleanupFailure()
                            }
                            completedSteps(step)
                        }
                    }
                )
            }
        )
    }

    private func makeFixture() throws -> StartupRecoveryFixture {
        let container = try ModelContainer(
            for: Schema([ProfileEntity.self, ProfileRetirementEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Retiring")
        let fallback = Profile(name: "Fallback")
        let context = ModelContext(container)
        context.insert(
            ProfileEntity(
                id: profile.id,
                name: profile.name,
                index: 1
            )
        )
        context.insert(
            ProfileEntity(
                id: fallback.id,
                name: fallback.name,
                index: 0
            )
        )
        try context.save()
        return try StartupRecoveryFixture(
            container: container,
            profile: profile,
            fallback: fallback,
            ledger: ProfileReferenceAdmissionLedger(context: ModelContext(container))
        )
    }

    private func profileExists(_ profileID: UUID, in container: ModelContainer) throws -> Bool {
        let context = ModelContext(container)
        let predicate = #Predicate<ProfileEntity> { $0.id == profileID }
        return try context.fetch(
            FetchDescriptor<ProfileEntity>(predicate: predicate)
        ).isEmpty == false
    }
}

@MainActor
private struct StartupRecoveryFixture {
    let container: ModelContainer
    let profile: Profile
    let fallback: Profile
    let ledger: ProfileReferenceAdmissionLedger
}

@MainActor
private final class StartupRecoveryCleanupParticipant: ProfileCleanupParticipant {
    let step: ProfileRetirementCleanupStep
    private let operation: @MainActor () throws -> Void

    init(
        step: ProfileRetirementCleanupStep,
        operation: @escaping @MainActor () throws -> Void
    ) {
        self.step = step
        self.operation = operation
    }

    func cleanup(profileId _: UUID) async throws {
        try operation()
    }
}

private struct TestCleanupFailure: Error {}
