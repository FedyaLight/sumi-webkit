import Foundation

/// Participant in ordered profile-deletion cleanup.
/// Implementations should be idempotent and fail closed (throw on hard errors).
@MainActor
protocol ProfileCleanupParticipant {
    var name: String { get }
    func cleanup(profileId: UUID) async throws
}

/// Runs profile-deletion cleanup participants in registration order.
@MainActor
final class ProfileDeletionCleanupOrchestrator {
    private let participants: [any ProfileCleanupParticipant]

    init(participants: [any ProfileCleanupParticipant]) {
        self.participants = participants
    }

    func cleanup(profileId: UUID) async throws {
        for participant in participants {
            try await participant.cleanup(profileId: profileId)
        }
    }
}

// MARK: - Default participants

/// Clears browsing / website data for the deleted profile via injected closures.
@MainActor
final class BrowsingDataProfileCleanupParticipant: ProfileCleanupParticipant {
    let name = "browsingData"
    private let clearAllData: @MainActor (UUID) async throws -> Void

    init(clearAllData: @escaping @MainActor (UUID) async throws -> Void) {
        self.clearAllData = clearAllData
    }

    func cleanup(profileId: UUID) async throws {
        try await clearAllData(profileId)
    }
}

/// Clears favicon partition for the deleted profile.
@MainActor
final class FaviconProfileCleanupParticipant: ProfileCleanupParticipant {
    let name = "favicon"
    private let clearFaviconPartition: @MainActor (UUID) -> Void

    init(clearFaviconPartition: @escaping @MainActor (UUID) -> Void) {
        self.clearFaviconPartition = clearFaviconPartition
    }

    func cleanup(profileId: UUID) async throws {
        clearFaviconPartition(profileId)
    }
}

/// Removes persisted permission decisions for the deleted profile partition.
@MainActor
final class PermissionProfileCleanupParticipant: ProfileCleanupParticipant {
    let name = "permissions"
    private let resetAllDecisions: @MainActor (UUID) async throws -> Void

    init(resetAllDecisions: @escaping @MainActor (UUID) async throws -> Void) {
        self.resetAllDecisions = resetAllDecisions
    }

    func cleanup(profileId: UUID) async throws {
        try await resetAllDecisions(profileId)
    }
}

/// No-op stub when a cleanup service is not wired yet.
@MainActor
struct StubProfileCleanupParticipant: ProfileCleanupParticipant {
    let name: String

    func cleanup(profileId: UUID) async throws {
        _ = profileId
    }
}
