import Combine
import Foundation

enum SumiBoostStoreError: LocalizedError, Equatable, Sendable {
    case unboostableURL
    case missingProfile
    case missingBoost
    case invalidImport
    case moduleDisabled
    case profileCleanupStoreUnreadable
    case profileRetired

    var errorDescription: String? {
        switch self {
        case .unboostableURL:
            return "This page cannot use Boosts."
        case .missingProfile:
            return "A browsing profile is required for Boosts."
        case .missingBoost:
            return "The selected Boost no longer exists."
        case .invalidImport:
            return "The selected file is not a valid Sumi Boost."
        case .moduleDisabled:
            return "Boosts are disabled."
        case .profileCleanupStoreUnreadable:
            return "Stored Boost data could not be read safely for profile cleanup."
        case .profileRetired:
            return "The browsing profile has been retired."
        }
    }
}

@MainActor
final class SumiBoostStore: ObservableObject {
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    private let diskWorker: SumiBoostDiskWorker
    private var entries: [SumiBoostDomainKey: SumiBoostDomainEntry] = [:]
    private var didLoad = false
    private var loadFailure: SumiBoostStoreError?
    private var retiredProfileIDs: Set<UUID> = []
    private let changesSubject = PassthroughSubject<Void, Never>()
    // Debounced persistence: editor edits (dot drag, sliders) mutate the store
    // many times per second; writing the entire boosts.json on every tick is
    // wasteful. A pending write is scheduled and re-scheduled, coalescing a
    // burst of edits into a single disk write. Lifecycle events (create,
    // delete, import, discard, flush) bypass the debounce and write now.
    private var pendingWriteTask: Task<Void, Never>?
    private var persistenceRevision: UInt64 = 0
    private static let writeDebounceNanoseconds: UInt64 = 300_000_000

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    func prefetch() {
        diskWorker.prefetch()
    }

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger
    ) {
        let rootDirectory = rootDirectory
            ?? SumiBoostDiskWorker.defaultRootDirectory(fileManager: fileManager)
        diskWorker = SumiBoostDiskWorker(
            rootDirectory: rootDirectory,
            fileManager: fileManager
        )
        self.profileReferenceAdmission = profileReferenceAdmission
    }

    func boosts(for url: URL?, profileId: UUID?) -> [SumiBoost] {
        guard let key = SumiBoostURLPolicy.key(for: url, profileId: profileId) else { return [] }
        guard acceptsReference(to: key.profileId) else { return [] }
        loadIfNeeded()
        return entries[key]?.boosts ?? []
    }

    func changedBoosts(for url: URL?, profileId: UUID?) -> [SumiBoost] {
        boosts(for: url, profileId: profileId)
            .filter(\.data.changeWasMade)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func activeBoost(for url: URL?, profileId: UUID?) -> SumiBoost? {
        guard let key = SumiBoostURLPolicy.key(for: url, profileId: profileId) else { return nil }
        guard acceptsReference(to: key.profileId) else { return nil }
        loadIfNeeded()
        guard let entry = entries[key],
              let activeBoostId = entry.activeBoostId
        else {
            return nil
        }
        return entry.boosts.first { $0.id == activeBoostId }
    }

    func activeBoostId(for url: URL?, profileId: UUID?) -> UUID? {
        guard let key = SumiBoostURLPolicy.key(for: url, profileId: profileId) else { return nil }
        guard acceptsReference(to: key.profileId) else { return nil }
        loadIfNeeded()
        return entries[key]?.activeBoostId
    }

    @discardableResult
    func createDraft(
        for url: URL?,
        profileId: UUID?,
        isEphemeral: Bool
    ) throws -> SumiBoost {
        guard let key = SumiBoostURLPolicy.key(for: url, profileId: profileId) else {
            throw profileId == nil ? SumiBoostStoreError.missingProfile : SumiBoostStoreError.unboostableURL
        }
        guard acceptsReference(to: key.profileId) else {
            throw SumiBoostStoreError.profileRetired
        }

        loadIfNeeded()
        let boost = SumiBoost(profileId: key.profileId, host: key.host)
        var entry = entries[key] ?? SumiBoostDomainEntry(
            profileId: key.profileId,
            host: key.host,
            activeBoostId: nil,
            boosts: [],
            isEphemeral: isEphemeral
        )
        entry.isEphemeral = entry.isEphemeral || isEphemeral
        entry.boosts.insert(boost, at: 0)
        entry.activeBoostId = boost.id
        entries[key] = entry
        persistImmediately(isEphemeral: entry.isEphemeral)
        notifyChanged()
        return boost
    }

    @discardableResult
    func updateBoost(
        id: UUID,
        profileId: UUID,
        host: String,
        isEphemeral: Bool,
        markChanged: Bool = true,
        mutate: (inout SumiBoostData) -> Void
    ) throws -> SumiBoost {
        guard acceptsReference(to: profileId) else {
            throw SumiBoostStoreError.profileRetired
        }
        let key = SumiBoostDomainKey(profileId: profileId, host: normalizedHost(host))
        loadIfNeeded()
        guard var entry = entries[key],
              let index = entry.boosts.firstIndex(where: { $0.id == id })
        else {
            throw SumiBoostStoreError.missingBoost
        }

        mutate(&entry.boosts[index].data)
        if markChanged {
            entry.boosts[index].data.changeWasMade = true
        }
        entry.boosts[index].updatedAt = Date()
        entry.isEphemeral = entry.isEphemeral || isEphemeral
        entries[key] = entry
        persistIfNeeded(isEphemeral: entry.isEphemeral)
        notifyChanged()
        return entry.boosts[index]
    }

    func toggleActiveBoost(
        _ boost: SumiBoost,
        isEphemeral: Bool
    ) {
        guard acceptsReference(to: boost.profileId) else { return }
        let key = SumiBoostDomainKey(profileId: boost.profileId, host: normalizedHost(boost.host))
        loadIfNeeded()
        guard var entry = entries[key] else { return }
        entry.activeBoostId = entry.activeBoostId == boost.id ? nil : boost.id
        entry.isEphemeral = entry.isEphemeral || isEphemeral
        entries[key] = entry
        persistIfNeeded(isEphemeral: entry.isEphemeral)
        notifyChanged()
    }

    func deleteBoost(
        _ boost: SumiBoost,
        isEphemeral: Bool
    ) {
        guard acceptsReference(to: boost.profileId) else { return }
        let key = SumiBoostDomainKey(profileId: boost.profileId, host: normalizedHost(boost.host))
        loadIfNeeded()
        guard var entry = entries[key] else { return }
        entry.boosts.removeAll { $0.id == boost.id }
        if entry.activeBoostId == boost.id {
            entry.activeBoostId = nil
        }
        entry.isEphemeral = entry.isEphemeral || isEphemeral
        if entry.boosts.isEmpty {
            entries.removeValue(forKey: key)
        } else {
            entries[key] = entry
        }
        persistImmediately(isEphemeral: entry.isEphemeral)
        notifyChanged()
    }

    func discardUnchangedDraft(_ boost: SumiBoost) {
        guard !boost.data.changeWasMade else { return }
        deleteBoost(boost, isEphemeral: false)
    }

    func deleteProfileData(profileID: UUID) async throws {
        retiredProfileIDs.insert(profileID)
        loadIfNeeded()
        if let loadFailure { throw loadFailure }

        let targetEntries = entries.filter { $0.key.profileId == profileID }
        guard !targetEntries.isEmpty else { return }

        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        let retainedEntries = entries.filter { $0.key.profileId != profileID }
        entries = retainedEntries
        try await diskWorker.commit(retainedEntries)
        notifyChanged()
    }

    func exportData(for boost: SumiBoost) async throws -> Data {
        try await diskWorker.exportData(for: boost)
    }

    @discardableResult
    func importBoost(
        from data: Data,
        for url: URL?,
        profileId: UUID?,
        isEphemeral: Bool
    ) async throws -> SumiBoost {
        guard let key = SumiBoostURLPolicy.key(for: url, profileId: profileId) else {
            throw profileId == nil ? SumiBoostStoreError.missingProfile : SumiBoostStoreError.unboostableURL
        }
        guard acceptsReference(to: key.profileId) else {
            throw SumiBoostStoreError.profileRetired
        }

        let importedData = try await diskWorker.decodeImportedBoostData(from: data)

        loadIfNeeded()
        var data = importedData
        data.changeWasMade = true
        let boost = SumiBoost(
            profileId: key.profileId,
            host: key.host,
            data: data
        )
        var entry = entries[key] ?? SumiBoostDomainEntry(
            profileId: key.profileId,
            host: key.host,
            activeBoostId: nil,
            boosts: [],
            isEphemeral: isEphemeral
        )
        entry.isEphemeral = entry.isEphemeral || isEphemeral
        entry.boosts.insert(boost, at: 0)
        entry.activeBoostId = boost.id
        entries[key] = entry
        persistImmediately(isEphemeral: entry.isEphemeral)
        notifyChanged()
        return boost
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        let interval = PerformanceTrace.beginInterval("Boost.load")
        let result = diskWorker.loadedResult()
        PerformanceTrace.endInterval("Boost.load", interval)
        entries = result.entries
        loadFailure = result.failure
    }

    /// Schedules a debounced disk write. Coalesces a burst of editor edits
    /// (dot drag, sliders) into a single `persist()` so the main thread isn't
    /// blocked re-encoding and atomically rewriting boosts.json on every tick.
    private func persistIfNeeded(isEphemeral: Bool) {
        guard !isEphemeral else { return }
        schedulePersist()
    }

    /// Enqueues immediately, cancelling any debounced write. Call from lifecycle
    /// events (create/delete/import/discard) and when the editor closes, so a
    /// draft or final state is durable without waiting for the debounce.
    private func persistImmediately(isEphemeral: Bool) {
        guard !isEphemeral else { return }
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        persist()
    }

    /// Public flush hook for the module: ensures any debounced write lands on
    /// disk now (used when the editor closes).
    func flushPendingWrites() async {
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        persist()
        await diskWorker.flush()
    }

    private func schedulePersist() {
        pendingWriteTask?.cancel()
        pendingWriteTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.writeDebounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.pendingWriteTask = nil
                self?.persist()
            }
        }
    }

    private func persist() {
        let source = entries
        persistenceRevision &+= 1
        diskWorker.enqueuePersist(source, revision: persistenceRevision)
    }

    private func notifyChanged() {
        changesSubject.send(())
    }

    private func normalizedHost(_ host: String) -> String {
        Self.normalizedHostValue(host)
    }

    nonisolated private static func normalizedHostValue(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private func acceptsReference(to profileID: UUID) -> Bool {
        retiredProfileIDs.contains(profileID) == false
            && profileReferenceAdmission.isReferenceAllowed(profileID)
    }
}
