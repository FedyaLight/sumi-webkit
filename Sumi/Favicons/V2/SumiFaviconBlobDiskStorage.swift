import Foundation
import OSLog

/// Physical favicon storage. It knows paths and atomic file operations, but has
/// no metadata cache, indexing rules, or scheduling state.
final class SumiFaviconBlobDiskStorage {
    private static let log = Logger.sumi(category: "FaviconBlobDiskStorage")

    let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL, fileManager: FileManager) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        } catch {
            Self.log.error(
                "Failed to create favicon blob root directory: \(String(describing: error), privacy: .public)"
            )
        }
    }

    @discardableResult
    func writeBlobIfMissing(
        _ data: Data,
        fileName: String,
        partition: SumiFaviconPartition
    ) throws -> Bool {
        precondition(!partition.isPrivate)
        let directory = blobDirectory(for: partition)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(fileName)
        guard !fileManager.fileExists(atPath: destination.path) else { return false }
        try data.write(to: destination, options: [.atomic])
        return true
    }

    func readBlob(
        fileName: String,
        partition: SumiFaviconPartition
    ) throws -> Data? {
        precondition(!partition.isPrivate)
        do {
            return try Data(contentsOf: blobURL(fileName: fileName, partition: partition))
        } catch where Self.isMissingFileError(error) {
            return nil
        }
    }

    @discardableResult
    func removeBlob(
        fileName: String,
        partition: SumiFaviconPartition
    ) throws -> Bool {
        precondition(!partition.isPrivate)
        return try removeItemIfPresent(at: blobURL(fileName: fileName, partition: partition))
    }

    func removePartition(_ partition: SumiFaviconPartition) throws {
        precondition(!partition.isPrivate)
        _ = try removeItemIfPresent(at: partitionDirectory(for: partition))
    }

    func discoverRegularPartitions() throws -> Set<SumiFaviconPartition> {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch where Self.isMissingFileError(error) {
            return []
        }

        return Set(contents.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("profile-") else { return nil }
            return SumiFaviconPartition(
                profileIdentifier: String(name.dropFirst("profile-".count)),
                isPrivate: false
            )
        })
    }

    private func partitionDirectory(for partition: SumiFaviconPartition) -> URL {
        rootDirectory.appendingPathComponent(partition.storageComponent, isDirectory: true)
    }

    private func blobDirectory(for partition: SumiFaviconPartition) -> URL {
        partitionDirectory(for: partition).appendingPathComponent("blobs", isDirectory: true)
    }

    private func blobURL(fileName: String, partition: SumiFaviconPartition) -> URL {
        blobDirectory(for: partition).appendingPathComponent(fileName)
    }

    @discardableResult
    private func removeItemIfPresent(at url: URL) throws -> Bool {
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch where Self.isMissingFileError(error) {
            return true
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && (nsError.code == NSFileNoSuchFileError
                || nsError.code == NSFileReadNoSuchFileError)
    }
}
