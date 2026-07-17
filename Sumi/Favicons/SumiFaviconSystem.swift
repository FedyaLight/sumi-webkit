import Foundation
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

    static func cacheKey(for url: URL) -> String? {
        referenceKey(for: url)
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
    let runtime: SumiFaviconRuntime
    let capabilities: BrowserFaviconCapabilities
    private var bookmarkHosts: Set<String> = []

    init(
        rootDirectory: URL,
        fetcher: any SumiFaviconNetworkFetching
    ) {
        let runtime = SumiFaviconRuntime(
            rootDirectory: rootDirectory,
            fetcher: fetcher
        )
        self.runtime = runtime
        capabilities = BrowserFaviconCapabilities(
            images: runtime.images,
            liveDiscovery: runtime.liveDiscovery,
            localIconIngestion: runtime.payloadIngestion,
            prefetch: runtime.coldFetches
        )
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        let normalizer = SumiSiteNormalizer()
        let hosts = Set(pins.compactMap { normalizer.host(for: $0.launchURL) })
        bookmarkHosts.formUnion(hosts)
        for pin in pins {
            runtime.coldFetches.schedule(
                pageURL: pin.launchURL,
                partition: .regular(pin.executionProfileId),
                priority: .pinnedLauncher
            )
        }
    }

    func syncBookmarks(
        _ bookmarks: [SumiBookmark],
        partition: SumiFaviconPartition = .regular(nil)
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
        guard let profile else { return .regular(nil) }
        return profile.isEphemeral
            ? .privateEphemeral(profile.id)
            : .regular(profile.id)
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
