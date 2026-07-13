import Foundation
import OSLog
import SumiDomain

struct SumiPermissionPersistenceLoadedState {
    var generation: UInt64
    var antiAbuseEvents: [SumiPermissionAntiAbuseEvent]
    var siteActivityRecordsById: [String: SumiPermissionSiteActivityRecord]
    var outcome: SumiPermissionPersistenceDiagnostics.LoadOutcome
    var needsCanonicalWrite: Bool
    var shouldRetireLegacyPersistence: Bool
}

/// Loads the canonical permission snapshot or migrates the two legacy domains
/// as whole snapshots. It never publishes a generation; that remains the
/// authority's decision.
enum SumiPermissionSnapshotLoader {
    private struct LegacyAntiAbuseEnvelope: Codable {
        var version: Int
        var records: [SumiPermissionAntiAbuseEvent]
    }

    private struct LegacySiteActivityEnvelope: Codable {
        var version: Int
        var records: [SumiPermissionSiteActivityRecord]
    }

    private enum FileLoad<Value> {
        case missing
        case loaded(Value)
        case failedRead(String)
        case failedDecode(String)
    }

    private static let log = Logger.sumi(category: "PermissionPersistence")

    static func load(
        fileURL: URL?,
        legacyDirectoryURL: URL?,
        userDefaults: UserDefaults?,
        legacyAntiAbuseStorageKey: String
    ) -> SumiPermissionPersistenceLoadedState {
        if let fileURL {
            switch loadFile(SumiPermissionPersistenceEnvelope.self, at: fileURL) {
            case .missing:
                break
            case .loaded(let envelope):
                guard envelope.version == SumiPermissionPersistenceAuthority.storageVersion else {
                    preserveUnreadableFile(at: fileURL)
                    return emptyState(outcome: .unsupportedFileVersion(envelope.version))
                }
                let didRetireLegacyPersistence = retireLegacyPersistence(
                    legacyDirectoryURL: legacyDirectoryURL,
                    userDefaults: userDefaults,
                    legacyAntiAbuseStorageKey: legacyAntiAbuseStorageKey
                )
                return SumiPermissionPersistenceLoadedState(
                    generation: envelope.generation,
                    antiAbuseEvents: envelope.antiAbuseEvents,
                    siteActivityRecordsById: newestSiteActivityRecords(envelope.siteActivityRecords),
                    outcome: .loadedFile,
                    needsCanonicalWrite: false,
                    shouldRetireLegacyPersistence: !didRetireLegacyPersistence
                )
            case .failedRead(let description):
                return emptyState(outcome: .failedFileRead(description))
            case .failedDecode(let description):
                preserveUnreadableFile(at: fileURL)
                return emptyState(outcome: .failedFileDecode(description))
            }
        }

        return loadLegacyState(
            canWriteCanonical: fileURL != nil,
            legacyDirectoryURL: legacyDirectoryURL,
            userDefaults: userDefaults,
            legacyAntiAbuseStorageKey: legacyAntiAbuseStorageKey
        )
    }

