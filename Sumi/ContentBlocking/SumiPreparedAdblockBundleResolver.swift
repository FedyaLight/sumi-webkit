import Foundation

enum SumiAdblockBundleInstallSource:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case appResource
    case remoteReleaseBundle
    case developmentBundle

    var id: String { rawValue }

    var generationSource: AdblockRuleGenerationSource {
        switch self {
        case .appResource:
            return .embeddedBundle
        case .remoteReleaseBundle:
            return .remoteReleaseBundle
        case .developmentBundle:
            return .developmentBundle
        }
    }
}

struct SumiPreparedAdblockBundleSearchPath: Equatable, Sendable {
    let source: SumiAdblockBundleInstallSource
    let path: String
    let exists: Bool
    let rejectionReason: String?
}

struct SumiPreparedAdblockBundleDiscovery: Equatable, Sendable {
    struct ResolvedBundle: Equatable, Sendable {
        let source: SumiAdblockBundleInstallSource
        let bundleURL: URL
        let profileId: String
        let bundleId: String?
        let generationId: String?
        let remoteMetadata: SumiAdblockPreparedBundleRemoteMetadata?
    }

    let requiredProfileId: String
    let resolvedBundle: ResolvedBundle?
    let searchedPaths: [SumiPreparedAdblockBundleSearchPath]

    var isAvailable: Bool { resolvedBundle != nil }
    var source: SumiAdblockBundleInstallSource? { resolvedBundle?.source }

    var failureSummary: String {
        let details = searchedPaths.map { path in
            "\(path.source.rawValue) path=\(path.path) exists=\(path.exists) rejected=\(path.rejectionReason ?? "nil")"
        }.joined(separator: " | ")
        return "Searched prepared bundle sources for profile \(requiredProfileId): \(details)"
    }
}

