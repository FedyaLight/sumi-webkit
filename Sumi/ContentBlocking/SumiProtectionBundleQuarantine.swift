import Darwin
import Foundation

/// Owns the deterministic, durable on-disk quarantine layout. The cache
/// transaction remains the sole authority deciding when artifacts enter it.
struct SumiProtectionBundleQuarantine {
    typealias Artifact = (role: String, url: URL)

    private struct Record: Codable {
        let schemaVersion: Int
        let transactionId: String
        let profileId: String
        let currentFailure: String
        let previousFailure: String
    }

    private let profileId: String
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let transactionId: UUID
    private let faultInjector: SumiProtectionBundleCacheTransaction.FaultInjector?

    init(
        profileId: String,
        rootDirectory: URL,
        fileManager: FileManager,
        transactionId: UUID,
        faultInjector: SumiProtectionBundleCacheTransaction.FaultInjector?
    ) {
        self.profileId = profileId
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.transactionId = transactionId
        self.faultInjector = faultInjector
    }

    func publishUnavailableMarker(
        currentFailure: String,
        previousFailure: String
    ) throws {
        let markerURL = SumiRemoteAdblockBundleCache.unavailableMarkerURL(
            profileId: profileId,
            rootDirectory: rootDirectory
        )
        try faultInjector?(.unavailablePublication, markerURL)
        try encodedRecord(
            currentFailure: currentFailure,
            previousFailure: previousFailure
        ).write(to: markerURL, options: .atomic)
        try faultInjector?(.unavailableDurability, markerURL)
        try synchronizeFile(at: markerURL)
        try synchronizeDirectory(at: markerURL.deletingLastPathComponent())
        try synchronizeDirectory(at: rootDirectory)
    }

    func publish(
        artifacts: [Artifact],
        currentFailure: String,
        previousFailure: String
    ) throws {
        try fileManager.createDirectory(
            at: quarantineRoot,
            withIntermediateDirectories: true
        )
        let diagnosticsURL = quarantineRoot.appendingPathComponent(
            "diagnostics.json"
        )
        if !fileManager.fileExists(atPath: diagnosticsURL.path) {
            try encodedRecord(
                currentFailure: currentFailure,
                previousFailure: previousFailure
            ).write(to: diagnosticsURL, options: .atomic)
        }

        var sourceParents = Set<URL>()
        for artifact in artifacts where fileManager.fileExists(
            atPath: artifact.url.path
        ) {
            let destination = quarantineRoot.appendingPathComponent(
                artifact.role,
                isDirectory: true
            )
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw SumiProtectionBundleRemoteUpdateError
                    .cacheQuarantineFailed(
                        "deterministic quarantine destination already contains \(artifact.role)"
                    )
            }
            try faultInjector?(.quarantinePublication, artifact.url)
            try fileManager.moveItem(at: artifact.url, to: destination)
            sourceParents.insert(artifact.url.deletingLastPathComponent())
        }

        try faultInjector?(.quarantineDurability, quarantineRoot)
        try synchronizeFile(at: diagnosticsURL)
        try synchronizeDirectory(at: quarantineRoot)
        try synchronizeDirectory(at: quarantineRoot.deletingLastPathComponent())
        try synchronizeDirectory(
            at: quarantineRoot.deletingLastPathComponent()
                .deletingLastPathComponent()
        )
        try synchronizeDirectory(at: rootDirectory)
        for parent in sourceParents {
            try synchronizeDirectory(at: parent)
        }
    }

    func cleanup(stagingRoot: URL, clearUnavailable: Bool) throws {
        try faultInjector?(.cleanup, stagingRoot)
        if fileManager.fileExists(atPath: stagingRoot.path) {
            try fileManager.removeItem(at: stagingRoot)
        }
        if clearUnavailable {
            let markerURL = SumiRemoteAdblockBundleCache.unavailableMarkerURL(
                profileId: profileId,
                rootDirectory: rootDirectory
            )
            if fileManager.fileExists(atPath: markerURL.path) {
                try fileManager.removeItem(at: markerURL)
            }
        }
        try faultInjector?(
            .cleanupDurability,
            stagingRoot.deletingLastPathComponent()
        )
        try synchronizeDirectory(at: stagingRoot.deletingLastPathComponent())
        try synchronizeDirectory(
            at: SumiRemoteAdblockBundleCache.bundleURL(
                profileId: profileId,
                rootDirectory: rootDirectory
            ).deletingLastPathComponent()
        )
        try synchronizeDirectory(at: rootDirectory)
    }

    func synchronizeBundleTree(at root: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw SumiProtectionBundleRemoteUpdateError.cacheCommitFailed(
                "could not enumerate staged bundle durability boundaries"
            )
        }
        var files = [URL]()
        var directories: [URL] = [root]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey]
            )
            if values.isRegularFile == true {
                files.append(url)
            } else if values.isDirectory == true {
                directories.append(url)
            }
        }
        for file in files.sorted(by: { $0.path < $1.path }) {
            try synchronizeFile(at: file)
        }
        for directory in directories.sorted(by: {
            $0.pathComponents.count > $1.pathComponents.count
        }) {
            try synchronizeDirectory(at: directory)
        }
        try synchronizeDirectory(at: root.deletingLastPathComponent())
        try synchronizeDirectory(
            at: root.deletingLastPathComponent().deletingLastPathComponent()
        )
        try synchronizeDirectory(at: rootDirectory)
    }

    func synchronizeDirectory(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError(path: url.path) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw posixError(path: url.path)
        }
    }

    private var quarantineRoot: URL {
        rootDirectory
            .appendingPathComponent("Quarantine", isDirectory: true)
            .appendingPathComponent(profileId, isDirectory: true)
            .appendingPathComponent(
                transactionId.uuidString.lowercased(),
                isDirectory: true
            )
    }

    private func encodedRecord(
        currentFailure: String,
        previousFailure: String
    ) throws -> Data {
        try JSONEncoder().encode(
            Record(
                schemaVersion: 1,
                transactionId: transactionId.uuidString.lowercased(),
                profileId: profileId,
                currentFailure: currentFailure,
                previousFailure: previousFailure
            )
        )
    }

    private func synchronizeFile(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError(path: url.path) }
        defer { Darwin.close(descriptor) }
        if Darwin.fcntl(descriptor, F_FULLFSYNC) == -1 {
            let code = errno
            guard code == EINVAL || code == ENOTSUP else {
                throw posixError(code: code, path: url.path)
            }
            guard Darwin.fsync(descriptor) == 0 else {
                throw posixError(path: url.path)
            }
        }
    }

    private func posixError(
        code: Int32 = errno,
        path: String
    ) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSFilePathErrorKey: path]
        )
    }
}
