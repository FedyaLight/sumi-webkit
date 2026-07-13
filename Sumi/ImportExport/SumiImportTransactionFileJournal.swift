import Darwin
import Foundation

enum SumiImportTransactionJournalFileOperation: Equatable, Sendable {
    case beginLoad
    case beginSave(SumiImportTransactionPhase)
    case createJournalDirectory
    case synchronizeExistingDirectoryParent
    case synchronizeJournalDirectoryParent
    case writeTemporaryFile(SumiImportTransactionPhase)
    case synchronizeTemporaryFile(SumiImportTransactionPhase)
    case closeTemporaryFileAfterFailure(SumiImportTransactionPhase)
    case discardTemporaryFile(SumiImportTransactionPhase)
    case publishPhase(SumiImportTransactionPhase)
    case synchronizePublishedPhase(SumiImportTransactionPhase)
    case beginClear
    case retireCompletedJournal
    case synchronizeRetiredCompletedJournal
    case removeCompletedJournal
    case synchronizeCompletedRemoval
    case closeDirectoryAfterFailure
}

struct SumiImportTransactionFileJournal: SumiImportTransactionJournal, Sendable {
    typealias OperationHook = @Sendable (SumiImportTransactionJournalFileOperation) throws -> Void
    typealias ApplicationSupportDirectoryProvider = @Sendable () -> URL?

    private enum Location: Sendable {
        case defaultApplicationSupport
        case explicit(URL)
    }

    private static let ioQueue = DispatchQueue(
        label: "com.sumi.browser.import-transaction-journal",
        qos: .utility
    )

    private let location: Location
    private let applicationSupportDirectoryProvider: ApplicationSupportDirectoryProvider
    private let operationHook: OperationHook

    init(
        fileURL: URL? = nil,
        applicationSupportDirectoryProvider: @escaping ApplicationSupportDirectoryProvider = {
            if let overridePath = ProcessInfo.processInfo.environment[
                "SUMI_APP_SUPPORT_OVERRIDE"
            ], !overridePath.isEmpty {
                return URL(fileURLWithPath: overridePath, isDirectory: true)
            }
            return FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?.appendingPathComponent(
                SumiAppIdentity.runtimeBundleIdentifier,
                isDirectory: true
            )
        },
        operationHook: @escaping OperationHook = { _ in }
    ) {
        location = fileURL.map(Location.explicit) ?? .defaultApplicationSupport
        self.applicationSupportDirectoryProvider = applicationSupportDirectoryProvider
        self.operationHook = operationHook
    }

    func load() async throws -> SumiImportTransactionJournalRecord? {
        let location = location
        let applicationSupportDirectoryProvider = applicationSupportDirectoryProvider
        let operationHook = operationHook
        return try await Self.performOffMain {
            let fileURL = try Self.resolveFileURL(
                location,
                applicationSupportDirectoryProvider: applicationSupportDirectoryProvider
            )
            try operationHook(.beginLoad)
            return try Self.loadRecord(fileURL: fileURL)
        }
    }

    func save(_ record: SumiImportTransactionJournalRecord) async throws {
        let location = location
        let applicationSupportDirectoryProvider = applicationSupportDirectoryProvider
        let operationHook = operationHook
        try await Self.performOffMain {
            let fileURL = try Self.resolveFileURL(
                location,
                applicationSupportDirectoryProvider: applicationSupportDirectoryProvider
            )
            try operationHook(.beginSave(record.phase))
            let tombstoneURL = Self.tombstoneURL(for: fileURL)
            let hasPublishedJournal = FileManager.default.fileExists(atPath: fileURL.path)
                || FileManager.default.fileExists(atPath: tombstoneURL.path)
            try Self.ensureJournalDirectory(
                fileURL.deletingLastPathComponent(),
                verifyExistingDirectoryPublication: !hasPublishedJournal,
                operationHook: operationHook
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(record)
            try Self.publish(
                data,
                phase: record.phase,
                to: fileURL,
                operationHook: operationHook
            )
        }
    }

    func clear() async throws {
        let location = location
        let applicationSupportDirectoryProvider = applicationSupportDirectoryProvider
        let operationHook = operationHook
        try await Self.performOffMain {
            let fileURL = try Self.resolveFileURL(
                location,
                applicationSupportDirectoryProvider: applicationSupportDirectoryProvider
            )
            let directory = fileURL.deletingLastPathComponent()
            let tombstoneURL = Self.tombstoneURL(for: fileURL)
            try operationHook(.beginClear)
            let hasActiveJournal = FileManager.default.fileExists(atPath: fileURL.path)
            let hasTombstone = FileManager.default.fileExists(atPath: tombstoneURL.path)
            guard hasActiveJournal || hasTombstone else { return }
            try Self.ensureJournalDirectory(
                directory,
                verifyExistingDirectoryPublication: false,
                operationHook: operationHook
            )

            if hasActiveJournal {
                let record = try Self.decodeRecord(at: fileURL)
                guard record.phase == .completed else {
                    throw SumiImportTransactionJournalError.refusingToClearUncompleted(
                        record.phase
                    )
                }

                if hasTombstone {
                    try Self.validateCompletedTombstone(at: tombstoneURL)
                    try Self.removeCompletedTombstone(
                        tombstoneURL,
                        directory: directory,
                        operationHook: operationHook
                    )
                }

                try operationHook(.retireCompletedJournal)
                guard Darwin.renamex_np(
                    fileURL.path,
                    tombstoneURL.path,
                    UInt32(RENAME_EXCL)
                ) == 0 else {
                    let code = errno
                    throw Self.posixError(
                        code,
                        "rename completed import journal",
                        path: fileURL.path
                    )
                }
                try Self.synchronizeDirectory(
                    directory,
                    operation: .synchronizeRetiredCompletedJournal,
                    operationHook: operationHook
                )
            } else if hasTombstone {
                try Self.validateCompletedTombstone(at: tombstoneURL)
            }

            try Self.removeCompletedTombstone(
                tombstoneURL,
                directory: directory,
                operationHook: operationHook
            )
        }
    }

    private static func performOffMain<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withTaskExecutorPreference(ioQueue, isolation: nil) {
            try operation()
        }
    }