    private static func loadLegacyState(
        canWriteCanonical: Bool,
        legacyDirectoryURL: URL?,
        userDefaults: UserDefaults?,
        legacyAntiAbuseStorageKey: String
    ) -> SumiPermissionPersistenceLoadedState {
        var antiAbuseFromFile: [SumiPermissionAntiAbuseEvent]?
        var siteActivityFromFile: [SumiPermissionSiteActivityRecord]?
        var loadedValidLegacyFile = false
        var sawLegacyFile = false
        var firstFailure: SumiPermissionPersistenceDiagnostics.LoadOutcome?

        if let legacyDirectoryURL {
            let antiAbuseURL = legacyDirectoryURL.appendingPathComponent(
                SumiPermissionPersistenceAuthority.legacyAntiAbuseFileName
            )
            switch loadFile(LegacyAntiAbuseEnvelope.self, at: antiAbuseURL) {
            case .missing:
                break
            case .loaded(let envelope):
                sawLegacyFile = true
                if envelope.version == SumiPermissionPersistenceAuthority.storageVersion {
                    loadedValidLegacyFile = true
                    antiAbuseFromFile = envelope.records
                } else {
                    preserveUnreadableFile(at: antiAbuseURL)
                    firstFailure = firstFailure ?? .unsupportedFileVersion(envelope.version)
                }
            case .failedRead(let description):
                sawLegacyFile = true
                firstFailure = firstFailure ?? .failedFileRead(description)
            case .failedDecode(let description):
                sawLegacyFile = true
                preserveUnreadableFile(at: antiAbuseURL)
                firstFailure = firstFailure ?? .failedFileDecode(description)
            }

            let siteActivityURL = legacyDirectoryURL.appendingPathComponent(
                SumiPermissionPersistenceAuthority.legacySiteActivityFileName
            )
            switch loadFile(LegacySiteActivityEnvelope.self, at: siteActivityURL) {
            case .missing:
                break
            case .loaded(let envelope):
                sawLegacyFile = true
                if envelope.version == SumiPermissionPersistenceAuthority.storageVersion {
                    loadedValidLegacyFile = true
                    siteActivityFromFile = envelope.records
                } else {
                    preserveUnreadableFile(at: siteActivityURL)
                    firstFailure = firstFailure ?? .unsupportedFileVersion(envelope.version)
                }
            case .failedRead(let description):
                sawLegacyFile = true
                firstFailure = firstFailure ?? .failedFileRead(description)
            case .failedDecode(let description):
                sawLegacyFile = true
                preserveUnreadableFile(at: siteActivityURL)
                firstFailure = firstFailure ?? .failedFileDecode(description)
            }
        }

        var antiAbuseFromDefaults: [SumiPermissionAntiAbuseEvent]?
        var siteActivityFromDefaults: [SumiPermissionSiteActivityRecord]?
        var sawLegacyDefaults = false

        if let data = userDefaults?.data(forKey: legacyAntiAbuseStorageKey) {
            sawLegacyDefaults = true
            do {
                antiAbuseFromDefaults = try JSONDecoder().decode(
                    [SumiPermissionAntiAbuseEvent].self,
                    from: data
                )
            } catch {
                preserveUnreadableDefaults(
                    data,
                    userDefaults: userDefaults,
                    storageKey: legacyAntiAbuseStorageKey
                )
                firstFailure = firstFailure ?? .failedLegacyUserDefaultsDecode(error.localizedDescription)
            }
        }

        if let data = userDefaults?.data(
            forKey: SumiPermissionPersistenceAuthority.legacySiteActivityStorageKey
        ) {
            sawLegacyDefaults = true
            do {
                let envelope = try JSONDecoder().decode(LegacySiteActivityEnvelope.self, from: data)
                if envelope.version == SumiPermissionPersistenceAuthority.storageVersion {
                    siteActivityFromDefaults = envelope.records
                } else {
                    preserveUnreadableDefaults(
                        data,
                        userDefaults: userDefaults,
                        storageKey: SumiPermissionPersistenceAuthority.legacySiteActivityStorageKey
                    )
                    firstFailure = firstFailure ?? .unsupportedFileVersion(envelope.version)
                }
            } catch {
                preserveUnreadableDefaults(
                    data,
                    userDefaults: userDefaults,
                    storageKey: SumiPermissionPersistenceAuthority.legacySiteActivityStorageKey
                )
                firstFailure = firstFailure ?? .failedLegacyUserDefaultsDecode(error.localizedDescription)
            }
        }

        guard antiAbuseFromFile != nil
                || siteActivityFromFile != nil
                || antiAbuseFromDefaults != nil
                || siteActivityFromDefaults != nil
        else {
            var state = emptyState(outcome: firstFailure ?? .missing)
            state.shouldRetireLegacyPersistence = sawLegacyFile || sawLegacyDefaults
            return state
        }

        return migratedState(
            antiAbuseEvents: newestAntiAbuseSnapshot(
                defaults: antiAbuseFromDefaults,
                file: antiAbuseFromFile
            ),
            siteActivityRecords: newestSiteActivitySnapshot(
                defaults: siteActivityFromDefaults,
                file: siteActivityFromFile
            ),
            outcome: loadedValidLegacyFile ? .loadedLegacySnapshots : .loadedLegacyUserDefaults,
            canWriteCanonical: canWriteCanonical,
            shouldRetireLegacyPersistence: sawLegacyFile || sawLegacyDefaults
        )
    }

    private static func migratedState(
        antiAbuseEvents: [SumiPermissionAntiAbuseEvent],
        siteActivityRecords: [SumiPermissionSiteActivityRecord],
        outcome: SumiPermissionPersistenceDiagnostics.LoadOutcome,
        canWriteCanonical: Bool,
        shouldRetireLegacyPersistence: Bool
    ) -> SumiPermissionPersistenceLoadedState {
        SumiPermissionPersistenceLoadedState(
            generation: canWriteCanonical ? 1 : 0,
            antiAbuseEvents: antiAbuseEvents,
            siteActivityRecordsById: newestSiteActivityRecords(siteActivityRecords),
            outcome: outcome,
            needsCanonicalWrite: canWriteCanonical,
            shouldRetireLegacyPersistence: shouldRetireLegacyPersistence
        )
    }

