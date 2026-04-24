//
//  SumiStartupPersistence.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import AppKit
import Combine
import CoreServices
import OSLog
import SwiftData
import SwiftUI
import WebKit

@MainActor
final class SumiStartupPersistence {
    static let shared = SumiStartupPersistence()
    let container: ModelContainer

    // MARK: - Constants
    nonisolated private static let log = Logger.sumi(category: "StartupPersistence")
    nonisolated private static let storeFileName = "default.store"
    nonisolated private static let backupPrefix = "default_backup_"
    // Backups now use a directory per snapshot: default_backup_<timestamp>/

    static let schema = Schema([
        SpaceEntity.self,
        ProfileEntity.self,
        TabEntity.self,
        FolderEntity.self,
        TabsStateEntity.self,
        HistoryEntryEntity.self,
        HistoryVisitEntity.self,
        ExtensionEntity.self,
        UserScriptEntity.self,
        UserScriptResourceEntity.self,
    ])

    // MARK: - URLs
    nonisolated private static var appSupportURL: URL {
        if let overridePath = ProcessInfo.processInfo.environment["SUMI_APP_SUPPORT_OVERRIDE"],
           !overridePath.isEmpty
        {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: overrideURL,
                    withIntermediateDirectories: true
                )
            } catch {
                log.error(
                    "Failed to create overridden Application Support directory: \(String(describing: error), privacy: .public)"
                )
            }
            return overrideURL
        }

        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = SumiAppIdentity.runtimeBundleIdentifier
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            log.error(
                "Failed to create Application Support directory: \(String(describing: error), privacy: .public)"
            )
        }
        return dir
    }

    nonisolated private static var storeURL: URL {
        appSupportURL.appendingPathComponent(storeFileName, isDirectory: false)
    }
    nonisolated private static var backupsDirectoryURL: URL {
        let dir = appSupportURL.appendingPathComponent("Backups", isDirectory: true)
        let fm = FileManager.default
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            log.error(
                "Failed to create Backups directory: \(String(describing: error), privacy: .public)"
            )
        }
        return dir
    }

    // MARK: - Init
    private init() {
        do {
            let resolvedContainer = try Self.openPersistentContainer()
            Self.log.info("SwiftData container initialized successfully")
            Self.scheduleStartupBackupIfPossible()
            self.container = resolvedContainer
        } catch {
            let classification = Self.classifyStoreError(error)
            Self.log.error(
                "SwiftData container initialization failed. Classification=\(String(describing: classification)) error=\(String(describing: error), privacy: .public)"
            )

            switch classification {
            case .schemaMismatch:
                Self.log.fault(
                    "Schema mismatch detected. Recreating the local store without migration."
                )
                do {
                    try Self.resetPersistentStore()
                    let resolvedContainer = try Self.openPersistentContainer()
                    Self.log.notice("Recreated SwiftData store after schema mismatch.")
                    self.container = resolvedContainer
                } catch let resetError {
                    Self.log.fault(
                        "Failed to recreate store after schema mismatch: \(String(describing: resetError), privacy: .public)"
                    )
                    fatalError("Sumi could not recreate the local browser store after a schema update.")
                }

            case .corruption, .other:
                Self.log.fault(
                    "Attempting to restore the latest known-good store backup after startup failure."
                )
                do {
                    try Self.restoreFromBackup()
                    let resolvedContainer = try Self.openPersistentContainer()
                    Self.log.notice(
                        "Restored SwiftData container from latest known-good backup.")
                    self.container = resolvedContainer
                } catch let restoreError {
                    Self.log.fault(
                        "Failed to restore usable SwiftData store from backup: \(String(describing: restoreError), privacy: .public)"
                    )
                    do {
                        try Self.resetPersistentStore()
                        let resolvedContainer = try Self.openPersistentContainer()
                        Self.log.notice(
                            "Recreated SwiftData store after backup restore failed."
                        )
                        self.container = resolvedContainer
                    } catch let resetError {
                        Self.log.fault(
                            "Failed to recreate store after backup restore failed: \(String(describing: resetError), privacy: .public)"
                        )
                        fatalError(
                            "Sumi could not open or recreate the local browser store."
                        )
                    }
                }

            case .diskSpace:
                Self.log.fault(
                    "Store initialization failed due to insufficient disk space. Not deleting store."
                )
                fatalError("Sumi could not open the local browser store because disk space is insufficient.")
            }
        }
    }

    private static func openPersistentContainer() throws -> ModelContainer {
        let config = ModelConfiguration(url: Self.storeURL)
        return try ModelContainer(for: Self.schema, configurations: [config])
    }

    // MARK: - Error Classification
    private enum StoreErrorType { case schemaMismatch, diskSpace, corruption, other }
    private static func classifyStoreError(_ error: Error) -> StoreErrorType {
        let ns = error as NSError
        let domain = ns.domain
        let code = ns.code
        let desc = Self.errorDescriptionTree(error)
        let lower = (desc + " " + domain).lowercased()

        // Disk space: POSIX ENOSPC or clear full-disk wording
        if domain == NSPOSIXErrorDomain && code == 28 { return .diskSpace }
        if lower.contains("no space left") || lower.contains("disk full") { return .diskSpace }

        // Schema mismatch / migration issues (avoid matching generic "model" alone — too broad)
        if lower.contains("migration")
            || lower.contains("mapping model")
            || lower.contains("version hash")
            || (lower.contains("incompatible") && (lower.contains("version") || lower.contains("store") || lower.contains("schema")))
            || (lower.contains("schema") && (lower.contains("mismatch") || lower.contains("incompatible")))
        {
            return .schemaMismatch
        }

        // Corruption indicators (SQLite/CoreData wording)
        if lower.contains("corrupt") || lower.contains("malformed")
            || lower.contains("database disk image is malformed")
            || lower.contains("file is encrypted or is not a database")
        {
            return .corruption
        }

        return .other
    }

    private static func errorDescriptionTree(_ error: Error) -> String {
        var parts: [String] = []
        var visited = Set<ObjectIdentifier>()

        func append(_ error: Error) {
            let ns = error as NSError
            let identity = ObjectIdentifier(ns)
            guard !visited.contains(identity) else { return }
            visited.insert(identity)

            parts.append(ns.localizedDescription)
            parts.append(ns.domain)
            parts.append(String(ns.code))
            for value in ns.userInfo.values {
                switch value {
                case let nested as NSError:
                    append(nested)
                case let nested as Error:
                    append(nested)
                default:
                    parts.append(String(describing: value))
                }
            }
        }

        append(error)
        return parts.joined(separator: " ")
    }

    // MARK: - Backup / Restore
    private enum PersistenceBackupError: Error { case storeNotFound, noBackupsFound }

    nonisolated private static func scheduleStartupBackupIfPossible() {
        DispatchQueue.global(qos: .utility).async {
            Self.createStartupBackupIfPossible()
        }
    }

    nonisolated private static func createStartupBackupIfPossible() {
        do {
            _ = try createBackupOnCurrentQueue()
        } catch let error as PersistenceBackupError {
            switch error {
            case .storeNotFound:
                log.notice("No persistent store file exists yet; skipping startup backup.")
            case .noBackupsFound:
                log.notice("No backups found while creating startup backup.")
            }
        } catch {
            log.error(
                "Failed to create startup store backup: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // Include SQLite sidecars (-wal/-shm) and back up into a directory
    nonisolated private static func createBackupOnCurrentQueue() throws -> URL {
        let fm = FileManager.default
        let source = Self.storeURL
        guard fm.fileExists(atPath: source.path) else {
            Self.log.info(
                "No existing store found to back up at \(source.path, privacy: .public)")
            throw PersistenceBackupError.storeNotFound
        }

        // Ensure backups root exists.
        let backupsRoot = Self.backupsDirectoryURL

        let stamp = Self.makeBackupTimestamp()
        let dirName = "\(Self.backupPrefix)\(stamp)"
        let backupDir = backupsRoot.appendingPathComponent(dirName, isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let candidates = [source] + Self.sidecarURLs(for: source)
        for file in candidates where fm.fileExists(atPath: file.path) {
            let dest = backupDir.appendingPathComponent(
                file.lastPathComponent,
                isDirectory: false
            )
            do {
                try fm.copyItem(at: file, to: dest)
            } catch {
                Self.log.error(
                    "Failed to copy \(file.lastPathComponent, privacy: .public) to backup: \(String(describing: error), privacy: .public)"
                )
                throw error
            }
        }

        return backupDir
    }

    // Restore the latest backup directory by copying files back next to the store
    nonisolated private static func restoreFromBackup() throws {
        try Self.runBlockingOnUtilityQueue {
            let fm = FileManager.default
            let root = Self.backupsDirectoryURL
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles])
            } catch {
                Self.log.error(
                    "Failed to list backups: \(String(describing: error), privacy: .public)")
                throw error
            }

            let backups = contents.filter { url in
                url.lastPathComponent.hasPrefix(Self.backupPrefix)
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }

            guard !backups.isEmpty else { throw PersistenceBackupError.noBackupsFound }

            // Pick the most recently modified backup directory
            let latest = backups.max { lhs, rhs in
                let l =
                    (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? Date.distantPast
                let r =
                    (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? Date.distantPast
                return l < r
            }!

            // Remove current store files first
            try Self.deleteStore()

            // Copy all files from backup dir back to app support dir
            let backupFiles = try fm.contentsOfDirectory(
                at: latest, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for file in backupFiles {
                let dest = Self.appSupportURL.appendingPathComponent(
                    file.lastPathComponent, isDirectory: false)
                do { try fm.copyItem(at: file, to: dest) } catch {
                    Self.log.error(
                        "Restore copy failed for \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                    throw error
                }
            }

            Self.log.notice(
                "Restored store from backup directory: \(latest.lastPathComponent, privacy: .public)"
            )
        }
    }

    // Deletes the base store and known SQLite sidecars if present
    nonisolated private static func deleteStore() throws {
        try Self.runBlockingOnUtilityQueue {
            let fm = FileManager.default
            let base = Self.storeURL
            let files = [base] + Self.sidecarURLs(for: base)
            for file in files {
                if fm.fileExists(atPath: file.path) {
                    do { try fm.removeItem(at: file) } catch {
                        Self.log.error(
                            "Failed to remove \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                        )
                        throw error
                    }
                }
            }
        }
    }

    nonisolated private static func resetPersistentStore() throws {
        try Self.runBlockingOnUtilityQueue {
            let fm = FileManager.default
            let base = Self.storeURL
            let files = [base] + Self.sidecarURLs(for: base)
            for file in files where fm.fileExists(atPath: file.path) {
                try? fm.removeItem(at: file)
            }
            if fm.fileExists(atPath: Self.backupsDirectoryURL.path) {
                try? fm.removeItem(at: Self.backupsDirectoryURL)
            }
        }
    }

    // MARK: - Helpers
    nonisolated private static func sidecarURLs(for base: URL) -> [URL] {
        // SQLite commonly uses -wal and -shm sidecars when WAL journaling is active
        // Compose manually to append -wal/-shm
        let walURL = URL(fileURLWithPath: base.path + "-wal")
        let shmURL = URL(fileURLWithPath: base.path + "-shm")
        return [walURL, shmURL]
    }

    nonisolated private static func makeBackupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: Date())
    }

    // Run a throwing closure on a background utility queue and block until it finishes
    nonisolated private static func runBlockingOnUtilityQueue<T>(_ work: @escaping () throws -> T)
        throws -> T
    {
        let group = DispatchGroup()
        group.enter()
        var result: Result<T, Error>!
        DispatchQueue.global(qos: .utility).async {
            do { result = .success(try work()) } catch { result = .failure(error) }
            group.leave()
        }
        group.wait()
        guard let result else {
            preconditionFailure("runBlockingOnUtilityQueue: async work did not assign result")
        }
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

extension BrowserManager.ProfileSwitchContext {
    var shouldProvideFeedback: Bool {
        switch self {
        case .windowActivation:
            return false
        case .spaceChange, .userInitiated, .recovery:
            return true
        }
    }

    var shouldAnimateTransition: Bool {
        switch self {
        case .windowActivation:
            return false
        case .spaceChange, .userInitiated, .recovery:
            return true
        }
    }
}
