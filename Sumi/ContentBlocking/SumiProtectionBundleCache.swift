import CryptoKit
import Foundation
import OSLog

struct SumiProtectionBundleValidationReceipt: Equatable, Sendable {
    let identity: SumiProtectionBundleIdentity
    let payloadFingerprint: String
}

protocol SumiProtectionBundlePayloadValidating: Sendable {
    func validateBundle(at bundleURL: URL) throws
        -> SumiProtectionBundleValidationReceipt
}

struct SumiProtectionBundleCacheMetadataReader: @unchecked Sendable {
    private static let log = Logger.sumi(category: "ContentBlocking")
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func read(from bundleURL: URL) -> SumiAdblockPreparedBundleRemoteMetadata? {
        let metadataURL = bundleURL.appendingPathComponent(
            SumiRemoteAdblockBundleCache.metadataFileName
        )
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
        at bundleURL: URL
    ) throws -> SumiProtectionBundleValidationReceipt {
        let bundle = try bundleReader.load(from: bundleURL)
        let payloadFingerprint = try bundleReader
            .validatedPayloadFingerprint(from: bundle)
        let metadataURL = bundleURL.appendingPathComponent(
            SumiRemoteAdblockBundleCache.metadataFileName
        )
        let metadataData = try Data(contentsOf: metadataURL)
        _ = try JSONDecoder().decode(
            SumiAdblockPreparedBundleRemoteMetadata.self,
            from: metadataData
        )
        let metadataFingerprint = SHA256.hash(data: metadataData)
            .map { String(format: "%02x", $0) }
            .joined()
        let exactFingerprint = SHA256.hash(
            data: Data("\(payloadFingerprint):\(metadataFingerprint)".utf8)
        )
        .map { String(format: "%02x", $0) }
        .joined()

        return SumiProtectionBundleValidationReceipt(
            identity: SumiProtectionBundleIdentity(
                profileId: bundle.manifest.profileId,
                bundleId: bundle.manifest.bundleId,
                generationId: bundle.manifest.generationId
            ),
            payloadFingerprint: exactFingerprint
        )
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

    func rejectDowngradeIfNeeded(
        profileId: String,
        incomingReleaseVersion: String
    ) throws {
        let unavailableMarker = SumiRemoteAdblockBundleCache.unavailableMarkerURL(
            profileId: profileId,
            rootDirectory: rootDirectory
        )
        guard !fileManager.fileExists(atPath: unavailableMarker.path) else {
            return
        }
        let bundleURL = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: rootDirectory
        )
        let metadataURL = bundleURL.appendingPathComponent(
            SumiRemoteAdblockBundleCache.metadataFileName
        )
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
        guard incomingReleaseVersion.compare(
            current,
            options: [.numeric]
        ) != .orderedAscending else {
            throw SumiProtectionBundleRemoteUpdateError
                .releaseDowngradeRejected(
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
        try rejectDowngradeIfNeeded(
            profileId: expectedIdentity.profileId,
            incomingReleaseVersion: incomingReleaseVersion
        )
        return try transaction.commit(expectedIdentity: expectedIdentity)
    }
}
