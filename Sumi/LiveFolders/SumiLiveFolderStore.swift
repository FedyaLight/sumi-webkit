import Foundation

actor SumiLiveFolderStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = SumiLiveFolderStore.defaultStoreURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    enum StoreError: Error {
        case verificationFailed
    }

    func load() throws -> SumiLiveFolderDiskState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.sumiLiveFolders.decode(
            SumiLiveFolderDiskState.self,
            from: data
        )
    }

    func save(_ state: SumiLiveFolderDiskState) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.sumiLiveFolders.encode(state)
        try data.write(to: fileURL, options: [.atomic])
        guard try Data(contentsOf: fileURL) == data else {
            throw StoreError.verificationFailed
        }
    }

    func normalizeLegacyProfileReferences() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let state = try load()
        try save(state)
        guard try load() == state else {
            throw StoreError.verificationFailed
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
