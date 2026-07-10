import Foundation

actor SumiProtectionBundleRemoteUpdater: SumiProtectionBundleRemoteUpdating {
    private let fetcher: any SumiProtectionBundleReleaseFetching
    private let signatureVerifier: any SumiProtectionBundleManifestVerifying
    private let releaseValidator: SumiProtectionBundleReleaseValidator
    private let cache: SumiProtectionBundleCache
    private let payloadValidator: any SumiProtectionBundlePayloadValidating
    private let isoDateFormatter = ISO8601DateFormatter()

    init(
        fetcher: any SumiProtectionBundleReleaseFetching = SumiProtectionBundleGitHubReleaseClient(),
        signatureVerifier: any SumiProtectionBundleManifestVerifying = SumiProtectionBundleSignatureVerifier(),
        rootDirectory: URL = SumiRemoteAdblockBundleCache.defaultRootDirectory(),
        fileManager: FileManager = .default,
        releaseValidator: SumiProtectionBundleReleaseValidator = SumiProtectionBundleReleaseValidator(),
        payloadValidator: (any SumiProtectionBundlePayloadValidating)? = nil
    ) {
        self.fetcher = fetcher
        self.signatureVerifier = signatureVerifier
        self.releaseValidator = releaseValidator
        cache = SumiProtectionBundleCache(rootDirectory: rootDirectory, fileManager: fileManager)
        self.payloadValidator = payloadValidator
            ?? SumiProtectionNativeBundlePayloadValidator(fileManager: fileManager)
    }

    func fetchLatestApprovedBundle(profileId: String) async throws -> SumiProtectionRemoteBundleFetchResult {
        let release = try await fetcher.latestRelease()
        let releaseAssets = try releaseValidator.approvedAssetIndex(for: release)
        guard let manifestAsset = releaseAssets[SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName] else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestAssetMissing(
                SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
            )
        }
        guard let signatureAsset = releaseAssets[SumiProtectionBundleRemoteUpdateConstants.releaseManifestSignatureAssetName] else {
            throw SumiProtectionBundleRemoteUpdateError.releaseManifestSignatureAssetMissing(
                SumiProtectionBundleRemoteUpdateConstants.releaseManifestSignatureAssetName
            )
        }

        let downloader = SumiProtectionBundleAssetDownloader(fetcher: fetcher)
        let manifestData = try await downloader.verifiedData(
            for: manifestAsset,
            expectedHash: SumiProtectionBundleAssetDownloader.githubSHA256(manifestAsset.digest),
            expectedByteSize: manifestAsset.size
        )
        let signatureData = try await downloader.verifiedData(
            for: signatureAsset,
            expectedHash: SumiProtectionBundleAssetDownloader.githubSHA256(signatureAsset.digest),
            expectedByteSize: signatureAsset.size
        )
        let signatureVerification = try signatureVerifier.verify(
            manifestData: manifestData,
            signatureData: signatureData,
            expectedSignedAsset: SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
        )
        let releaseManifest = try JSONDecoder().decode(
            SumiProtectionBundleReleaseManifest.self,
            from: manifestData
        )
        let selection = try releaseValidator.selectBundle(
            in: releaseManifest,
            profileId: profileId,
            releaseAssets: releaseAssets
        )
        try cache.rejectDowngradeIfNeeded(
            profileId: profileId,
            incomingReleaseVersion: releaseManifest.releaseVersion
        )

        let transaction = try SumiProtectionBundleCacheTransaction(
            profileId: profileId,
            rootDirectory: cache.rootDirectory,
            fileManager: cache.fileManager,
            payloadValidator: payloadValidator
        )
        for descriptor in selection.assets {
            try Task.checkCancellation()
            guard let releaseAsset = releaseAssets[descriptor.name] else {
                throw SumiProtectionBundleRemoteUpdateError.assetMissing(descriptor.name)
            }
            let data = try await downloader.verifiedData(
                for: releaseAsset,
                expectedHash: descriptor.sha256,
                expectedByteSize: descriptor.byteSize
            )
            try transaction.write(data, relativePath: descriptor.relativePath)
        }

        let metadata = SumiAdblockPreparedBundleRemoteMetadata(
            releaseVersion: releaseManifest.releaseVersion,
            releaseTag: release.tagName,
            releaseURL: release.htmlURL,
            publishedDate: release.publishedAt.flatMap(isoDateFormatter.date(from:)),
            manifestSignatureRequired: SumiProtectionBundleTrust.remoteManifestSignatureRequired,
            manifestSignatureVerified: true,
            signingKeyId: signatureVerification.keyId,
            signingKeyVersion: signatureVerification.keyVersion
        )
        try transaction.writeMetadata(metadata)
        try Task.checkCancellation()
        let identity = SumiProtectionBundleIdentity(
            profileId: profileId,
            bundleId: selection.bundle.bundleId,
            generationId: selection.bundle.generationId
        )
        let bundleURL = try cache.commit(
            transaction,
            expectedIdentity: identity,
            incomingReleaseVersion: releaseManifest.releaseVersion
        )

        return SumiProtectionRemoteBundleFetchResult(
            profileId: profileId,
            releaseVersion: releaseManifest.releaseVersion,
            releaseTag: release.tagName,
            releaseURL: release.htmlURL,
            publishedDate: metadata.publishedDate,
            manifestSignatureRequired: SumiProtectionBundleTrust.remoteManifestSignatureRequired,
            manifestSignatureVerified: true,
            signingKeyId: signatureVerification.keyId,
            signingKeyVersion: signatureVerification.keyVersion,
            bundleId: identity.bundleId,
            generationId: identity.generationId,
            bundleURL: bundleURL
        )
    }
}
