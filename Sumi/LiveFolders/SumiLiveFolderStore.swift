import Foundation
import OSLog

actor SumiLiveFolderStore {
    private static let log = Logger.sumi(category: "LiveFolders")
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = SumiLiveFolderStore.defaultStoreURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() -> SumiLiveFolderDiskState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder.sumiLiveFolders.decode(SumiLiveFolderDiskState.self, from: data)
        } catch {
            Self.log.error("Failed to read live folders state: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }

    func save(_ state: SumiLiveFolderDiskState) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.sumiLiveFolders.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            Self.log.error("Failed to write live folders state: \(String(describing: error), privacy: .public)")
        }
    }

    nonisolated static func defaultStoreURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["SUMI_APP_SUPPORT_OVERRIDE"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
                .appendingPathComponent("live-folders.json", isDirectory: false)
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
        return directory.appendingPathComponent("live-folders.json", isDirectory: false)
    }
}

private extension JSONEncoder {
    static var sumiLiveFolders: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var sumiLiveFolders: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
