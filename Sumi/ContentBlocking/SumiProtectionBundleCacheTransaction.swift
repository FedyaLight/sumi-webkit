import Foundation
import OSLog

protocol SumiProtectionBundlePayloadValidating: Sendable {
    func validateBundle(
        at bundleURL: URL,
        expectedIdentity: SumiProtectionBundleIdentity
    ) throws
}

struct SumiProtectionBundleCacheMetadataReader: @unchecked Sendable {
    private static let log = Logger.sumi(category: "ContentBlocking")
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func read(from bundleURL: URL) -> SumiAdblockPreparedBundleRemoteMetadata? {
        let metadataURL = bundleURL.appendingPathComponent(SumiRemoteAdblockBundleCache.metadataFileName)
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(
                SumiAdblockPreparedBundleRemoteMetadata.self,
                from: Data(contentsOf: metadataURL)
            )
        } catch {
            Self.log.error(
                "Failed to read remote adblock bundle metadata at \(metadataURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

struct SumiProtectionNativeBundlePayloadValidator: SumiProtectionBundlePayloadValidating, @unchecked Sendable {
    private let bundleReader: SumiAdblockNativeBundleReader

    init(fileManager: FileManager = .default) {
        bundleReader = SumiAdblockNativeBundleReader(fileManager: fileManager)
    }

    func validateBundle(
        at bundleURL: URL,
        expectedIdentity: SumiProtectionBundleIdentity
    ) throws {
        let bundle = try bundleReader.load(from: bundleURL)
        guard bundle.manifest.profileId == expectedIdentity.profileId,
              bundle.manifest.bundleId == expectedIdentity.bundleId,
              bundle.manifest.generationId == expectedIdentity.generationId
        else {
            throw SumiProtectionBundleRemoteUpdateError.bundleMetadataMismatch(
                "expected \(expectedIdentity.bundleId)/\(expectedIdentity.generationId), got \(bundle.manifest.bundleId)/\(bundle.manifest.generationId)"
            )
        }
    }
}

struct SumiProtectionBundleCache: @unchecked Sendable {
    private static let publicationLock = NSLock()

    let rootDirectory: URL
    let fileManager: FileManager

    init(
        rootDirectory: URL = SumiRemoteAdblockBundleCache.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func remoteMetadata(profileId: String) -> SumiAdblockPreparedBundleRemoteMetadata? {
        let bundleURL = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: rootDirectory
        )
        return SumiProtectionBundleCacheMetadataReader(fileManager: fileManager)
            .read(from: bundleURL)
    }

    func rejectDowngradeIfNeeded(profileId: String, incomingReleaseVersion: String) throws {
        let bundleURL = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: rootDirectory
        )
        let metadataURL = bundleURL.appendingPathComponent(SumiRemoteAdblockBundleCache.metadataFileName)
        guard fileManager.fileExists(atPath: metadataURL.path) else { return }
        let current: String
        do {
            current = try JSONDecoder().decode(
                SumiAdblockPreparedBundleRemoteMetadata.self,
                from: Data(contentsOf: metadataURL)
            ).releaseVersion
        } catch {
            throw SumiProtectionBundleRemoteUpdateError.cacheCommitFailed(
                "installed release metadata is unreadable; refusing an unversioned replacement: \(error.localizedDescription)"
            )
        }
        guard incomingReleaseVersion.compare(current, options: [.numeric]) != .orderedAscending else {
            throw SumiProtectionBundleRemoteUpdateError.releaseDowngradeRejected(
                current: current,
                incoming: incomingReleaseVersion
            )
        }
    }

    func commit(
        _ transaction: SumiProtectionBundleCacheTransaction,
        expectedIdentity: SumiProtectionBundleIdentity,
        incomingReleaseVersion: String
    ) throws -> URL {
        Self.publicationLock.lock()
        defer { Self.publicationLock.unlock() }
        // Recheck while holding the process-wide publication lock. A slower
        // download, including one owned by another updater instance, cannot
        // replace a release installed while it was suspended.
        try rejectDowngradeIfNeeded(
            profileId: expectedIdentity.profileId,
            incomingReleaseVersion: incomingReleaseVersion
        )
        return try transaction.commit(expectedIdentity: expectedIdentity)
    }
}

final class SumiProtectionBundleCacheTransaction {
    private let profileId: String
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let payloadValidator: any SumiProtectionBundlePayloadValidating
    private let stagingRoot: URL
    let stagedBundleURL: URL
    private var committed = false

    init(
        profileId: String,
        rootDirectory: URL = SumiRemoteAdblockBundleCache.defaultRootDirectory(),
        fileManager: FileManager = .default,
        payloadValidator: any SumiProtectionBundlePayloadValidating = SumiProtectionNativeBundlePayloadValidator()
    ) throws {
        self.profileId = profileId
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.payloadValidator = payloadValidator
        stagingRoot = rootDirectory
            .appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        stagedBundleURL = stagingRoot
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
        try fileManager.createDirectory(at: stagedBundleURL, withIntermediateDirectories: true)
    }

    deinit {
        removeIfPresent(stagingRoot)
    }

    func write(_ data: Data, relativePath: String) throws {
        let destination = try safeDestinationURL(relativePath: relativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    func writeMetadata(_ metadata: SumiAdblockPreparedBundleRemoteMetadata) throws {
        try JSONEncoder().encode(metadata).write(
            to: stagedBundleURL.appendingPathComponent(SumiRemoteAdblockBundleCache.metadataFileName),
            options: .atomic
        )
    }

    func commit(expectedIdentity: SumiProtectionBundleIdentity) throws -> URL {
        precondition(!committed, "A protection bundle cache transaction may commit only once")
        guard expectedIdentity.profileId == profileId else {
            throw SumiProtectionBundleRemoteUpdateError.bundleMetadataMismatch(
                "cache transaction profile \(profileId) does not match \(expectedIdentity.profileId)"
            )
        }
        try payloadValidator.validateBundle(
            at: stagedBundleURL,
            expectedIdentity: expectedIdentity
        )

        let destination = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: rootDirectory
        )
        let profileRoot = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        let hadPreviousBundle = fileManager.fileExists(atPath: destination.path)

        do {
            if hadPreviousBundle {
                try ContentBlockingItemExchange.swap(destination, stagedBundleURL)
            } else {
                try fileManager.moveItem(at: stagedBundleURL, to: destination)
            }
            try payloadValidator.validateBundle(
                at: destination,
                expectedIdentity: expectedIdentity
            )
        } catch {
            let commitDescription = error.localizedDescription
            do {
                if hadPreviousBundle {
                    try ContentBlockingItemExchange.swap(destination, stagedBundleURL)
                } else {
                    removeIfPresent(destination)
                }
            } catch let rollbackError {
                throw SumiProtectionBundleRemoteUpdateError.cacheRollbackFailed(
                    commit: commitDescription,
                    rollback: rollbackError.localizedDescription
                )
            }
            throw error
        }

        removeIfPresent(stagingRoot)
        committed = true
        return destination
    }

    private func safeDestinationURL(relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              })
        else {
            throw SumiProtectionBundleRemoteUpdateError.invalidRelativePath(relativePath)
        }
        let destination = stagedBundleURL.appendingPathComponent(relativePath)
        let root = stagedBundleURL.standardizedFileURL.path
        let candidate = destination.standardizedFileURL.path
        guard candidate.hasPrefix(root + "/") else {
            throw SumiProtectionBundleRemoteUpdateError.invalidRelativePath(relativePath)
        }
        return destination
    }

    private func removeIfPresent(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }
}
