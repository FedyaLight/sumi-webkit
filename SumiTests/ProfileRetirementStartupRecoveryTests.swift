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

        try await recovery.recover()

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

        try await makeRecovery(
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

        try await makeRecovery(
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

        do {
            try await recovery.recover()
            XCTFail("Expected runtime cleanup preparation to fail closed")
        } catch is TestCleanupFailure {}

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

        do {
            try await makeRecovery(
                ledger: fixture.ledger,
                failingAt: .permissions,
                completedSteps: { firstAttempt.append($0) }
            ).recover()
            XCTFail("Expected cleanup failure to keep startup recovery closed")
        } catch is TestCleanupFailure {}

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
        try await makeRecovery(
            ledger: reloaded,
            completedSteps: { resumed.append($0) }
        ).recover()

        XCTAssertEqual(resumed, [.permissions, .visitedLinks, .persistentDataStore])
        XCTAssertEqual(reloaded.record(for: token)?.phase, .retired)

        var noOpSteps: [ProfileRetirementCleanupStep] = []
        try await makeRecovery(
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

        do {
            try await makeRecovery(
                ledger: fixture.ledger,
                failingAt: .favicons,
                completedSteps: { firstAttempt.append($0) }
            ).recover()
            XCTFail("Expected favicon cleanup failure to keep recovery closed")
        } catch is TestCleanupFailure {}

        XCTAssertEqual(firstAttempt, [.websiteData, .applicationData])
        XCTAssertEqual(
            fixture.ledger.record(for: token)?.nextCleanupStep,
            .favicons
        )

        let reloaded = try ProfileReferenceAdmissionLedger(
            context: ModelContext(fixture.container)
        )
        var retry: [ProfileRetirementCleanupStep] = []
        try await makeRecovery(
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

        try await recovery.recover()

        XCTAssertEqual(preparedPhases, [.retired])
        XCTAssertFalse(didConstructCleanup)
        XCTAssertEqual(fixture.ledger.record(for: token)?.phase, .retired)
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
        let profile = Profile(name: "Retiring", icon: "Retiring icon")
        let fallback = Profile(name: "Fallback", icon: "Fallback icon")
        let context = ModelContext(container)
        context.insert(
            ProfileEntity(
                id: profile.id,
                name: profile.name,
                icon: profile.icon,
                index: 1
            )
        )
        context.insert(
            ProfileEntity(
                id: fallback.id,
                name: fallback.name,
                icon: fallback.icon,
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
