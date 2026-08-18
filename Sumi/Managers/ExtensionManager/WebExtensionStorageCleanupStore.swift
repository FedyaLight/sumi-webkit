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

enum WebExtensionStorageCleanupError: Error, Equatable {
    case storageRootUnavailable
    case removalFailed(String)
    case removalVerificationFailed(String)
}

struct WebExtensionStorageCleanupStore {
    struct StorageSnapshot: Equatable {
        let directoryExists: Bool
        let entryNames: [String]

        private static let stateFileName = "State.plist"

        var hasOnlyPrunableEntries: Bool {
            entryNames.allSatisfy(Self.isPrunableEntryName)
        }

        var hasStoredDataCandidate: Bool {
            !hasOnlyPrunableEntries
        }

        fileprivate static func isPrunableEntryName(_ entryName: String) -> Bool {
            entryName == stateFileName
        }
    }

    private static let logger = Logger.sumi(category: "Extensions")

    private let controllerStorageId: UUID?
    private let libraryDirectoryProvider: () -> URL?
    private let fileManager: FileManager
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
        storageDirectoryNameResolver: @escaping (String) -> String = { $0 }
    ) {
        self.controllerStorageId = controllerStorageId
        self.libraryDirectoryProvider = libraryDirectoryProvider
        self.fileManager = fileManager
        self.storageDirectoryNameResolver = storageDirectoryNameResolver
    }

    /// Enumerates only controller namespace directories in Sumi's WebKit
    /// root. This is intentionally separate from WebsiteDataStore inventory:
    /// the latter can contain hundreds of thousands of files and must not be
    /// walked during ordinary maintenance.
    static func controllerStorageIdentifiers(
        libraryDirectoryProvider: () -> URL? = {
            FileManager.default.urls(
                for: .libraryDirectory,
                in: .userDomainMask
            ).first
        },
        fileManager: FileManager = .default
    ) -> [UUID] {
        guard let libraryDirectory = libraryDirectoryProvider() else { return [] }
        let root = libraryDirectory
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(
                SumiAppIdentity.runtimeBundleIdentifier,
                isDirectory: true
            )
            .appendingPathComponent("WebExtensions", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.compactMap { entry in
            let values = try? entry.resourceValues(
                forKeys: [.isDirectoryKey]
            )
            guard values?.isDirectory == true
            else {
                return nil
            }
            return UUID(uuidString: entry.lastPathComponent)
        }
    }

    func directory(for extensionId: String) -> URL? {
        directoryForStorageName(storageDirectoryNameResolver(extensionId))
    }

    private func directoryForStorageName(_ storageName: String) -> URL? {
        guard let storageRoot = storageRootDirectory() else { return nil }
        do {
            return try ExtensionPathSafety.extensionDirectory(
                for: storageName,
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

    func deleteControllerStorageDirectory() throws {
        guard let storageRoot = storageRootDirectory() else {
            throw WebExtensionStorageCleanupError.storageRootUnavailable
        }
        guard fileManager.fileExists(atPath: storageRoot.path) else { return }

        do {
            try fileManager.removeItem(at: storageRoot)
        } catch {
            throw WebExtensionStorageCleanupError.removalFailed(storageRoot.path)
        }
        guard fileManager.fileExists(atPath: storageRoot.path) == false else {
            throw WebExtensionStorageCleanupError.removalVerificationFailed(
                storageRoot.path
            )
        }
    }

    func deleteStorageDirectory(for extensionId: String) throws {
        guard let storageDirectory = directory(for: extensionId) else {
            throw WebExtensionStorageCleanupError.storageRootUnavailable
        }
        guard fileManager.fileExists(atPath: storageDirectory.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: storageDirectory)
        } catch {
            throw WebExtensionStorageCleanupError.removalFailed(
                storageDirectory.path
            )
        }
        guard fileManager.fileExists(atPath: storageDirectory.path) == false
        else {
            throw WebExtensionStorageCleanupError.removalVerificationFailed(
                storageDirectory.path
            )
        }
    }

    func hasStoredDataCandidate(for extensionId: String) -> Bool {
        snapshot(for: extensionId).hasStoredDataCandidate
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

        guard contents.allSatisfy({
            StorageSnapshot.isPrunableEntryName($0.lastPathComponent)
        }) else {
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
                entryNames: []
            )
        }

        let entryNames = contents.map(\.lastPathComponent).sorted()

        return StorageSnapshot(
            directoryExists: true,
            entryNames: entryNames
        )
    }

    private static var emptySnapshot: StorageSnapshot {
        StorageSnapshot(
            directoryExists: false,
            entryNames: []
        )
    }
}
