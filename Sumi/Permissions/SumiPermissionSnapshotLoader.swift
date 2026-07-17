import Foundation
import OSLog
import SumiDomain

struct SumiPermissionPersistenceLoadedState {
    var generation: UInt64
    var antiAbuseEvents: [SumiPermissionAntiAbuseEvent]
    var siteActivityRecordsById: [String: SumiPermissionSiteActivityRecord]
    var outcome: SumiPermissionPersistenceDiagnostics.LoadOutcome
}

/// Loads the canonical permission snapshot. It never publishes a generation;
/// that remains the authority's decision.
enum SumiPermissionSnapshotLoader {
    private enum FileLoad<Value> {
        case missing
        case loaded(Value)
        case failedRead(String)
        case failedDecode(String)
    }

    private static let log = Logger.sumi(category: "PermissionPersistence")

    static func load(
        fileURL: URL?
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
                return SumiPermissionPersistenceLoadedState(
                    generation: envelope.generation,
                    antiAbuseEvents: envelope.antiAbuseEvents,
                    siteActivityRecordsById: newestSiteActivityRecords(envelope.siteActivityRecords),
                    outcome: .loadedFile
                )
            case .failedRead(let description):
                return emptyState(outcome: .failedFileRead(description))
            case .failedDecode(let description):
                preserveUnreadableFile(at: fileURL)
                return emptyState(outcome: .failedFileDecode(description))
            }
        }

        return emptyState(outcome: .missing)
    }

    private static func emptyState(
        outcome: SumiPermissionPersistenceDiagnostics.LoadOutcome
    ) -> SumiPermissionPersistenceLoadedState {
        SumiPermissionPersistenceLoadedState(
            generation: 0,
            antiAbuseEvents: [],
            siteActivityRecordsById: [:],
            outcome: outcome
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
}
