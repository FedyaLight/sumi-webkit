import Foundation

/// Keeps rebuildable HTTP caches bounded without weakening WebsiteDataStore
/// isolation. Size observation is optional; every deletion remains public
/// WebKit API work supplied by the caller.
@MainActor
enum SumiHTTPDiskCacheBudget {
    static let targetBytes: UInt64 = 1_073_741_824
    private static let pressureBytes = targetBytes + targetBytes / 20
    private static let observationInterval: TimeInterval = 24 * 60 * 60
    private static let documentKey =
        "local-installation-storage.http-disk-cache-budget.v1"

    struct Observation: Codable, Equatable {
        let profileID: UUID
        let bytes: UInt64
        let observedAt: Date
    }

    struct Activation: Codable, Equatable {
        let profileID: UUID
        let activatedAt: Date
    }

    private struct State: Codable {
        var observations: [Observation] = []
        var activations: [Activation] = []
    }

    static func recordActivation(
        profileID: UUID?,
        database: SumiDatabase,
        now: Date = Date()
    ) {
        guard let profileID else { return }
        do {
            var state = try loadState(database: database)
            state.activations.removeAll { $0.profileID == profileID }
            state.activations.append(
                Activation(profileID: profileID, activatedAt: now)
            )
            try save(state, database: database)
        } catch {
            RuntimeDiagnostics.emit(
                "[StorageMaintenance] Could not record profile activity: \(error)"
            )
        }
    }

    @discardableResult
    static func runIfNeeded(
        profiles: [Profile],
        foregroundProfileID: @escaping @MainActor () -> UUID?,
        database: SumiDatabase,
        now: Date = Date(),
        observe: @escaping @MainActor (Profile) async -> UInt64?,
        clearDiskCache: @escaping @MainActor (Profile) async -> Bool
    ) async throws -> [UUID] {
        let regularProfiles = profiles.filter { $0.isEphemeral == false }
        let liveProfileIDs = Set(regularProfiles.map(\.id))
        var state = try loadState(database: database)
        normalize(&state, liveProfileIDs: liveProfileIDs)

        guard regularProfiles.isEmpty == false else {
            try save(state, database: database)
            return []
        }

        guard observationsAreStale(
            state.observations,
            profileIDs: liveProfileIDs,
            now: now
        )
        else {
            try save(state, database: database)
            return []
        }

        var sizes: [UUID: UInt64] = [:]
        for profile in regularProfiles {
            guard let bytes = await observe(profile) else {
                return []
            }
            sizes[profile.id] = bytes
        }

        guard let initialTotal = totalBytes(sizes) else {
            return []
        }

        var clearedProfileIDs: [UUID] = []
        if initialTotal > pressureBytes {
            let activations = latestActivations(state.activations)
            let candidates = regularProfiles
                .filter { $0.id != foregroundProfileID() }
                .sorted {
                    let leftActivation = activations[$0.id] ?? .distantPast
                    let rightActivation = activations[$1.id] ?? .distantPast
                    if leftActivation != rightActivation {
                        return leftActivation < rightActivation
                    }
                    let leftBytes = sizes[$0.id] ?? 0
                    let rightBytes = sizes[$1.id] ?? 0
                    if leftBytes != rightBytes {
                        return leftBytes > rightBytes
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }

            for profile in candidates {
                guard totalBytes(sizes).map({ $0 > targetBytes }) == true else {
                    break
                }
                guard foregroundProfileID() != profile.id else { continue }

                guard await clearDiskCache(profile) else {
                    return clearedProfileIDs
                }
                guard let bytes = await observe(profile) else {
                    return clearedProfileIDs
                }
                sizes[profile.id] = bytes
                clearedProfileIDs.append(profile.id)
            }
        }

        state.observations = regularProfiles.compactMap { profile in
            guard let bytes = sizes[profile.id] else { return nil }
            return Observation(
                profileID: profile.id,
                bytes: bytes,
                observedAt: now
            )
        }
        try save(state, database: database)

        if clearedProfileIDs.isEmpty == false {
            RuntimeDiagnostics.emit(
                "[StorageMaintenance] Cleared HTTP DiskCache for \(clearedProfileIDs.count) inactive profile(s)"
            )
        }
        return clearedProfileIDs
    }

    private static func observationsAreStale(
        _ observations: [Observation],
        profileIDs: Set<UUID>,
        now: Date
    ) -> Bool {
        guard observations.count == profileIDs.count,
              Set(observations.map(\.profileID)) == profileIDs
        else {
            return true
        }
        let staleBefore = now.addingTimeInterval(-observationInterval)
        return observations.contains { $0.observedAt < staleBefore }
    }

    private static func totalBytes(_ sizes: [UUID: UInt64]) -> UInt64? {
        var total: UInt64 = 0
        for size in sizes.values {
            let addition = total.addingReportingOverflow(size)
            guard addition.overflow == false else { return nil }
            total = addition.partialValue
        }
        return total
    }

    private static func normalize(
        _ state: inout State,
        liveProfileIDs: Set<UUID>
    ) {
        state.observations.removeAll {
            liveProfileIDs.contains($0.profileID) == false
        }
        state.activations.removeAll {
            liveProfileIDs.contains($0.profileID) == false
        }
    }

    private static func latestActivations(
        _ activations: [Activation]
    ) -> [UUID: Date] {
        activations.reduce(into: [:]) { result, activation in
            guard result[activation.profileID, default: .distantPast]
                < activation.activatedAt
            else {
                return
            }
            result[activation.profileID] = activation.activatedAt
        }
    }

    private static func loadState(database: SumiDatabase) throws -> State {
        try database.read { connection in
            guard let data = try connection.documents.data(forKey: documentKey)
            else {
                return State()
            }
            do {
                return try JSONDecoder().decode(State.self, from: data)
            } catch {
                RuntimeDiagnostics.emit(
                    "[StorageMaintenance] Discarded invalid HTTP DiskCache budget state: \(error)"
                )
                return State()
            }
        }
    }

    private static func save(
        _ state: State,
        database: SumiDatabase
    ) throws {
        try database.transaction {
            try $0.documents.save(state, forKey: documentKey)
        }
    }
}