/// Resolves one prepared bundle using the production source priority. Loading
/// and payload validation stay in the native bundle reader.
struct SumiPreparedAdblockBundleResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let bundleReader: SumiAdblockNativeBundleReader
    private let metadataReader: SumiProtectionBundleCacheMetadataReader

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        bundleReader = SumiAdblockNativeBundleReader(fileManager: fileManager)
        metadataReader = SumiProtectionBundleCacheMetadataReader(
            fileManager: fileManager
        )
    }

    func discover(
        profileId: String,
        resourceURL: URL? = Bundle.main.resourceURL,
        remoteBundlesRootURL: URL? =
            SumiRemoteAdblockBundleCache.defaultRootDirectory(),
        generatedBundlesRootURL: URL? = nil
    ) -> SumiPreparedAdblockBundleDiscovery {
        var searchedPaths = [SumiPreparedAdblockBundleSearchPath]()

        let remoteRoot = remoteBundlesRootURL
            ?? SumiRemoteAdblockBundleCache.defaultRootDirectory()
        let remotePath = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: remoteRoot
        )
        if let resolved = evaluate(
            source: .remoteReleaseBundle,
            profileId: profileId,
            bundleURL: remotePath,
            resourceUnavailableReason: nil,
            searchedPaths: &searchedPaths
        ) {
            return discovery(
                profileId: profileId,
                resolved: resolved,
                searchedPaths: searchedPaths
            )
        }

        let appResourcePath = (
            resourceURL
                ?? URL(
                    fileURLWithPath: "<missing app resources>",
                    isDirectory: true
                )
        )
        .appendingPathComponent("SumiAdblockBundles", isDirectory: true)
        .appendingPathComponent(profileId, isDirectory: true)
        .appendingPathComponent(
            SumiAdblockNativeRuleBundle.directoryName,
            isDirectory: true
        )
        if let resolved = evaluate(
            source: .appResource,
            profileId: profileId,
            bundleURL: appResourcePath,
            resourceUnavailableReason: resourceURL == nil
                ? "Bundle resourceURL is unavailable."
                : nil,
            searchedPaths: &searchedPaths
        ) {
            return discovery(
                profileId: profileId,
                resolved: resolved,
                searchedPaths: searchedPaths
            )
        }

        let developmentPath = generatedBundlesRootURL?
            .appendingPathComponent(profileId, isDirectory: true)
            .appendingPathComponent(
                SumiAdblockNativeRuleBundle.directoryName,
                isDirectory: true
            )
        #if DEBUG
            if let developmentPath {
                if let resolved = evaluate(
                    source: .developmentBundle,
                    profileId: profileId,
                    bundleURL: developmentPath,
                    resourceUnavailableReason: nil,
                    searchedPaths: &searchedPaths
                ) {
                    return discovery(
                        profileId: profileId,
                        resolved: resolved,
                        searchedPaths: searchedPaths
                    )
                }
            } else {
                searchedPaths.append(missingDevelopmentPath)
            }
        #else
            if let developmentPath {
                let exists = bundleDirectoryExists(developmentPath)
                searchedPaths.append(
                    SumiPreparedAdblockBundleSearchPath(
                        source: .developmentBundle,
                        path: developmentPath.path,
                        exists: exists,
                        rejectionReason: exists
                            ? "developmentBundle is only accepted in DEBUG builds."
                            : "Path does not exist."
                    )
                )
            } else {
                searchedPaths.append(missingDevelopmentPath)
            }
        #endif

        return discovery(
            profileId: profileId,
            resolved: nil,
            searchedPaths: searchedPaths
        )
    }

    private var missingDevelopmentPath: SumiPreparedAdblockBundleSearchPath {
        SumiPreparedAdblockBundleSearchPath(
            source: .developmentBundle,
            path: "<not configured>",
            exists: false,
            rejectionReason: "No development bundle root configured."
        )
    }

    private func discovery(
        profileId: String,
        resolved: SumiPreparedAdblockBundleDiscovery.ResolvedBundle?,
        searchedPaths: [SumiPreparedAdblockBundleSearchPath]
    ) -> SumiPreparedAdblockBundleDiscovery {
        SumiPreparedAdblockBundleDiscovery(
            requiredProfileId: profileId,
            resolvedBundle: resolved,
            searchedPaths: searchedPaths
        )
    }

    private func evaluate(
        source: SumiAdblockBundleInstallSource,
        profileId: String,
        bundleURL: URL,
        resourceUnavailableReason: String?,
        searchedPaths: inout [SumiPreparedAdblockBundleSearchPath]
    ) -> SumiPreparedAdblockBundleDiscovery.ResolvedBundle? {
        if let resourceUnavailableReason {
            searchedPaths.append(
                searchPath(
                    source: source,
                    bundleURL: bundleURL,
                    exists: false,
                    rejectionReason: resourceUnavailableReason
                )
            )
            return nil
        }

        let exists = bundleDirectoryExists(bundleURL)
        guard exists else {
            searchedPaths.append(
                searchPath(
                    source: source,
                    bundleURL: bundleURL,
                    exists: false,
                    rejectionReason: "Path does not exist."
                )
            )
            return nil
        }

        do {
            let bundle = try bundleReader.load(from: bundleURL)
            guard bundle.manifest.profileId == profileId else {
                searchedPaths.append(
                    searchPath(
                        source: source,
                        bundleURL: bundleURL,
                        exists: true,
                        rejectionReason:
                            "Manifest profileId \(bundle.manifest.profileId) does not match required profile \(profileId)."
                    )
                )
                return nil
            }
            searchedPaths.append(
                searchPath(
                    source: source,
                    bundleURL: bundleURL,
                    exists: true,
                    rejectionReason: nil
                )
            )
            return SumiPreparedAdblockBundleDiscovery.ResolvedBundle(
                source: source,
                bundleURL: bundleURL,
                profileId: bundle.manifest.profileId,
                bundleId: bundle.manifest.bundleId,
                generationId: bundle.manifest.generationId,
                remoteMetadata: source == .remoteReleaseBundle
                    ? metadataReader.read(from: bundleURL)
                    : nil
            )
        } catch {
            searchedPaths.append(
                searchPath(
                    source: source,
                    bundleURL: bundleURL,
                    exists: true,
                    rejectionReason: error.localizedDescription
                )
            )
            return nil
        }
    }

    private func searchPath(
        source: SumiAdblockBundleInstallSource,
        bundleURL: URL,
        exists: Bool,
        rejectionReason: String?
    ) -> SumiPreparedAdblockBundleSearchPath {
        SumiPreparedAdblockBundleSearchPath(
            source: source,
            path: bundleURL.path,
            exists: exists,
            rejectionReason: rejectionReason
        )
    }

    private func bundleDirectoryExists(_ bundleURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: bundleURL.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}
