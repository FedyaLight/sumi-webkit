import Foundation
import OSLog

/// Serial persistence boundary for Boosts. All filesystem, Codable, and CSS
/// work stays on its private queue; callers exchange immutable Sendable values.
final class SumiBoostDiskWorker: @unchecked Sendable {
    struct LoadResult: Sendable {
        var entries: [SumiBoostDomainKey: SumiBoostDomainEntry]
        var failure: SumiBoostStoreError?
    }

    private struct DiskState: Codable, Sendable {
        var domains: [DiskDomainEntry]
    }

    private struct DiskDomainEntry: Codable, Sendable {
        var profileId: UUID
        var host: String
        var activeBoostId: UUID?
        var boosts: [DiskBoost]
    }

    private struct DiskBoost: Codable, Sendable {
        var id: UUID
        var profileId: UUID
        var host: String
        var data: SumiBoostData
        var customCSSFileName: String?
        var createdAt: Date
        var updatedAt: Date
    }

    private static let log = Logger.sumi(category: "BoostStore")

    private let queue = DispatchQueue(label: "com.sumi.browser.boost-disk", qos: .utility)
    private let lock = NSLock()
    private let loadGroup = DispatchGroup()
    private let rootDirectory: URL
    private let fileManager: FileManager
    private var didStartLoad = false
    private var loadResult: LoadResult?
    private var latestRequestedPersistRevision: UInt64 = 0
    private var latestPersistedRevision: UInt64 = 0

    init(rootDirectory: URL, fileManager: FileManager) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func prefetch() {
        lock.lock()
        guard !didStartLoad else {
            lock.unlock()
            return
        }
        didStartLoad = true
        loadGroup.enter()
        lock.unlock()

        queue.async { [self] in
            let result = loadEntries()
            lock.lock()
            loadResult = result
            lock.unlock()
            loadGroup.leave()
        }
    }

    func loadedResult() -> LoadResult {
        prefetch()
        loadGroup.wait()
        lock.lock()
        defer { lock.unlock() }
        return loadResult ?? LoadResult(entries: [:], failure: .profileCleanupStoreUnreadable)
    }

    func enqueuePersist(
        _ entries: [SumiBoostDomainKey: SumiBoostDomainEntry],
        revision: UInt64
    ) {
        lock.lock()
        latestRequestedPersistRevision = max(latestRequestedPersistRevision, revision)
        lock.unlock()

        queue.async { [self] in
            lock.lock()
            let latestRequestedRevision = latestRequestedPersistRevision
            lock.unlock()
            guard revision >= latestRequestedRevision,
                  revision > latestPersistedRevision else {
                return
            }

            let interval = PerformanceTrace.beginInterval("Boost.persist")
            defer { PerformanceTrace.endInterval("Boost.persist", interval) }
            do {
                try persistEntries(entries)
                latestPersistedRevision = revision
            } catch {
                RuntimeDiagnostics.debug(
                    "Boost store persistence failed: \(error.localizedDescription)",
                    category: "Boosts"
                )
            }
        }
    }