    private static func emptyState(
        outcome: SumiPermissionPersistenceDiagnostics.LoadOutcome
    ) -> SumiPermissionPersistenceLoadedState {
        SumiPermissionPersistenceLoadedState(
            generation: 0,
            antiAbuseEvents: [],
            siteActivityRecordsById: [:],
            outcome: outcome,
            needsCanonicalWrite: false,
            shouldRetireLegacyPersistence: false
        )
    }

    private static func loadFile<Value: Decodable>(
        _ type: Value.Type,
        at url: URL
    ) -> FileLoad<Value> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failedRead(error.localizedDescription)
        }
        do {
            return .loaded(try JSONDecoder().decode(type, from: data))
        } catch {
            return .failedDecode(error.localizedDescription)
        }
    }

    /// Legacy snapshots have no generation. Select one complete snapshot by
    /// its latest domain timestamp; unioning snapshots could resurrect deleted
    /// records. With no ordering evidence, the legacy file wins ties.
    private static func newestAntiAbuseSnapshot(
        defaults: [SumiPermissionAntiAbuseEvent]?,
        file: [SumiPermissionAntiAbuseEvent]?
    ) -> [SumiPermissionAntiAbuseEvent] {
        switch (defaults, file) {
        case (.none, .none):
            return []
        case (.some(let defaults), .none):
            return defaults
        case (.none, .some(let file)):
            return file
        case (.some(let defaults), .some(let file)):
            let defaultsHighWater = defaults.map(\.createdAt).max() ?? .distantPast
            let fileHighWater = file.map(\.createdAt).max() ?? .distantPast
            return defaultsHighWater > fileHighWater ? defaults : file
        }
    }

    private static func newestSiteActivitySnapshot(
        defaults: [SumiPermissionSiteActivityRecord]?,
        file: [SumiPermissionSiteActivityRecord]?
    ) -> [SumiPermissionSiteActivityRecord] {
        switch (defaults, file) {
        case (.none, .none):
            return []
        case (.some(let defaults), .none):
            return defaults
        case (.none, .some(let file)):
            return file
        case (.some(let defaults), .some(let file)):
            let defaultsHighWater = defaults.map(\.updatedAt).max() ?? .distantPast
            let fileHighWater = file.map(\.updatedAt).max() ?? .distantPast
            return defaultsHighWater > fileHighWater ? defaults : file
        }
    }

    private static func newestSiteActivityRecords(
        _ records: [SumiPermissionSiteActivityRecord]
    ) -> [String: SumiPermissionSiteActivityRecord] {
        var byId: [String: SumiPermissionSiteActivityRecord] = [:]
        for record in records
        where byId[record.id] == nil || byId[record.id]!.updatedAt <= record.updatedAt {
            byId[record.id] = record
        }
        return byId
    }

    private static func preserveUnreadableFile(at url: URL) {
        let backupURL = url.appendingPathExtension("unreadable")
        guard !FileManager.default.fileExists(atPath: backupURL.path),
              let data = try? Data(contentsOf: url)
        else { return }
        do {
            try data.write(to: backupURL, options: .atomic)
        } catch {
            log.error(
                "Failed to preserve unreadable permission payload at \(backupURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func preserveUnreadableDefaults(
        _ data: Data,
        userDefaults: UserDefaults?,
        storageKey: String
    ) {
        guard let userDefaults else { return }
        let backupKey = "\(storageKey).unreadable"
        guard userDefaults.data(forKey: backupKey) == nil else { return }
        userDefaults.set(data, forKey: backupKey)
    }

    @discardableResult
    static func retireLegacyPersistence(
        legacyDirectoryURL: URL?,
        userDefaults: UserDefaults?,
        legacyAntiAbuseStorageKey: String
    ) -> Bool {
        var succeeded = true
        if let legacyDirectoryURL {
            for fileName in [
                SumiPermissionPersistenceAuthority.legacyAntiAbuseFileName,
                SumiPermissionPersistenceAuthority.legacySiteActivityFileName,
            ] {
                let url = legacyDirectoryURL.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    succeeded = false
                    log.error(
                        "Failed to retire legacy permission snapshot at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
        userDefaults?.removeObject(forKey: legacyAntiAbuseStorageKey)
        userDefaults?.removeObject(
            forKey: SumiPermissionPersistenceAuthority.legacySiteActivityStorageKey
        )
        return succeeded
    }
}
