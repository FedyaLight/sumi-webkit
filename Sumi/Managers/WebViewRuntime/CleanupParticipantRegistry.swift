import Foundation

/// Registry of non-Tab WebKit runtimes that share profile website data
/// stores. Participants are quiesced after admission closes and before any
/// storage mutation starts.
@MainActor
final class CleanupParticipantRegistry {
    struct ParticipantID: Hashable, Sendable {
        let rawValue: String

        static let extensionRuntime = Self(rawValue: "extension-runtime")
    }

    typealias Quiescer = @MainActor (Set<UUID>) async -> Bool

    private var quiescers: [ParticipantID: Quiescer] = [:]

    func register(
        _ participantID: ParticipantID,
        quiescer: @escaping Quiescer
    ) {
        quiescers[participantID] = quiescer
    }

    func unregister(_ participantID: ParticipantID) {
        quiescers.removeValue(forKey: participantID)
    }

    func quiesce(profileIDs: Set<UUID>) async -> Bool {
        for participantID in quiescers.keys.sorted(by: {
            $0.rawValue < $1.rawValue
        }) {
            guard let quiescer = quiescers[participantID],
                  await quiescer(profileIDs) else {
                return false
            }
        }
        return true
    }

    func removeAll() {
        quiescers.removeAll()
    }
}
