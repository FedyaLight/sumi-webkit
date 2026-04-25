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

    // MARK: - Init
    private init() {
        do {
            self.container = try Self.makePersistentContainerForStartup()
        } catch {
            fatalError(Self.startupFailureMessage(for: error))
        }
    }

    static func makePersistentContainerForStartup() throws -> ModelContainer {
        try makePersistentContainerForStartup(
            openPersistentContainer: Self.openPersistentContainer,
            resetPersistentStore: Self.resetPersistentStore
        )
    }

    static func makePersistentContainerForStartup(
        openPersistentContainer: () throws -> ModelContainer,
        resetPersistentStore: () throws -> Void
    ) throws -> ModelContainer {
        do {
            let resolvedContainer = try openPersistentContainer()
            Self.log.info("SwiftData container initialized successfully.")
            return resolvedContainer
        } catch {
            switch Self.classifyStoreOpenFailure(error) {
            case .diskSpace:
                Self.log.fault(
                    "SwiftData container initialization failed because disk space is insufficient. Local store files were not removed. error=\(String(describing: error), privacy: .public)"
                )
                throw StartupPersistenceError.diskSpace(error)

            case .permissionDenied:
                Self.log.fault(
                    "SwiftData container initialization failed because store access was denied. Local store files were not removed. error=\(String(describing: error), privacy: .public)"
                )
                throw StartupPersistenceError.permissionDenied(error)

            case .resettableLocalStore:
                Self.log.fault(
                    "SwiftData container initialization failed for the local store. Removing local store files and reopening once. error=\(String(describing: error), privacy: .public)"
                )
                do {
                    try resetPersistentStore()
                } catch let resetError {
                    Self.log.fault(
                        "Failed to remove local store files after startup failure: \(String(describing: resetError), privacy: .public)"
                    )
                    throw StartupPersistenceError.resetFailed(
                        initialError: error,
                        resetError: resetError
                    )
                }

                do {
                    let resolvedContainer = try openPersistentContainer()
                    Self.log.notice("Recreated SwiftData store after startup open failure.")
                    return resolvedContainer
                } catch let reopenError {
                    Self.log.fault(
                        "Failed to reopen SwiftData container after recreating local store files. initial=\(String(describing: error), privacy: .public) reopen=\(String(describing: reopenError), privacy: .public)"
                    )
                    throw StartupPersistenceError.reopenFailed(
                        initialError: error,
                        reopenError: reopenError
                    )
                }
            }
        }
    }

    private static func openPersistentContainer() throws -> ModelContainer {
        let config = ModelConfiguration(url: Self.storeURL)
        return try ModelContainer(for: Self.schema, configurations: [config])
    }

    // MARK: - Error Classification
    private enum StoreOpenFailure {
        case diskSpace
        case permissionDenied
        case resettableLocalStore
    }

    private enum StartupPersistenceError: Error {
        case diskSpace(Error)
        case permissionDenied(Error)
        case resetFailed(initialError: Error, resetError: Error)
        case reopenFailed(initialError: Error, reopenError: Error)
    }

    private static func classifyStoreOpenFailure(_ error: Error) -> StoreOpenFailure {
        let ns = error as NSError
        let domain = ns.domain
        let code = ns.code
        let desc = Self.errorDescriptionTree(error)
        let lower = (desc + " " + domain).lowercased()

        if domain == NSPOSIXErrorDomain && code == 28 { return .diskSpace }
        if lower.contains("no space left") || lower.contains("disk full") { return .diskSpace }

        if domain == NSPOSIXErrorDomain && (code == 1 || code == 13) {
            return .permissionDenied
        }
        if domain == NSCocoaErrorDomain
            && (code == NSFileReadNoPermissionError || code == NSFileWriteNoPermissionError)
        {
            return .permissionDenied
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted") {
            return .permissionDenied
        }

        return .resettableLocalStore
    }

    private static func startupFailureMessage(for error: Error) -> String {
        switch error {
        case StartupPersistenceError.diskSpace:
            return "Sumi could not open the local browser store because disk space is insufficient."
        case StartupPersistenceError.permissionDenied:
            return "Sumi could not open the local browser store because store file access was denied."
        case StartupPersistenceError.resetFailed:
            return "Sumi could not remove the failed local browser store."
        case StartupPersistenceError.reopenFailed:
            return "Sumi could not open or recreate the local browser store."
        default:
            return "Sumi could not open the local browser store: \(error)"
        }
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

    nonisolated private static func resetPersistentStore() throws {
        let fm = FileManager.default
        let base = Self.storeURL
        let files = [base] + Self.sidecarURLs(for: base)
        for file in files where fm.fileExists(atPath: file.path) {
            do {
                try fm.removeItem(at: file)
            } catch {
                Self.log.error(
                    "Failed to remove \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                throw error
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
