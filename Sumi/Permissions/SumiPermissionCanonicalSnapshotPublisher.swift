import Darwin
import Foundation

private final class SumiPermissionDirectoryDurabilityState: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingCreatedDirectoryParents: [URL] = []

    func recordCreatedDirectories(_ directories: [URL]) {
        lock.withLock {
            for directory in directories {
                appendUnique(directory.deletingLastPathComponent())
            }
        }
    }

    func requiredBarriers(for permissionDirectory: URL) -> [URL] {
        lock.withLock {
            var barriers: [URL] = []
            appendUnique(permissionDirectory, to: &barriers)
            appendUnique(permissionDirectory.deletingLastPathComponent(), to: &barriers)
            for directory in pendingCreatedDirectoryParents {
                appendUnique(directory, to: &barriers)
            }
            return barriers
        }
    }

    func acknowledgeBarriers() {
        lock.withLock {
            pendingCreatedDirectoryParents.removeAll(keepingCapacity: true)
        }
    }

    private func appendUnique(_ url: URL) {
        appendUnique(url, to: &pendingCreatedDirectoryParents)
    }

    private func appendUnique(_ url: URL, to urls: inout [URL]) {
        let standardizedURL = url.standardizedFileURL
        guard !urls.contains(where: { $0.standardizedFileURL == standardizedURL }) else { return }
        urls.append(standardizedURL)
    }
}

/// Publishes one permission snapshot using a same-directory temporary file and
/// an atomic rename. The stage hook exists only for focused fault testing.
struct SumiPermissionCanonicalSnapshotPublisher: @unchecked Sendable {
    enum Stage: CaseIterable, Equatable, Sendable {
        case encode
        case temporaryWrite
        case temporaryFileSync
        case atomicReplace
        case parentDirectorySync
    }

    typealias FaultInjector = @Sendable (Stage, URL) throws -> Void

    let fileURL: URL
    private let faultInjector: FaultInjector?
    private let directoryDurabilityState = SumiPermissionDirectoryDurabilityState()

    init(fileURL: URL, faultInjector: FaultInjector? = nil) {
        self.fileURL = fileURL
        self.faultInjector = faultInjector
    }

    var canonicalFileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func publish(_ envelope: SumiPermissionPersistenceEnvelope) throws {
        try faultInjector?(.encode, fileURL)
        let data = try JSONEncoder().encode(envelope)

        let directoryURL = fileURL.deletingLastPathComponent()
        let newlyCreatedDirectories = missingDirectoryChain(endingAt: directoryURL)
        directoryDurabilityState.recordCreatedDirectories(newlyCreatedDirectories)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try faultInjector?(.temporaryWrite, temporaryURL)
        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try faultInjector?(.temporaryFileSync, temporaryURL)
        try synchronizeFile(at: temporaryURL)

        try faultInjector?(.atomicReplace, fileURL)
        guard rename(temporaryURL.path, fileURL.path) == 0 else {
            throw posixError(path: fileURL.path)
        }

        // The rename changes directory metadata. Synchronize that directory,
        // then every parent that gained a directory entry during first publish.
        for barrierURL in directoryDurabilityState.requiredBarriers(for: directoryURL) {
            try faultInjector?(.parentDirectorySync, barrierURL)
            try synchronizeDirectory(at: barrierURL)
        }
        directoryDurabilityState.acknowledgeBarriers()
    }

    private func missingDirectoryChain(endingAt directoryURL: URL) -> [URL] {
        var missing: [URL] = []
        var cursor = directoryURL.standardizedFileURL
        while !FileManager.default.fileExists(atPath: cursor.path) {
            missing.append(cursor)
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { break }
            cursor = parent
        }
        return missing
    }

    private func synchronizeFile(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw posixError(path: url.path) }
        defer { _ = Darwin.close(descriptor) }

        if fcntl(descriptor, F_FULLFSYNC) != 0 {
            let fullSyncError = errno
            guard fullSyncError == EINVAL || fullSyncError == ENOTSUP else {
                throw posixError(code: fullSyncError, path: url.path)
            }
            guard fsync(descriptor) == 0 else { throw posixError(path: url.path) }
        }
    }

    private func synchronizeDirectory(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw posixError(path: url.path) }
        defer { _ = Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError(path: url.path) }
    }

    private func posixError(code: Int32 = errno, path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSFilePathErrorKey: path]
        )
    }
}
