import XCTest

@testable import Sumi

@MainActor
final class ProfileDeletionCleanupOrchestratorTests: XCTestCase {
    func testCleanupRunsParticipantsInRegistrationOrder() async throws {
        let profileId = UUID()
        let callOrder = CallOrderRecorder()
        let first = SpyProfileCleanupParticipant(name: "first", callOrder: callOrder)
        let second = SpyProfileCleanupParticipant(name: "second", callOrder: callOrder)
        let third = SpyProfileCleanupParticipant(name: "third", callOrder: callOrder)
        let orchestrator = ProfileDeletionCleanupOrchestrator(
            participants: [first, second, third]
        )

        try await orchestrator.cleanup(profileId: profileId)

        XCTAssertEqual(first.cleanupCallCount, 1)
        XCTAssertEqual(second.cleanupCallCount, 1)
        XCTAssertEqual(third.cleanupCallCount, 1)
        XCTAssertEqual(first.cleanedProfileIds, [profileId])
        XCTAssertEqual(second.cleanedProfileIds, [profileId])
        XCTAssertEqual(third.cleanedProfileIds, [profileId])
        XCTAssertEqual(callOrder.names, ["first", "second", "third"])
    }

    func testFailingParticipantStopsSubsequentParticipants() async {
        let profileId = UUID()
        let callOrder = CallOrderRecorder()
        let first = SpyProfileCleanupParticipant(name: "first", callOrder: callOrder)
        let failing = SpyProfileCleanupParticipant(
            name: "failing",
            callOrder: callOrder,
            errorToThrow: SpyProfileCleanupParticipantError.boom
        )
        let later = SpyProfileCleanupParticipant(name: "later", callOrder: callOrder)
        let orchestrator = ProfileDeletionCleanupOrchestrator(
            participants: [first, failing, later]
        )

        do {
            try await orchestrator.cleanup(profileId: profileId)
            XCTFail("Expected cleanup to throw")
        } catch SpyProfileCleanupParticipantError.boom {
            // Expected fail-closed propagation from the orchestrator.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(first.cleanupCallCount, 1)
        XCTAssertEqual(failing.cleanupCallCount, 1)
        XCTAssertEqual(later.cleanupCallCount, 0)
        XCTAssertEqual(callOrder.names, ["first", "failing"])
    }
}

private enum SpyProfileCleanupParticipantError: Error {
    case boom
}

@MainActor
private final class CallOrderRecorder {
    private(set) var names: [String] = []

    func record(_ name: String) {
        names.append(name)
    }
}

@MainActor
private final class SpyProfileCleanupParticipant: ProfileCleanupParticipant {
    let name: String
    private let callOrder: CallOrderRecorder
    private let errorToThrow: Error?
    private(set) var cleanupCallCount = 0
    private(set) var cleanedProfileIds: [UUID] = []

    init(
        name: String,
        callOrder: CallOrderRecorder,
        errorToThrow: Error? = nil
    ) {
        self.name = name
        self.callOrder = callOrder
        self.errorToThrow = errorToThrow
    }

    func cleanup(profileId: UUID) async throws {
        cleanupCallCount += 1
        cleanedProfileIds.append(profileId)
        callOrder.record(name)
        if let errorToThrow {
            throw errorToThrow
        }
    }
}
