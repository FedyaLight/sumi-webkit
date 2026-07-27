//
//  SumiStartupPersistence.swift
//  Sumi
//
//

import AppKit
import Combine
import CoreServices
import Darwin
import GRDB
import OSLog
import SwiftUI
import WebKit

@MainActor
final class SumiStartupPersistence {
    static let shared = SumiStartupPersistence()
    private let lifetimeLock: SumiStartupStoreIO.LifetimeLock?
    private let databaseResult: Result<SumiDatabase, Error>

    var database: SumiDatabase {
        do {
            return try openDatabase()
        } catch {
            Self.terminateBecauseStartupPersistenceUnavailable(error)
        }
    }

    // MARK: - Constants
    nonisolated private static let log = Logger.sumi(category: "StartupPersistence")
    nonisolated private static let storeFileName = "Sumi.sqlite"
    nonisolated private static let quarantineDirectoryName = "StartupPersistenceQuarantine"

    // MARK: - URLs
    nonisolated private static var appSupportURL: URL {
        SumiApplicationSupportDirectory.appRootURL()
    }

    nonisolated private static var storeURL: URL {
        appSupportURL.appendingPathComponent(storeFileName, isDirectory: false)
    }

    nonisolated private static var quarantineRootURL: URL {
        appSupportURL.appendingPathComponent(quarantineDirectoryName, isDirectory: true)
    }