    private static func resolveFileURL(
        _ location: Location,
        applicationSupportDirectoryProvider: ApplicationSupportDirectoryProvider
    ) throws -> URL {
        switch location {
        case .explicit(let fileURL):
            return fileURL
        case .defaultApplicationSupport:
            guard let directory = applicationSupportDirectoryProvider() else {
                throw SumiImportTransactionJournalError.applicationSupportUnavailable
            }
            return directory.appendingPathComponent(
                "ImportTransaction.json",
                isDirectory: false
            )
        }
    }

    private static func loadRecord(
        fileURL: URL
    ) throws -> SumiImportTransactionJournalRecord? {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try decodeRecord(at: fileURL)
        }
        let tombstoneURL = tombstoneURL(for: fileURL)
        guard FileManager.default.fileExists(atPath: tombstoneURL.path) else {
            return nil
        }
        let record = try decodeRecord(at: tombstoneURL)
        guard record.phase == .completed else {
            throw SumiImportTransactionJournalError.invalidCompletedTombstone(record.phase)
        }
        return record
    }

    private static func decodeRecord(
        at url: URL
    ) throws -> SumiImportTransactionJournalRecord {
        let record = try JSONDecoder().decode(
            SumiImportTransactionJournalRecord.self,
            from: Data(contentsOf: url)
        )
        guard record.version == SumiImportTransactionJournalRecord.currentVersion else {
            throw SumiImportTransactionJournalError.unsupportedVersion(record.version)
        }
        return record
    }

    private static func validateCompletedTombstone(at url: URL) throws {
        let record = try decodeRecord(at: url)
        guard record.phase == .completed else {
            throw SumiImportTransactionJournalError.invalidCompletedTombstone(record.phase)
        }
    }

    private static func publish(
        _ data: Data,
        phase: SumiImportTransactionPhase,
        to fileURL: URL,
        operationHook: OperationHook
    ) throws {
        let directory = fileURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)",
            isDirectory: false
        )
        var temporaryExists = false
        var openDescriptor: Int32?
        do {
            try operationHook(.writeTemporaryFile(phase))
            let descriptor = Darwin.open(
                temporaryURL.path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(S_IRUSR | S_IWUSR)
            )
            guard descriptor >= 0 else {
                let code = errno
                throw posixError(code, "open temporary import journal", path: temporaryURL.path)
            }
            openDescriptor = descriptor
            temporaryExists = true

            try writeAll(data, to: descriptor, path: temporaryURL.path)
            try operationHook(.synchronizeTemporaryFile(phase))
            try synchronizeDescriptor(descriptor, path: temporaryURL.path)
            openDescriptor = nil
            try closeDescriptor(descriptor, path: temporaryURL.path)

            try operationHook(.publishPhase(phase))
            guard Darwin.rename(temporaryURL.path, fileURL.path) == 0 else {
                let code = errno
                throw posixError(code, "publish import journal", path: fileURL.path)
            }
            temporaryExists = false
            try synchronizeDirectory(
                directory,
                operation: .synchronizePublishedPhase(phase),
                operationHook: operationHook
            )
        } catch let operationError {
            var cleanupErrors: [Error] = []
            if let descriptor = openDescriptor {
                do {
                    try operationHook(.closeTemporaryFileAfterFailure(phase))
                } catch {
                    cleanupErrors.append(error)
                }
                if Darwin.close(descriptor) != 0 {
                    let code = errno
                    cleanupErrors.append(
                        posixError(code, "close failed temporary import journal", path: temporaryURL.path)
                    )
                }
            }
            if temporaryExists {
                do {
                    try operationHook(.discardTemporaryFile(phase))
                    if Darwin.unlink(temporaryURL.path) != 0 {
                        let code = errno
                        cleanupErrors.append(
                            posixError(code, "discard temporary import journal", path: temporaryURL.path)
                        )
                    }
                } catch {
                    cleanupErrors.append(error)
                }
            }
            guard !cleanupErrors.isEmpty else { throw operationError }
            throw SumiImportTransactionJournalFileFailure(
                operationError: operationError,
                cleanupErrors: cleanupErrors
            )
        }
    }

    private static func ensureJournalDirectory(
        _ directory: URL,
        verifyExistingDirectoryPublication: Bool,
        operationHook: OperationHook
    ) throws {
        var missingDirectories: [URL] = []
        var candidate = directory.standardizedFileURL
        let fileManager = FileManager.default

        while !isDirectory(candidate, fileManager: fileManager) {
            guard !fileManager.fileExists(atPath: candidate.path) else {
                throw posixError(ENOTDIR, "resolve import journal directory", path: candidate.path)
            }
            missingDirectories.append(candidate)
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else {
                throw posixError(ENOENT, "resolve import journal directory", path: candidate.path)
            }
            candidate = parent
        }

        if verifyExistingDirectoryPublication && missingDirectories.isEmpty {
            try synchronizeDirectory(
                candidate.deletingLastPathComponent(),
                operation: .synchronizeExistingDirectoryParent,
                operationHook: operationHook
            )
        }

        for newDirectory in missingDirectories.reversed() {
            try operationHook(.createJournalDirectory)
            if Darwin.mkdir(newDirectory.path, mode_t(S_IRWXU)) != 0 {
                let code = errno
                guard code == EEXIST,
                      isDirectory(newDirectory, fileManager: fileManager)
                else {
                    throw posixError(code, "create import journal directory", path: newDirectory.path)
                }
            }
            try synchronizeDirectory(
                newDirectory.deletingLastPathComponent(),
                operation: .synchronizeJournalDirectoryParent,
                operationHook: operationHook
            )
        }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func removeCompletedTombstone(
        _ tombstoneURL: URL,
        directory: URL,
        operationHook: OperationHook
    ) throws {
        try operationHook(.removeCompletedJournal)
        guard Darwin.unlink(tombstoneURL.path) == 0 else {
            let code = errno
            throw posixError(code, "remove completed import journal", path: tombstoneURL.path)
        }
        try synchronizeDirectory(
            directory,
            operation: .synchronizeCompletedRemoval,
            operationHook: operationHook
        )
    }

    private static func synchronizeDirectory(
        _ directory: URL,
        operation: SumiImportTransactionJournalFileOperation,
        operationHook: OperationHook
    ) throws {
        try operationHook(operation)
        let descriptor = Darwin.open(
            directory.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            let code = errno
            throw posixError(code, "open import journal directory", path: directory.path)
        }
        do {
            try synchronizeDescriptor(descriptor, path: directory.path)
        } catch let operationError {
            var cleanupErrors: [Error] = []
            do {
                try operationHook(.closeDirectoryAfterFailure)
            } catch {
                cleanupErrors.append(error)
            }
            if Darwin.close(descriptor) != 0 {
                let code = errno
                cleanupErrors.append(
                    posixError(code, "close failed import journal directory", path: directory.path)
                )
            }
            guard !cleanupErrors.isEmpty else { throw operationError }
            throw SumiImportTransactionJournalFileFailure(
                operationError: operationError,
                cleanupErrors: cleanupErrors
            )
        }
        try closeDescriptor(descriptor, path: directory.path)
    }

    private static func writeAll(_ data: Data, to descriptor: Int32, path: String) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard var cursor = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.write(descriptor, cursor, remaining)
                if written < 0 {
                    let code = errno
                    if code == EINTR { continue }
                    throw posixError(code, "write temporary import journal", path: path)
                }
                guard written > 0 else {
                    throw posixError(EIO, "write temporary import journal", path: path)
                }
                remaining -= written
                cursor = cursor.advanced(by: written)
            }
        }
    }

    private static func synchronizeDescriptor(_ descriptor: Int32, path: String) throws {
        while Darwin.fsync(descriptor) != 0 {
            let code = errno
            if code == EINTR { continue }
            throw posixError(code, "fsync import journal", path: path)
        }
        while Darwin.fcntl(descriptor, F_FULLFSYNC) != 0 {
            let code = errno
            if code == EINTR { continue }
            throw posixError(code, "F_FULLFSYNC import journal", path: path)
        }
    }

    private static func closeDescriptor(_ descriptor: Int32, path: String) throws {
        guard Darwin.close(descriptor) == 0 else {
            let code = errno
            throw posixError(code, "close import journal", path: path)
        }
    }

    private static func tombstoneURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("completed-cleanup")
    }

    private static func posixError(
        _ code: Int32,
        _ operation: String,
        path: String
    ) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey: "Failed to \(operation) at \(path): \(String(cString: strerror(code)))"
            ]
        )
    }
}
