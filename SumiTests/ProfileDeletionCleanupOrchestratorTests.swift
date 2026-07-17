import XCTest

@testable import Sumi

@MainActor
final class ProfileDeletionCleanupOrchestratorTests: XCTestCase {
    func testCleanupUsesDurableStepOrderAndCheckpointsNextStep() async throws {
        let profileID = UUID()
        let calls = CleanupCallRecorder()
        let orchestrator = makeOrchestrator(calls: calls)
        var checkpoints: [ProfileRetirementCleanupStep] = []

        try await orchestrator.cleanup(
            profileId: profileID,
            startingAt: .websiteData,
            checkpoint: { checkpoints.append($0) }
        )

        XCTAssertEqual(calls.steps, ProfileRetirementCleanupStep.ordered)
        XCTAssertEqual(calls.profileIDs, Array(
            repeating: profileID,
            count: ProfileRetirementCleanupStep.ordered.count
        ))
        XCTAssertEqual(
            checkpoints,
            ProfileRetirementCleanupStep.ordered
        )
    }

    func testCleanupResumesAtPersistedStep() async throws {
        let calls = CleanupCallRecorder()
        let orchestrator = makeOrchestrator(calls: calls)
        var checkpoints: [ProfileRetirementCleanupStep] = []

        try await orchestrator.cleanup(
            profileId: UUID(),
            startingAt: .permissions,
            checkpoint: { checkpoints.append($0) }
        )

        XCTAssertEqual(
            calls.steps,
            [.permissions, .visitedLinks, .persistentDataStore]
        )
        XCTAssertEqual(
            checkpoints,
            [.permissions, .visitedLinks, .persistentDataStore]
        )
    }

    func testFailureDoesNotCheckpointOrRunLaterSteps() async {
        let calls = CleanupCallRecorder()
        let orchestrator = makeOrchestrator(
            calls: calls,
            failingAt: .permissions
        )
        var checkpoints: [ProfileRetirementCleanupStep] = []

        do {
            try await orchestrator.cleanup(
                profileId: UUID(),
                startingAt: .websiteData,
                checkpoint: { checkpoints.append($0) }
            )
            XCTFail("Expected cleanup to throw")
        } catch CleanupParticipantError.boom {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            calls.steps,
            [.websiteData, .applicationData, .favicons, .permissions]
        )
        XCTAssertEqual(
            checkpoints,
            [.websiteData, .applicationData, .favicons]
        )
    }

    func testApplicationDataFailureKeepsApplicationDataAsRetryPoint() async {
        let calls = CleanupCallRecorder()
        let orchestrator = makeOrchestrator(
            calls: calls,
            failingAt: .applicationData
        )
        var checkpoints: [ProfileRetirementCleanupStep] = []

        do {
            try await orchestrator.cleanup(
                profileId: UUID(),
                startingAt: .websiteData,
                checkpoint: { checkpoints.append($0) }
            )
            XCTFail("Expected application-data cleanup to throw")
        } catch CleanupParticipantError.boom {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(calls.steps, [.websiteData, .applicationData])
        XCTAssertEqual(checkpoints, [.websiteData])
    }

    func testMissingParticipantFailsClosed() async {
        let calls = CleanupCallRecorder()
        let participants = ProfileRetirementCleanupStep.ordered
            .filter { $0 != .permissions }
            .map { CleanupParticipant(step: $0, calls: calls) }
        let orchestrator = ProfileDeletionCleanupOrchestrator(
            participants: participants
        )

        do {
            try await orchestrator.cleanup(
                profileId: UUID(),
                startingAt: .websiteData,
                checkpoint: { _ in }
            )
            XCTFail("Expected cleanup to reject a missing participant")
        } catch let error as ProfileDeletionCleanupError {
            XCTAssertEqual(error, .missingParticipant(.permissions))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(calls.steps, [.websiteData, .applicationData, .favicons])
    }

    private func makeOrchestrator(
        calls: CleanupCallRecorder,
        failingAt failingStep: ProfileRetirementCleanupStep? = nil
    ) -> ProfileDeletionCleanupOrchestrator {
        ProfileDeletionCleanupOrchestrator(
            participants: ProfileRetirementCleanupStep.ordered.reversed().map {
                CleanupParticipant(
                    step: $0,
                    calls: calls,
                    error: $0 == failingStep ? CleanupParticipantError.boom : nil
                )
            }
        )
    }
}

private enum CleanupParticipantError: Error {
    case boom
}

@MainActor
private final class CleanupCallRecorder {
    private(set) var steps: [ProfileRetirementCleanupStep] = []
    private(set) var profileIDs: [UUID] = []

    func record(step: ProfileRetirementCleanupStep, profileID: UUID) {
        steps.append(step)
        profileIDs.append(profileID)
    }
}

@MainActor
private final class CleanupParticipant: ProfileCleanupParticipant {
    let step: ProfileRetirementCleanupStep
    private let calls: CleanupCallRecorder
    private let error: Error?

    init(
        step: ProfileRetirementCleanupStep,
        calls: CleanupCallRecorder,
        error: Error? = nil
    ) {
        self.step = step
        self.calls = calls
        self.error = error
    }

    func cleanup(profileId: UUID) async throws {
        calls.record(step: step, profileID: profileId)
        if let error { throw error }
    }
}