    // MARK: - Init
    private init() {
        do {
            let lifetimeLock = try SumiStartupStoreIO.LifetimeLock(storeURL: Self.storeURL)
            self.lifetimeLock = lifetimeLock
            self.databaseResult = Result {
                try Self.makePersistentDatabaseForStartup()
            }
        } catch {
            self.lifetimeLock = nil
            self.databaseResult = .failure(
                StartupPersistenceError.storeLockUnavailable(error)
            )
        }
        if case .failure(let error) = databaseResult {
            Self.log.fault(
                "Startup persistence is unavailable. \(Self.startupFailureMessage(for: error), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    func openDatabase() throws -> SumiDatabase {
        try databaseResult.get()
    }

    static func makePersistentDatabaseForStartup() throws -> SumiDatabase {
        try makePersistentDatabaseForStartup(
            storeURL: Self.storeURL,
            quarantineRootURL: Self.quarantineRootURL,
            openDatabase: SumiDatabase.open
        )
    }

    static func makePersistentDatabaseForStartup<Database>(
        storeURL: URL,
        quarantineRootURL: URL,
        performRecoveryOperation: SumiStartupStoreRecovery.RecoveryOperationRunner = { _, operation in
            try operation()
        },
        openDatabase: (URL) throws -> Database
    ) throws -> Database {
        do {
            try SumiStartupStoreRecovery.resumeInterruptedTransition(
                at: storeURL,
                perform: performRecoveryOperation
            )
        } catch {
            throw StartupPersistenceError.interruptedRecoveryFailed(error)
        }

        do {
            let resolvedDatabase = try openDatabase(storeURL)
            Self.log.info("Browser database initialized successfully.")
            return resolvedDatabase
        } catch {
            let diagnostics = Self.classifyStoreOpenFailure(error)
            switch diagnostics.reason {
            case .diskSpace:
                Self.log.fault(
                    "Database initialization failed because disk space is insufficient. Local store files were not removed. error=\(String(describing: error), privacy: .public)"
                )
                throw StartupPersistenceError.diskSpace(error)

            case .permissionDenied:
                Self.log.fault(
                    "Database initialization failed because store access was denied. Local store files were not removed. error=\(String(describing: error), privacy: .public)"
                )
                throw StartupPersistenceError.permissionDenied(error)

            case .schemaMismatch:
                Self.log.fault(
                    "Database initialization failed because the local schema does not match this app version. Local store files were not removed. error=\(String(describing: error), privacy: .public)"
                )
                throw StartupPersistenceError.schemaMismatch(error)

            case .localStoreCorruption:
                return try recoverCorruptStore(
                    at: storeURL,
                    quarantineRootURL: quarantineRootURL,
                    initialError: error,
                    performRecoveryOperation: performRecoveryOperation,
                    openDatabase: openDatabase
                )

            case .unclassified:
                Self.log.fault(
                    "Database initialization failed for an unclassified reason. Local store files were not removed. error=\(String(describing: error), privacy: .public)"
                )
                throw StartupPersistenceError.unclassified(error)
            }
        }
    }

    private static func recoverCorruptStore<Database>(
        at storeURL: URL,
        quarantineRootURL: URL,
        initialError: Error,
        performRecoveryOperation: SumiStartupStoreRecovery.RecoveryOperationRunner,
        openDatabase: (URL) throws -> Database
    ) throws -> Database {
        Self.log.fault(
            "SQLite reported structured database corruption. Preserving the store family before recovery. error=\(String(describing: initialError), privacy: .public)"
        )

        let quarantine: SumiStartupStoreRecovery.Quarantine
        do {
            quarantine = try SumiStartupStoreRecovery.quarantine(
                storeURL: storeURL,
                quarantineRootURL: quarantineRootURL,
                failure: initialError,
                perform: performRecoveryOperation
            )
        } catch let preservationError {
            throw StartupPersistenceError.preservationFailed(
                initialError: initialError,
                preservationError: preservationError
            )
        }

        do {
            try SumiStartupStoreRecovery.restorePreservedFamily(
                from: quarantine,
                to: storeURL,
                perform: performRecoveryOperation
            )
        } catch let preparationError {
            throw StartupPersistenceError.recoveryPreparationFailed(
                initialError: initialError,
                preparationError: preparationError
            )
        }

        do {
            let recoveredDatabase = try openDatabase(storeURL)
            Self.log.notice("Opened the database from the preserved store-family copy.")
            return recoveredDatabase
        } catch let recoveryError {
            let recoveryDiagnostics = Self.classifyStoreOpenFailure(recoveryError)
            guard recoveryDiagnostics.authorizesStoreReplacement else {
                throw StartupPersistenceError.recoveryOpenFailed(
                    initialError: initialError,
                    recoveryError: recoveryError
                )
            }

            do {
                try SumiStartupStoreRecovery.prepareFreshStore(
                    at: storeURL,
                    preserving: quarantine,
                    perform: performRecoveryOperation
                )
            } catch let preparationError {
                throw StartupPersistenceError.freshStorePreparationFailed(
                    initialError: initialError,
                    preparationError: preparationError
                )
            }

            do {
                let freshDatabase = try openDatabase(storeURL)
                Self.log.notice(
                    "Created a fresh database after preserving the corrupt store family at \(quarantine.directoryURL.path, privacy: .public)."
                )
                return freshDatabase
            } catch let freshStoreError {
                throw StartupPersistenceError.freshStoreOpenFailed(
                    initialError: initialError,
                    freshStoreError: freshStoreError
                )
            }
        }
    }

    // MARK: - Error Classification
    enum StoreOpenFailureReason: Equatable {
        case diskSpace
        case permissionDenied
        case schemaMismatch
        case localStoreCorruption
        case unclassified
    }

    struct StoreOpenFailureDiagnostics: Equatable {
        let reason: StoreOpenFailureReason

        var authorizesStoreReplacement: Bool {
            reason == .localStoreCorruption
        }
    }

    private enum StartupPersistenceError: Error {
        case diskSpace(Error)
        case permissionDenied(Error)
        case schemaMismatch(Error)
        case unclassified(Error)
        case preservationFailed(initialError: Error, preservationError: Error)
        case recoveryPreparationFailed(initialError: Error, preparationError: Error)
        case recoveryOpenFailed(initialError: Error, recoveryError: Error)
        case freshStorePreparationFailed(initialError: Error, preparationError: Error)
        case freshStoreOpenFailed(initialError: Error, freshStoreError: Error)
        case interruptedRecoveryFailed(Error)
        case storeLockUnavailable(Error)
    }

    nonisolated static func classifyStoreOpenFailure(_ error: Error) -> StoreOpenFailureDiagnostics {
        if let databaseError = error as? SumiDatabaseError,
           case .unsupportedSchemaVersion = databaseError {
            return StoreOpenFailureDiagnostics(reason: .schemaMismatch)
        }
        if let databaseError = error as? DatabaseError {
            switch databaseError.resultCode {
            case .SQLITE_FULL:
                return StoreOpenFailureDiagnostics(reason: .diskSpace)
            case .SQLITE_PERM, .SQLITE_READONLY, .SQLITE_AUTH:
                return StoreOpenFailureDiagnostics(reason: .permissionDenied)
            case .SQLITE_CORRUPT, .SQLITE_NOTADB:
                return StoreOpenFailureDiagnostics(reason: .localStoreCorruption)
            default:
                break
            }
        }

        let errors = Self.errorTree(error)
        let lower = errors
            .flatMap { [$0.localizedDescription, $0.domain] }
            .joined(separator: " ")
            .lowercased()

        if errors.contains(where: Self.isDiskSpaceError) {
            return StoreOpenFailureDiagnostics(reason: .diskSpace)
        }
        if lower.contains("no space left") || lower.contains("disk full") {
            return StoreOpenFailureDiagnostics(reason: .diskSpace)
        }

        if errors.contains(where: Self.isPermissionError) {
            return StoreOpenFailureDiagnostics(reason: .permissionDenied)
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted") {
            return StoreOpenFailureDiagnostics(reason: .permissionDenied)
        }

        if Self.descriptionIndicatesSchemaMismatch(lower) {
            return StoreOpenFailureDiagnostics(reason: .schemaMismatch)
        }

        if errors.contains(where: Self.isSQLiteCorruption) {
            return StoreOpenFailureDiagnostics(reason: .localStoreCorruption)
        }

        return StoreOpenFailureDiagnostics(reason: .unclassified)
    }

    nonisolated private static func isDiskSpaceError(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain && error.code == ENOSPC {
            return true
        }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
            return true
        }
        return false
    }

    nonisolated private static func isPermissionError(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain && (error.code == EPERM || error.code == EACCES) {
            return true
        }
        if error.domain == NSCocoaErrorDomain
            && (error.code == NSFileReadNoPermissionError || error.code == NSFileWriteNoPermissionError) {
            return true
        }
        return false
    }

    nonisolated private static func descriptionIndicatesSchemaMismatch(
        _ description: String
    ) -> Bool {
        description.contains("unsupported schema version")
            || description.contains("store is incompatible")
            || description.contains("schema does not match")
    }

    nonisolated private static func isSQLiteCorruption(_ error: NSError) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("database disk image is malformed")
            || description.contains("file is not a database")
    }

