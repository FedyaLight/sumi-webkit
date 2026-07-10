import Foundation

protocol SumiProtectionBundleReleaseFetching: Sendable {
    func latestRelease() async throws -> SumiProtectionBundleGitHubRelease
    func data(from url: URL) async throws -> Data
}

final class SumiProtectionBundleGitHubReleaseClient: SumiProtectionBundleReleaseFetching, @unchecked Sendable {
    private let latestReleaseURL: URL
    private let session: URLSession

    init(
        owner: String = SumiProtectionBundleRemoteUpdateConstants.owner,
        repository: String = SumiProtectionBundleRemoteUpdateConstants.repository,
        session: URLSession = SumiNonPersistentURLSession.make()
    ) {
        latestReleaseURL = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        self.session = session
    }

    func latestRelease() async throws -> SumiProtectionBundleGitHubRelease {
        let data = try await data(from: latestReleaseURL)
        return try JSONDecoder().decode(SumiProtectionBundleGitHubRelease.self, from: data)
    }

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SumiBundleUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw SumiProtectionBundleRemoteUpdateError.httpStatus(response.statusCode, url.absoluteString)
        }
        return data
    }
}
