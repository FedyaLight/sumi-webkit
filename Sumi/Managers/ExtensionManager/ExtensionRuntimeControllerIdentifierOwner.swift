//
//  ExtensionControllerIdentifierOwner.swift
//  Sumi
//
//  Owns WKWebExtensionController identifier allocation and test storage cleanup.
//

import Darwin
import Foundation
import OSLog

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerIdentifierOwner {
    nonisolated private static let log = Logger.sumi(category: "Extensions")

    nonisolated private static let controllerIdentifierKey =
        "\(SumiAppIdentity.bundleIdentifier).WKWebExtensionController.Identifier"
    #if DEBUG
        nonisolated private static let testControllerIdentifiersDefaultsKeyBase =
            "\(SumiAppIdentity.bundleIdentifier).tests.WKWebExtensionController.Identifiers"
        nonisolated private static var testControllerIdentifiersDefaultsKey: String {
            "\(testControllerIdentifiersDefaultsKeyBase).\(ProcessInfo.processInfo.processIdentifier)"
        }
        nonisolated private static let installTestControllerCleanupAtExit: Void = {
            removeInactiveTestWebExtensionControllerStorage()
        }()
    #endif

    private var identifierStorage: UUID?

    var identifier: UUID {
        ensureIdentifier()
    }

    @discardableResult
    private func ensureIdentifier() -> UUID {
        if let identifierStorage {
            return identifierStorage
        }

        let identifier = Self.makeRuntimeControllerIdentifier()
        identifierStorage = identifier
        return identifier
    }

    func removeTestStorageIfNeededForLoadedIdentifier() {
        #if DEBUG
            if let identifierStorage {
                Self.removeTestWebExtensionControllerStorageIfNeeded(
                    for: identifierStorage
                )
            }
        #endif
    }

    /// Test processes are hosted inside Sumi.app and share the real
    /// `~/Library/WebKit/<bundle-id>/WebExtensions` root with the user's
    /// running browser. Every controller identifier a test process allocates
    /// (including profile-derived ones) must be registered here so its
    /// on-disk storage is removed once the test process exits — otherwise
    /// test runs permanently leak controller storage directories into the
    /// user's real WebKit root.
    nonisolated static func registerTestControllerIdentifierIfRunningTests(
        _ controllerIdentifier: UUID
    ) {
        #if DEBUG
            guard RuntimeDiagnostics.isRunningTests else { return }
            _ = installTestControllerCleanupAtExit
            registerTestWebExtensionControllerIdentifier(controllerIdentifier)
        #endif
    }

    private static func makeRuntimeControllerIdentifier() -> UUID {
        #if DEBUG
            if RuntimeDiagnostics.isRunningTests {
                _ = installTestControllerCleanupAtExit
                let uuid = UUID()
                registerTestWebExtensionControllerIdentifier(uuid)
                return uuid
            }
        #endif

        if let raw = UserDefaults.standard.string(forKey: controllerIdentifierKey),
           let uuid = UUID(uuidString: raw) {
            return uuid
        }

        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: controllerIdentifierKey)
        return uuid
    }

    #if DEBUG
        nonisolated private static func registerTestWebExtensionControllerIdentifier(
            _ controllerIdentifier: UUID
        ) {
            var identifiers = UserDefaults.standard.stringArray(
                forKey: testControllerIdentifiersDefaultsKey
            ) ?? []
            identifiers.append(controllerIdentifier.uuidString.uppercased())
            UserDefaults.standard.set(
                Array(Set(identifiers)).sorted(),
                forKey: testControllerIdentifiersDefaultsKey
            )
        }

        nonisolated private static func removeInactiveTestWebExtensionControllerStorage() {
            let defaults = UserDefaults.standard
            let prefix = "\(testControllerIdentifiersDefaultsKeyBase)."
            let processKey = testControllerIdentifiersDefaultsKey
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                guard key != processKey,
                      let rawPID = key.dropFirst(prefix.count).split(separator: ".").first,
                      let pid = pid_t(rawPID),
                      kill(pid, 0) != 0
                else {
                    continue
                }

                let identifiers = defaults.stringArray(forKey: key) ?? []
                removeTestWebExtensionControllerStorage(identifiers: identifiers)
                defaults.removeObject(forKey: key)
            }
        }

        nonisolated private static func removeTestWebExtensionControllerStorage(
            identifiers: [String]
        ) {
            for identifier in identifiers {
                guard let uuid = UUID(uuidString: identifier) else {
                    continue
                }
                removeTestWebExtensionControllerStorageIfNeeded(for: uuid)
            }
        }

        nonisolated private static func removeTestWebExtensionControllerStorageIfNeeded(
            for controllerIdentifier: UUID
        ) {
            guard RuntimeDiagnostics.isRunningTests else {
                return
            }
            guard let libraryDirectory = FileManager.default.urls(
                for: .libraryDirectory,
                in: .userDomainMask
            ).first else {
                return
            }

            let storageURL = libraryDirectory
                .appendingPathComponent("WebKit", isDirectory: true)
                .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
                .appendingPathComponent("WebExtensions", isDirectory: true)
                .appendingPathComponent(controllerIdentifier.uuidString.uppercased(), isDirectory: true)
            do {
                try FileManager.default.removeItem(at: storageURL)
            } catch {
                let nsError = error as NSError
                guard nsError.domain != NSCocoaErrorDomain
                    || nsError.code != NSFileNoSuchFileError
                else {
                    return
                }
                log.error(
                    "Failed to remove test WebExtension controller storage at \(storageURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    #endif
}