    private static func startupFailureMessage(for error: Error) -> String {
        switch error {
        case StartupPersistenceError.diskSpace:
            return "Sumi could not open the local browser store because disk space is insufficient."
        case StartupPersistenceError.permissionDenied:
            return "Sumi could not open the local browser store because store file access was denied."
        case StartupPersistenceError.schemaMismatch:
            return "Sumi could not open the local browser store because its schema does not match this app version."
        case StartupPersistenceError.unclassified:
            return "Sumi could not safely classify the local browser store failure. Browser data was not removed."
        case StartupPersistenceError.preservationFailed:
            return "Sumi could not safely preserve the damaged local browser store. Browser data was not removed."
        case StartupPersistenceError.recoveryPreparationFailed:
            return "Sumi preserved the damaged browser store but could not prepare its recovery copy."
        case StartupPersistenceError.recoveryOpenFailed:
            return "Sumi preserved the damaged browser store, but its recovery copy could not be opened safely."
        case StartupPersistenceError.freshStorePreparationFailed:
            return "Sumi preserved the damaged browser store but could not prepare a new local store."
        case StartupPersistenceError.freshStoreOpenFailed:
            return "Sumi preserved the damaged browser store but could not create a new local store."
        case StartupPersistenceError.interruptedRecoveryFailed:
            return "Sumi could not safely complete an interrupted browser store recovery."
        case StartupPersistenceError.storeLockUnavailable:
            return "Sumi could not lock the browser store. Another Sumi process may be using it. Browser data was not changed."
        default:
            return "Sumi could not open the local browser store: \(error)"
        }
    }

    private static func terminateBecauseStartupPersistenceUnavailable(_ error: Error) -> Never {
        let message = startupFailureMessage(for: error)
        log.fault(
            "Terminating because startup persistence is unavailable. \(message, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )

        if NSApplication.shared.isRunning {
            let alert = NSAlert()
            alert.messageText = "Sumi could not open browser data"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }

        Darwin.exit(EXIT_FAILURE)
    }

    nonisolated private static func errorTree(_ error: Error) -> [NSError] {
        var errors: [NSError] = []
        var visited = Set<ObjectIdentifier>()

        func append(_ error: Error) {
            let ns = error as NSError
            let identity = ObjectIdentifier(ns)
            guard !visited.contains(identity) else { return }
            visited.insert(identity)
            errors.append(ns)

            for key in [
                NSUnderlyingErrorKey,
                NSMultipleUnderlyingErrorsKey,
                "NSDetailedErrors",
            ] {
                guard let value = ns.userInfo[key] else { continue }
                switch value {
                case let nested as NSError:
                    append(nested)
                case let nested as Error:
                    append(nested)
                case let nested as [Any]:
                    for value in nested {
                        if let nestedError = value as? Error {
                            append(nestedError)
                        }
                    }
                default:
                    continue
                }
            }
        }

        append(error)
        return errors
    }
}

extension BrowserManager.ProfileSwitchContext {
    var shouldProvideFeedback: Bool {
        switch self {
        case .windowActivation, .profileRetirement:
            return false
        case .spaceChange, .userInitiated, .recovery:
            return true
        }
    }

    var shouldAnimateTransition: Bool {
        switch self {
        case .windowActivation, .profileRetirement:
            return false
        case .spaceChange, .userInitiated, .recovery:
            return true
        }
    }
}
