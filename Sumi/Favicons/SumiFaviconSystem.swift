import Foundation
import OSLog
import SumiDomain

enum SumiFaviconLookupKey {
    static func referenceKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              isCacheableScheme(scheme)
        else {
            return nil
        }

        if let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host.lowercased()
        }

        let absoluteString = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return absoluteString.isEmpty ? nil : absoluteString.lowercased()
    }

    static func documentURL(forReferenceKey key: String) -> URL? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let explicitURL = URL(string: trimmed),
           let scheme = explicitURL.scheme?.lowercased(),
           isCacheableScheme(scheme) {
            return explicitURL
        }

        return URL(string: "https://\(trimmed)")
    }

    private static func isCacheableScheme(_ scheme: String) -> Bool {
        scheme == "http" || scheme == "https"
            || ExtensionURLIdentity.ownedSchemes.contains(scheme)
    }
}

@MainActor
final class SumiFaviconSystem {
    private static let log = Logger.sumi(category: "FaviconSystem")
    private static let sharedRegularUpgradeKey =
        "local-installation-storage.shared-favicons.v3"
    private static let sharedRegularUpgradeMarker = Data("complete".utf8)
    let runtime: SumiFaviconRuntime
    let capabilities: BrowserFaviconCapabilities
    private let favoriteBackdrops: SumiFavoriteBackdropStore
    private var bookmarkHosts: Set<String> = []

    init(
        database: SumiDatabase,
        rootDirectory: URL,
        fetcher: any SumiFaviconNetworkFetching
    ) {
        let runtime = SumiFaviconRuntime(
            database: database,
            rootDirectory: rootDirectory,
            fetcher: fetcher
        )
        let favoriteBackdrops = SumiFavoriteBackdropStore(
            rootDirectory: rootDirectory.appendingPathComponent(
                "favorite-backdrops-v1",
                isDirectory: true
            ),
            imageReader: runtime.images
        )
        self.runtime = runtime
        self.favoriteBackdrops = favoriteBackdrops
        capabilities = BrowserFaviconCapabilities(
            images: runtime.images,
            liveDiscovery: runtime.liveDiscovery,
            localIconIngestion: runtime.payloadIngestion,
            prefetch: runtime.coldFetches,
            favoriteBackdrops: favoriteBackdrops
        )
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        favoriteBackdrops.syncFavorite(pins)
        let normalizer = SumiSiteNormalizer()
        let hosts = Set(pins.compactMap { normalizer.host(for: $0.launchURL) })
        bookmarkHosts.formUnion(hosts)
        for pin in pins {
            runtime.coldFetches.schedule(
                pageURL: pin.launchURL,
                partition: .regular(),
                priority: .pinnedLauncher
            )
        }
    }

    func syncBookmarks(
        _ bookmarks: [SumiBookmark],
        partition: SumiFaviconPartition = .regular()
    ) {
        let normalizer = SumiSiteNormalizer()
        let hosts = Set(bookmarks.compactMap { normalizer.host(for: $0.url) })
        bookmarkHosts.formUnion(hosts)
        for bookmark in bookmarks {
            runtime.coldFetches.schedule(
                pageURL: bookmark.url,
                partition: partition,
                priority: .backgroundPrefetch
            )
        }
    }

    func invalidateSite(domain: String, profile: Profile?) {
        runtime.maintenance.invalidateSite(
            domain: domain,
            partition: partition(profile: profile)
        )
    }

    func clearFaviconPartition(for profile: Profile) throws {
        guard profile.isEphemeral else { return }
        try runtime.maintenance.clearPartition(partition(profile: profile))
    }

    func burnAfterHistoryClear(savedLogins: Set<String>) async {
        runtime.maintenance.burnAfterHistoryClear(
            savedLogins: savedLogins,
            bookmarkHosts: bookmarkHosts
        )
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>
    ) async {
        runtime.maintenance.burnDomains(
            domains,
            remainingHistoryHosts: remainingHistoryHosts,
            savedLogins: savedLogins,
            bookmarkHosts: bookmarkHosts
        )
    }

    func partition(profile: Profile?) -> SumiFaviconPartition {
        guard let profile else { return .regular() }
        return profile.isEphemeral
            ? .privateEphemeral(profile.id)
            : .regular()
    }

    /// Regular favicon data became one rebuildable shared cache in v3. Old
    /// per-profile payloads have no authority and are cheaper to refetch than
    /// to carry through a complex cache migration.
    static func discardLegacyRegularPartitions(
        database: SumiDatabase,
        rootDirectory: URL,
        fileManager: FileManager = .default
    ) {
        do {
            let completed = try database.read {
                try $0.documents.data(forKey: sharedRegularUpgradeKey)
                    == sharedRegularUpgradeMarker
            }
            guard completed == false else { return }

            if fileManager.fileExists(atPath: rootDirectory.path) {
                let directories = try fileManager.contentsOfDirectory(
                    at: rootDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                let sharedComponent =
                    SumiFaviconPartition.regular().storageComponent
                for directory in directories
                where directory.lastPathComponent.hasPrefix("profile-")
                    && directory.lastPathComponent != sharedComponent {
                    try fileManager.removeItem(at: directory)
                }
            }
            try database.transaction { connection in
                let sharedKey =
                    "favicon.metadata.\(SumiFaviconPartition.regular().storageComponent)"
                let keys = try connection.documents.keys(
                    withPrefix: "favicon.metadata.profile-"
                )
                for key in keys where key != sharedKey {
                    try connection.documents.delete(key: key)
                }
                try connection.documents.save(
                    sharedRegularUpgradeMarker,
                    forKey: sharedRegularUpgradeKey
                )
            }
        } catch {
            log.error(
                "Failed to discard legacy regular favicon caches: \(String(describing: error), privacy: .public)"
            )
        }
    }

    func invalidateSite(domain: String, partition: SumiFaviconPartition) {
        runtime.maintenance.invalidateSite(domain: domain, partition: partition)
    }

    #if DEBUG
        func drainRuntimeTasksForTests(cancel: Bool = true) async {
            await runtime.coldFetches.drainForTests(cancel: cancel)
        }
    #endif
}
