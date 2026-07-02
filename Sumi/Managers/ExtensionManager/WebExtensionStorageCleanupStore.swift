//
//  WebExtensionStorageCleanupStore.swift
//  Sumi
//
//  Filesystem-backed storage state for WebExtension cleanup. Runtime controller
//  creation stays with ExtensionManager; this store only uses a resolved
//  controller storage identifier.
//

import Foundation
import OSLog

struct WebExtensionStorageCleanupStore {
    typealias StorageSnapshot = WebExtensionStorageCleanupPlanner.StorageSnapshot

    private static let logger = Logger.sumi(category: "Extensions")

    private let controllerStorageId: UUID?
    private let libraryDirectoryProvider: () -> URL?
    private let fileManager: FileManager
    private let planner: WebExtensionStorageCleanupPlanner
    /// Maps the internal extension id to the directory name WebKit actually
    /// uses (the composed "<bundleId> (<teamId>)" identifier for Safari app
    /// extensions). Defaults to identity for directory-source extensions.
    private let storageDirectoryNameResolver: (String) -> String

    init(
        controllerStorageId: UUID?,
        libraryDirectoryProvider: @escaping () -> URL? = {
            FileManager.default.urls(
                for: .libraryDirectory,
                in: .userDomainMask
            ).first
        },
        fileManager: FileManager = .default,
        planner: WebExtensionStorageCleanupPlanner = .shared,
        storageDirectoryNameResolver: @escaping (String) -> String = { $0 }
    ) {
        self.controllerStorageId = controllerStorageId
        self.libraryDirectoryProvider = libraryDirectoryProvider
        self.fileManager = fileManager
        self.planner = planner
        self.storageDirectoryNameResolver = storageDirectoryNameResolver
    }

    func directory(for extensionId: String) -> URL? {
        directoryForStorageName(storageDirectoryNameResolver(extensionId))
    }

    private func directoryForStorageName(_ storageName: String) -> URL? {
        guard let storageRoot = storageRootDirectory() else { return nil }
        do {
            return try ExtensionUtils.extensionDirectory(
                forExtensionID: storageName,
                under: storageRoot
            )
        } catch {
            Self.logger.debug(
                "Failed to resolve WebExtension storage directory for \(storageName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func storageRootDirectory() -> URL? {
        guard let controllerStorageId,
              let libraryDirectory = libraryDirectoryProvider()
        else {
            return nil
        }

        return libraryDirectory
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("WebExtensions", isDirectory: true)
            .appendingPathComponent(controllerStorageId.uuidString.uppercased(), isDirectory: true)
    }

    /// One-time adoption of a legacy storage directory after the WebKit-facing
    /// identifier changed (bare bundle id → composed "<bundleId> (<teamId>)").
    /// Moves the legacy directory into place when the current directory has no
    /// real data yet, preserving sessions across the identifier migration.
    /// Never touches a current directory that already contains store files.
    func adoptLegacyStorageDirectoryIfNeeded(for extensionId: String) {
        let currentName = storageDirectoryNameResolver(extensionId)
        guard currentName != extensionId,
              let legacyDirectory = directoryForStorageName(extensionId),
              let currentDirectory = directoryForStorageName(currentName),
              fileManager.fileExists(atPath: legacyDirectory.path)
        else {
            return
        }

        if fileManager.fileExists(atPath: currentDirectory.path) {
            let currentSnapshot = snapshotOfDirectory(currentDirectory)
            guard currentSnapshot.hasStoredDataCandidate == false else { return }
            let legacySnapshot = snapshotOfDirectory(legacyDirectory)
            guard legacySnapshot.hasStoredDataCandidate else { return }
            do {
                try fileManager.removeItem(at: currentDirectory)
            } catch {
                Self.logger.error(
                    "Failed to clear prunable WebExtension storage before legacy adoption for \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return
            }
        }

        do {
            try fileManager.moveItem(at: legacyDirectory, to: currentDirectory)
            Self.logger.info(
                "Adopted legacy WebExtension storage for \(extensionId, privacy: .public) into composed identifier directory"
            )
        } catch {
            Self.logger.error(
                "Failed to adopt legacy WebExtension storage for \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func hasStoredDataCandidate(for extensionId: String) -> Bool {
        planner.hasStoredDataCandidate(in: snapshot(for: extensionId))
    }

    @discardableResult
    func pruneEmptyOrStateOnlyDirectory(for extensionId: String) -> Bool {
        guard let storageDirectory = directory(for: extensionId) else {
            return false
        }

        guard fileManager.fileExists(atPath: storageDirectory.path) else {
            return false
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: storageDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            Self.logger.debug(
                "Failed to inspect WebExtension storage directory for \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        guard contents.allSatisfy(planner.isPrunableStorageEntry) else {
            return false
        }

        do {
            try fileManager.removeItem(at: storageDirectory)
            return true
        } catch {
            Self.logger.debug(
                "Failed to prune empty WebExtension storage directory for \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    @discardableResult
    func ensureDirectoryExists(for extensionId: String) -> Bool {
        guard let storageDirectory = directory(for: extensionId) else {
            return false
        }

        do {
            try fileManager.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            Self.logger.debug(
                "Failed to create WebExtension storage directory for \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func snapshot(for extensionId: String) -> StorageSnapshot {
        guard let storageDirectory = directory(for: extensionId) else {
            return Self.emptySnapshot
        }
        return snapshotOfDirectory(storageDirectory)
    }

    private func snapshotOfDirectory(_ storageDirectory: URL) -> StorageSnapshot {
        let directoryExists = fileManager.fileExists(atPath: storageDirectory.path)
        guard directoryExists else {
            return Self.emptySnapshot
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: storageDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            Self.logger.debug(
                "Failed to read WebExtension storage directory snapshot at \(storageDirectory.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return StorageSnapshot(
                directoryExists: true,
                entryNames: [],
                hasRegisteredContentScriptsStore: false,
                hasLocalStorageStore: false,
                hasSyncStorageStore: false
            )
        }

        let entryNames = contents.map(\.lastPathComponent).sorted()

        return StorageSnapshot(
            directoryExists: true,
            entryNames: entryNames,
            hasRegisteredContentScriptsStore: entryNames.contains("RegisteredContentScripts.db"),
            hasLocalStorageStore: entryNames.contains("LocalStorage.db"),
            hasSyncStorageStore: entryNames.contains("SyncStorage.db")
        )
    }

    private static var emptySnapshot: StorageSnapshot {
        StorageSnapshot(
            directoryExists: false,
            entryNames: [],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: false,
            hasSyncStorageStore: false
        )
    }
}
