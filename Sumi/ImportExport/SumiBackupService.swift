import Foundation

@MainActor
final class SumiBackupService {
    private static let maxAutomaticPreRestoreBackups = 5

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func backupData(from browserManager: BrowserManager) -> SumiPortableArchive {
        let data = SumiImportExportSnapshot.makeData(from: browserManager)
        return SumiPortableArchive(
            includedCategories: Array(data.nonEmptyCategories).sorted { $0.rawValue < $1.rawValue },
            warnings: [
                "Backup v1 contains logical Sumi data only. Cookies, passwords, WebKit website data, caches, downloads, history, and extension payloads are not included."
            ],
            settings: [:],
            data: data
        )
    }

    func writeBackup(from browserManager: BrowserManager, to destination: URL) throws {
        let archive = backupData(from: browserManager)
        let payload = try encoder.encode(archive)
        try payload.write(to: destination, options: .atomic)
    }

    func readBackup(from source: URL) throws -> SumiPortableArchive {
        let payload = try Data(contentsOf: source)
        let archive = try decoder.decode(SumiPortableArchive.self, from: payload)
        guard archive.format == SumiPortableArchive.format else {
            throw SumiImportExportError.unsupportedFile("This file is not a Sumi backup.")
        }
        guard archive.version <= SumiPortableArchive.currentVersion else {
            throw SumiImportExportError.unsupportedFile("This Sumi backup was created by a newer version of Sumi.")
        }
        return archive
    }

    func writeAutomaticPreRestoreBackup(from browserManager: BrowserManager) throws -> URL {
        let directory = try automaticBackupDirectory()
        let filename = "pre-restore-\(Self.timestamp()).sumibackup"
        let destination = directory.appendingPathComponent(filename, isDirectory: false)
        try writeBackup(from: browserManager, to: destination)
        try pruneAutomaticPreRestoreBackups(in: directory, keeping: Self.maxAutomaticPreRestoreBackups)
        return destination
    }

    private func automaticBackupDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SumiImportExportError.exportFailed("Application Support is unavailable.")
        }
        let directory = base
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func pruneAutomaticPreRestoreBackups(in directory: URL, keeping limit: Int) throws {
        guard limit > 0 else { return }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let automaticBackups = files
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("pre-restore-") && name.hasSuffix(".sumibackup")
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for stale in automaticBackups.dropFirst(limit) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}

enum SumiImportExportError: LocalizedError {
    case unsupportedFile(String)
    case importFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let message), .importFailed(let message), .exportFailed(let message):
            return message
        }
    }
}
