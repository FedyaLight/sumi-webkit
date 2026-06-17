import Combine
import Foundation

enum SumiBoostStoreError: LocalizedError {
    case unboostableURL
    case missingProfile
    case missingBoost
    case invalidImport

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
        }
    }
}

@MainActor
final class SumiBoostStore: ObservableObject {
    static let shared = SumiBoostStore()

    private struct DiskState: Codable {
        var domains: [DiskDomainEntry]
    }

    private struct DiskDomainEntry: Codable {
        var profileId: UUID
        var host: String
        var activeBoostId: UUID?
        var boosts: [DiskBoost]
    }

    private struct DiskBoost: Codable {
        var id: UUID
        var profileId: UUID
        var host: String
        var data: SumiBoostData
        var customCSSFileName: String?
        var createdAt: Date
        var updatedAt: Date
    }

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private var entries: [SumiBoostDomainKey: SumiBoostDomainEntry] = [:]
    private var didLoad = false
    private let changesSubject = PassthroughSubject<Void, Never>()
    // Debounced persistence: editor edits (dot drag, sliders) mutate the store
    // many times per second; writing the entire boosts.json on every tick is
    // wasteful. A pending write is scheduled and re-scheduled, coalescing a
    // burst of edits into a single disk write. Lifecycle events (create,
    // delete, import, discard, flush) bypass the debounce and write now.
    private var pendingWriteTask: Task<Void, Never>?
    private static let writeDebounceNanoseconds: UInt64 = 300_000_000

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
        self.fileManager = fileManager
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.jsonEncoder.dateEncodingStrategy = .iso8601
        self.jsonDecoder.dateDecodingStrategy = .iso8601
    }

    func canBoost(url: URL?) -> Bool {
        SumiBoostURLPolicy.normalizedBoostableHost(for: url) != nil
    }

    func boosts(for url: URL?, profileId: UUID?) -> [SumiBoost] {
        guard let key = SumiBoostURLPolicy.key(for: url, profileId: profileId) else { return [] }
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

    func setActiveBoost(
        _ boostId: UUID?,
        for url: URL?,
        profileId: UUID?,
        isEphemeral: Bool
    ) {
        guard let key = SumiBoostURLPolicy.key(for: url, profileId: profileId) else { return }
        loadIfNeeded()
        guard var entry = entries[key] else { return }
        if let boostId, entry.boosts.contains(where: { $0.id == boostId }) {
            entry.activeBoostId = boostId
        } else {
            entry.activeBoostId = nil
        }
        entry.isEphemeral = entry.isEphemeral || isEphemeral
        entries[key] = entry
        persistIfNeeded(isEphemeral: entry.isEphemeral)
        notifyChanged()
    }

    func toggleActiveBoost(
        _ boost: SumiBoost,
        isEphemeral: Bool
    ) {
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
        removeCSSFile(for: boost.id)
        persistImmediately(isEphemeral: entry.isEphemeral)
        notifyChanged()
    }

    func discardUnchangedDraft(_ boost: SumiBoost) {
        guard !boost.data.changeWasMade else { return }
        deleteBoost(boost, isEphemeral: false)
    }

    func exportData(for boost: SumiBoost) throws -> Data {
        try jsonEncoder.encode(SumiBoostExportPackage(boost: boost))
    }

    @discardableResult
    func importBoost(
        from data: Data,
        for url: URL?,
        profileId: UUID?,
        isEphemeral: Bool
    ) throws -> SumiBoost {
        guard let key = SumiBoostURLPolicy.key(for: url, profileId: profileId) else {
            throw profileId == nil ? SumiBoostStoreError.missingProfile : SumiBoostStoreError.unboostableURL
        }

        let importedData: SumiBoostData
        if let package = try? jsonDecoder.decode(SumiBoostExportPackage.self, from: data) {
            importedData = package.data
        } else if let boostData = try? jsonDecoder.decode(SumiBoostData.self, from: data) {
            importedData = boostData
        } else if let boost = try? jsonDecoder.decode(SumiBoost.self, from: data) {
            importedData = boost.data
        } else {
            throw SumiBoostStoreError.invalidImport
        }

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
        guard let data = try? Data(contentsOf: jsonURL),
              let diskState = try? jsonDecoder.decode(DiskState.self, from: data)
        else {
            return
        }

        entries = Dictionary(
            uniqueKeysWithValues: diskState.domains.map { diskEntry in
                let key = SumiBoostDomainKey(
                    profileId: diskEntry.profileId,
                    host: normalizedHost(diskEntry.host)
                )
                let boosts = diskEntry.boosts.map(loadBoost)
                return (
                    key,
                    SumiBoostDomainEntry(
                        profileId: diskEntry.profileId,
                        host: key.host,
                        activeBoostId: diskEntry.activeBoostId,
                        boosts: boosts,
                        isEphemeral: false
                    )
                )
            }
        )
    }

    private func loadBoost(_ diskBoost: DiskBoost) -> SumiBoost {
        var data = diskBoost.data
        if let customCSSFileName = diskBoost.customCSSFileName,
           let css = try? String(
                contentsOf: cssDirectory.appendingPathComponent(customCSSFileName),
                encoding: .utf8
           ) {
            data.customCSS = css
        }

        return SumiBoost(
            id: diskBoost.id,
            profileId: diskBoost.profileId,
            host: normalizedHost(diskBoost.host),
            data: data,
            createdAt: diskBoost.createdAt,
            updatedAt: diskBoost.updatedAt
        )
    }

    /// Schedules a debounced disk write. Coalesces a burst of editor edits
    /// (dot drag, sliders) into a single `persist()` so the main thread isn't
    /// blocked re-encoding and atomically rewriting boosts.json on every tick.
    private func persistIfNeeded(isEphemeral: Bool) {
        guard !isEphemeral else { return }
        schedulePersist()
    }

    /// Writes immediately, cancelling any debounced write. Call from lifecycle
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
    func flushPendingWrites() {
        guard pendingWriteTask != nil else { return }
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        persist()
    }

    private func schedulePersist() {
        pendingWriteTask?.cancel()
        pendingWriteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.writeDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.pendingWriteTask = nil
                self?.persist()
            }
        }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: cssDirectory, withIntermediateDirectories: true)
            let diskState = DiskState(
                domains: entries.values
                    .filter { !$0.isEphemeral }
                    .sorted { $0.id < $1.id }
                    .map(makeDiskDomainEntry)
            )
            let data = try jsonEncoder.encode(diskState)
            try data.write(to: jsonURL, options: [.atomic])
        } catch {
            RuntimeDiagnostics.debug(
                "Boost store persistence failed: \(error.localizedDescription)",
                category: "Boosts"
            )
        }
    }

    private func makeDiskDomainEntry(_ entry: SumiBoostDomainEntry) -> DiskDomainEntry {
        DiskDomainEntry(
            profileId: entry.profileId,
            host: entry.host,
            activeBoostId: entry.activeBoostId,
            boosts: entry.boosts
                .sorted { $0.createdAt < $1.createdAt }
                .map(makeDiskBoost)
        )
    }

    private func makeDiskBoost(_ boost: SumiBoost) -> DiskBoost {
        var data = boost.data
        let trimmedCSS = data.customCSS
        var fileName: String?
        if trimmedCSS.isEmpty {
            removeCSSFile(for: boost.id)
            fileName = nil
        } else {
            fileName = "\(boost.id.uuidString.lowercased()).css"
            do {
                try trimmedCSS.write(
                    to: cssDirectory.appendingPathComponent(fileName!),
                    atomically: true,
                    encoding: .utf8
                )
                data.customCSS = ""
            } catch {
                RuntimeDiagnostics.debug(
                    "Boost CSS persistence failed: \(error.localizedDescription)",
                    category: "Boosts"
                )
                fileName = nil
            }
        }

        return DiskBoost(
            id: boost.id,
            profileId: boost.profileId,
            host: boost.host,
            data: data,
            customCSSFileName: fileName,
            createdAt: boost.createdAt,
            updatedAt: boost.updatedAt
        )
    }

    private func removeCSSFile(for boostId: UUID) {
        let fileName = "\(boostId.uuidString.lowercased()).css"
        try? fileManager.removeItem(at: cssDirectory.appendingPathComponent(fileName))
    }

    private func notifyChanged() {
        changesSubject.send(())
    }

    private func normalizedHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private var jsonURL: URL {
        rootDirectory.appendingPathComponent("boosts.json")
    }

    private var cssDirectory: URL {
        rootDirectory.appendingPathComponent("css", isDirectory: true)
    }

    private static func defaultRootDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent("Sumi", isDirectory: true)
            .appendingPathComponent("Boosts", isDirectory: true)
    }
}
