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

    init(
        controllerStorageId: UUID?,
        libraryDirectoryProvider: @escaping () -> URL? = {
            FileManager.default.urls(
                for: .libraryDirectory,
                in: .userDomainMask
            ).first
        },
        fileManager: FileManager = .default,
        planner: WebExtensionStorageCleanupPlanner = .shared
    ) {
        self.controllerStorageId = controllerStorageId
        self.libraryDirectoryProvider = libraryDirectoryProvider
        self.fileManager = fileManager
        self.planner = planner
    }

    func directory(for extensionId: String) -> URL? {
        guard let controllerStorageId,
              let libraryDirectory = libraryDirectoryProvider()
        else {
            return nil
        }

        let storageRoot = libraryDirectory
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("WebExtensions", isDirectory: true)
            .appendingPathComponent(controllerStorageId.uuidString.uppercased(), isDirectory: true)
        return try? ExtensionUtils.extensionDirectory(
            forExtensionID: extensionId,
            under: storageRoot
        )
    }

    func hasStoredDataCandidate(for extensionId: String) -> Bool {
        planner.hasStoredDataCandidate(in: snapshot(for: extensionId))
    }

    @discardableResult
    func pruneEmptyOrStateOnlyDirectory(for extensionId: String) -> Bool {
        guard let storageDirectory = directory(for: extensionId) else {
            return false
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
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

        let directoryExists = fileManager.fileExists(atPath: storageDirectory.path)
        guard directoryExists else {
            return Self.emptySnapshot
        }

        let entryNames = ((try? fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []).map(\.lastPathComponent).sorted()

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
