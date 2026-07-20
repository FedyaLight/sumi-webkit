import Foundation

actor SumiEssentialBackdropDiskStorage {
    private let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        fileManager = .default
    }

    func read(_ key: SumiEssentialBackdropKey.StoredKey) throws -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: key))
        } catch where Self.isMissingFileError(error) {
            return nil
        }
    }

    func write(
        _ data: Data,
        for key: SumiEssentialBackdropKey.StoredKey
    ) throws {
        let directory = partitionDirectory(key.partitionComponent)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL(for: key), options: [.atomic])
    }

    func remove(_ key: SumiEssentialBackdropKey.StoredKey) throws {
        do {
            try fileManager.removeItem(at: fileURL(for: key))
        } catch where Self.isMissingFileError(error) {
            return
        }
    }

    func remove(
        _ key: SumiEssentialBackdropKey.StoredKey,
        ifMatching expectedData: Data
    ) throws {
        let url = fileURL(for: key)
        do {
            guard try Data(contentsOf: url) == expectedData else { return }
            try fileManager.removeItem(at: url)
        } catch where Self.isMissingFileError(error) {
            return
        }
    }

    func existingKeys() throws -> Set<SumiEssentialBackdropKey.StoredKey> {
        let partitions: [URL]
        do {
            partitions = try fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch where Self.isMissingFileError(error) {
            return []
        }

        var keys = Set<SumiEssentialBackdropKey.StoredKey>()
        for partitionURL in partitions {
            guard (try? partitionURL.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory) == true else { continue }
            let files = try fileManager.contentsOfDirectory(
                at: partitionURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for fileURL in files where fileURL.pathExtension == "png" {
                keys.insert(SumiEssentialBackdropKey.StoredKey(
                    partitionComponent: partitionURL.lastPathComponent,
                    fileName: fileURL.lastPathComponent
                ))
            }
        }
        return keys
    }

    private func partitionDirectory(_ component: String) -> URL {
        rootDirectory.appendingPathComponent(component, isDirectory: true)
    }

    private func fileURL(
        for key: SumiEssentialBackdropKey.StoredKey
    ) -> URL {
        partitionDirectory(key.partitionComponent)
            .appendingPathComponent(key.fileName, isDirectory: false)
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError
                || error.code == NSFileReadNoSuchFileError)
    }
}