    func commit(_ entries: [SumiBoostDomainKey: SumiBoostDomainEntry]) async throws {
        try await perform { [self] in
            try persistEntries(entries)
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume()
            }
        }
    }

    func exportData(for boost: SumiBoost) async throws -> Data {
        try await perform {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(SumiBoostExportPackage(boost: boost))
        }
    }

    func decodeImportedBoostData(from data: Data) async throws -> SumiBoostData {
        try await perform {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var failures: [String] = []

            do {
                return try decoder.decode(SumiBoostExportPackage.self, from: data).data
            } catch {
                failures.append("SumiBoostExportPackage: \(error.localizedDescription)")
            }

            do {
                return try decoder.decode(SumiBoostData.self, from: data)
            } catch {
                failures.append("SumiBoostData: \(error.localizedDescription)")
            }

            do {
                return try decoder.decode(SumiBoost.self, from: data).data
            } catch {
                failures.append("SumiBoost: \(error.localizedDescription)")
            }

            Self.log.error(
                "Boost import rejected (bytes=\(data.count, privacy: .public)): \(failures.joined(separator: "; "), privacy: .public)"
            )
            throw SumiBoostStoreError.invalidImport
        }
    }

    static func defaultRootDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent("Sumi", isDirectory: true)
            .appendingPathComponent("Boosts", isDirectory: true)
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try operation() })
            }
        }
    }

    private func loadEntries() -> LoadResult {
        let jsonURL = rootDirectory.appendingPathComponent("boosts.json")
        let cssDirectory = rootDirectory.appendingPathComponent("css", isDirectory: true)
        do {
            let data = try Data(contentsOf: jsonURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let diskState: DiskState
            do {
                diskState = try decoder.decode(DiskState.self, from: data)
            } catch {
                preserveUnreadableBoostsPayload(data, jsonURL: jsonURL)
                Self.log.error(
                    "Failed to decode boosts store: \(error.localizedDescription, privacy: .public)"
                )
                return LoadResult(entries: [:], failure: .profileCleanupStoreUnreadable)
            }
            let entries = Dictionary(
                uniqueKeysWithValues: diskState.domains.map { diskEntry in
                    let host = Self.normalizedHost(diskEntry.host)
                    let key = SumiBoostDomainKey(profileId: diskEntry.profileId, host: host)
                    return (
                        key,
                        SumiBoostDomainEntry(
                            profileId: diskEntry.profileId,
                            host: host,
                            activeBoostId: diskEntry.activeBoostId,
                            boosts: diskEntry.boosts.map {
                                loadBoost($0, cssDirectory: cssDirectory)
                            },
                            isEphemeral: false
                        )
                    )
                }
            )
            return LoadResult(entries: entries, failure: nil)
        } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                Self.log.error(
                    "Failed to read boosts store: \(error.localizedDescription, privacy: .public)"
                )
                return LoadResult(entries: [:], failure: .profileCleanupStoreUnreadable)
            }
            return LoadResult(entries: [:], failure: nil)
        }
    }

    private func preserveUnreadableBoostsPayload(_ data: Data, jsonURL: URL) {
        let backupURL = jsonURL.appendingPathExtension("unreadable")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        do {
            try data.write(to: backupURL, options: [.atomic])
        } catch {
            Self.log.error(
                "Failed to preserve unreadable boosts payload: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func loadBoost(_ diskBoost: DiskBoost, cssDirectory: URL) -> SumiBoost {
        var data = diskBoost.data
        if let customCSSFileName = diskBoost.customCSSFileName {
            do {
                data.customCSS = try String(
                    contentsOf: cssDirectory.appendingPathComponent(customCSSFileName),
                    encoding: .utf8
                )
            } catch {
                Self.log.error(
                    "Failed to read custom CSS '\(customCSSFileName, privacy: .public)' for boost: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return SumiBoost(
            id: diskBoost.id,
            profileId: diskBoost.profileId,
            host: Self.normalizedHost(diskBoost.host),
            data: data,
            createdAt: diskBoost.createdAt,
            updatedAt: diskBoost.updatedAt
        )
    }

    private func persistEntries(
        _ source: [SumiBoostDomainKey: SumiBoostDomainEntry]
    ) throws {
        let cssDirectory = rootDirectory.appendingPathComponent("css", isDirectory: true)
        let jsonURL = rootDirectory.appendingPathComponent("boosts.json")
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cssDirectory, withIntermediateDirectories: true)

        let diskState = DiskState(
            domains: try source.values
                .filter { !$0.isEphemeral }
                .sorted { $0.id < $1.id }
                .map { try makeDiskDomainEntry($0, cssDirectory: cssDirectory) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(diskState)
        try data.write(to: jsonURL, options: [.atomic])

        let retainedCSSNames = Set(
            diskState.domains.flatMap(\.boosts).compactMap(\.customCSSFileName)
        )
        if let files = try? fileManager.contentsOfDirectory(
            at: cssDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension == "css"
                && !retainedCSSNames.contains(file.lastPathComponent) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func makeDiskDomainEntry(
        _ entry: SumiBoostDomainEntry,
        cssDirectory: URL
    ) throws -> DiskDomainEntry {
        try DiskDomainEntry(
            profileId: entry.profileId,
            host: entry.host,
            activeBoostId: entry.activeBoostId,
            boosts: entry.boosts
                .sorted { $0.createdAt < $1.createdAt }
                .map { try makeDiskBoost($0, cssDirectory: cssDirectory) }
        )
    }

    private func makeDiskBoost(_ boost: SumiBoost, cssDirectory: URL) throws -> DiskBoost {
        var data = boost.data
        let customCSS = data.customCSS
        let fileName: String?
        if customCSS.isEmpty {
            fileName = nil
        } else {
            let cssFileName = "\(boost.id.uuidString.lowercased()).css"
            fileName = cssFileName
            try customCSS.write(
                to: cssDirectory.appendingPathComponent(cssFileName),
                atomically: true,
                encoding: .utf8
            )
            data.customCSS = ""
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

    private static func normalizedHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }
}
