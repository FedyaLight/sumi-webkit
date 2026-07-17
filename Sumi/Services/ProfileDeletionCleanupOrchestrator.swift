import Foundation

/// Participant in ordered profile-deletion cleanup.
/// Implementations should be idempotent and fail closed (throw on hard errors).
@MainActor
protocol ProfileCleanupParticipant {
    var step: ProfileRetirementCleanupStep { get }
    func cleanup(profileId: UUID) async throws
}

enum ProfileDeletionCleanupError: Error, Equatable {
    case missingParticipant(ProfileRetirementCleanupStep)
    case invalidStartingStep(ProfileRetirementCleanupStep)
}

/// Runs idempotent cleanup steps from the durable retirement checkpoint.
@MainActor
final class ProfileDeletionCleanupOrchestrator {
    typealias Checkpoint = @MainActor (ProfileRetirementCleanupStep) async throws -> Void

    private let participantsByStep: [
        ProfileRetirementCleanupStep: any ProfileCleanupParticipant
    ]

    init(participants: [any ProfileCleanupParticipant]) {
        participantsByStep = Dictionary(
            uniqueKeysWithValues: participants.map { ($0.step, $0) }
        )
    }

    func cleanup(
        profileId: UUID,
        startingAt startingStep: ProfileRetirementCleanupStep,
        checkpoint: Checkpoint
    ) async throws {
        guard startingStep != .completed,
              let startIndex = ProfileRetirementCleanupStep.ordered.firstIndex(
                  of: startingStep
              ) else {
            if startingStep == .completed { return }
            throw ProfileDeletionCleanupError.invalidStartingStep(startingStep)
        }

        for index in startIndex..<ProfileRetirementCleanupStep.ordered.count {
            let step = ProfileRetirementCleanupStep.ordered[index]
            guard let participant = participantsByStep[step] else {
                throw ProfileDeletionCleanupError.missingParticipant(step)
            }
            try await participant.cleanup(profileId: profileId)
            try await checkpoint(step)
        }
    }
}

// MARK: - Default participants

/// Clears browsing / website data for the deleted profile via injected closures.
@MainActor
final class BrowsingDataProfileCleanupParticipant: ProfileCleanupParticipant {
    let step = ProfileRetirementCleanupStep.websiteData
    private let clearAllData: @MainActor (UUID) async throws -> Void

    init(clearAllData: @escaping @MainActor (UUID) async throws -> Void) {
        self.clearAllData = clearAllData
    }

    func cleanup(profileId: UUID) async throws {
        try await clearAllData(profileId)
    }
}

/// Removes browser-owned private data that is keyed by the retired profile.
@MainActor
final class ApplicationDataProfileCleanupParticipant: ProfileCleanupParticipant {
    let step = ProfileRetirementCleanupStep.applicationData
    private let clearApplicationData: @MainActor (UUID) async throws -> Void

    init(clearApplicationData: @escaping @MainActor (UUID) async throws -> Void) {
        self.clearApplicationData = clearApplicationData
    }

    func cleanup(profileId: UUID) async throws {
        try await clearApplicationData(profileId)
    }
}

/// Clears favicon partition for the deleted profile.
@MainActor
final class FaviconProfileCleanupParticipant: ProfileCleanupParticipant {
    let step = ProfileRetirementCleanupStep.favicons
    private let clearFaviconPartition: @MainActor (UUID) throws -> Void

    init(clearFaviconPartition: @escaping @MainActor (UUID) throws -> Void) {
        self.clearFaviconPartition = clearFaviconPartition
    }

    func cleanup(profileId: UUID) async throws {
        try clearFaviconPartition(profileId)
    }
}

/// Removes persisted permission decisions for the deleted profile partition.
@MainActor
final class PermissionProfileCleanupParticipant: ProfileCleanupParticipant {
    let step = ProfileRetirementCleanupStep.permissions
    private let resetAllDecisions: @MainActor (UUID) async throws -> Void

    init(resetAllDecisions: @escaping @MainActor (UUID) async throws -> Void) {
        self.resetAllDecisions = resetAllDecisions
    }

    func cleanup(profileId: UUID) async throws {
        try await resetAllDecisions(profileId)
    }
}

@MainActor
final class VisitedLinksProfileCleanupParticipant: ProfileCleanupParticipant {
    let step = ProfileRetirementCleanupStep.visitedLinks
    private let discardStore: @MainActor (UUID) -> Void

    init(discardStore: @escaping @MainActor (UUID) -> Void) {
        self.discardStore = discardStore
    }

    func cleanup(profileId: UUID) async throws {
        discardStore(profileId)
    }
}

@MainActor
final class PersistentWebsiteDataStoreCleanupParticipant: ProfileCleanupParticipant {
    let step = ProfileRetirementCleanupStep.persistentDataStore
    private let removeDataStore: @MainActor (UUID) async throws -> Void

    init(removeDataStore: @escaping @MainActor (UUID) async throws -> Void) {
        self.removeDataStore = removeDataStore
    }

    func cleanup(profileId: UUID) async throws {
        try await removeDataStore(profileId)
    }
}
