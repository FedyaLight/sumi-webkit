import Foundation
import OSLog

struct SumiPermissionJSONPersistenceDiagnostics: Equatable, Sendable {
    enum LoadOutcome: Equatable, Sendable {
        case notLoaded
        case missing
        case loadedFile
        case loadedLegacyUserDefaults
        case failedFileRead(String)
        case failedFileDecode(String)
        case failedLegacyUserDefaultsDecode(String)
        case unsupportedFileVersion(Int)
    }

    var loadOutcome: LoadOutcome = .notLoaded
    var lastWriteFailure: String?
}

struct SumiPermissionJSONSnapshotFailure: LocalizedError, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case read
        case decode
        case write
    }

    var kind: Kind
    var description: String
    var data: Data?

    var errorDescription: String? {
        description
    }
}

enum SumiPermissionJSONSnapshotLoadResult<Snapshot: Sendable>: Sendable {
    case missing
    case loaded(snapshot: Snapshot, data: Data)
    case failed(SumiPermissionJSONSnapshotFailure)
}

struct SumiPermissionJSONSnapshotStore<Snapshot: Codable & Sendable>: Sendable {
    let fileURL: URL

    init(fileName: String, directoryURL: URL? = nil) {
        let directory = directoryURL ?? SumiApplicationSupportDirectory.appRootURL()
            .appendingPathComponent("Permissions", isDirectory: true)
        fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
    }

    func load() -> SumiPermissionJSONSnapshotLoadResult<Snapshot> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .failed(
                SumiPermissionJSONSnapshotFailure(
                    kind: .read,
                    description: error.localizedDescription,
                    data: nil
                )
            )
        }

        do {
            return .loaded(snapshot: try JSONDecoder().decode(Snapshot.self, from: data), data: data)
        } catch {
            preserveUnreadablePayload(data)
            return .failed(
                SumiPermissionJSONSnapshotFailure(
                    kind: .decode,
                    description: error.localizedDescription,
                    data: data
                )
            )
        }
    }

    func write(_ snapshot: Snapshot) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            throw SumiPermissionJSONSnapshotFailure(
                kind: .write,
                description: error.localizedDescription,
                data: nil
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw SumiPermissionJSONSnapshotFailure(
                kind: .write,
                description: error.localizedDescription,
                data: data
            )
        }
    }

    func preserveUnreadablePayload(_ data: Data) {
        let unreadableURL = fileURL.appendingPathExtension("unreadable")
        guard !FileManager.default.fileExists(atPath: unreadableURL.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: unreadableURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: unreadableURL, options: .atomic)
        } catch {
            Logger.sumi(category: "PermissionPersistence").error(
                "Failed to preserve unreadable permission JSON payload at \(unreadableURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
