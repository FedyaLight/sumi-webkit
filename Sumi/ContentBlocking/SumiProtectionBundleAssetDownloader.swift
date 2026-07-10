import CryptoKit
import Foundation

struct SumiProtectionBundleAssetDownloader: Sendable {
    private let fetcher: any SumiProtectionBundleReleaseFetching

    init(fetcher: any SumiProtectionBundleReleaseFetching) {
        self.fetcher = fetcher
    }

    func verifiedData(
        for asset: SumiProtectionBundleGitHubRelease.Asset,
        expectedHash: String?,
        expectedByteSize: Int
    ) async throws -> Data {
        guard expectedByteSize >= 0,
              expectedByteSize <= SumiProtectionBundleRemoteUpdateConstants.maximumAssetByteCount
        else {
            throw SumiProtectionBundleRemoteUpdateError.assetTooLarge(
                name: asset.name,
                byteCount: expectedByteSize
            )
        }
        try Task.checkCancellation()
        let data = try await fetcher.data(from: asset.browserDownloadURL)
        try Task.checkCancellation()
        guard data.count == expectedByteSize else {
            throw SumiProtectionBundleRemoteUpdateError.assetSizeMismatch(
                name: asset.name,
                expected: expectedByteSize,
                actual: data.count
            )
        }
        if let expectedHash {
            let actualHash = Self.sha256Hex(data)
            guard actualHash.caseInsensitiveCompare(expectedHash) == .orderedSame else {
                throw SumiProtectionBundleRemoteUpdateError.assetHashMismatch(
                    name: asset.name,
                    expected: expectedHash,
                    actual: actualHash
                )
            }
        }
        return data
    }

    static func githubSHA256(_ digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        return String(digest.dropFirst("sha256:".count))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
