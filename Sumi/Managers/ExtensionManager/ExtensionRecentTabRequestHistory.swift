import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionRecentTabRequestHistory {
    private nonisolated static let requestTTL: TimeInterval = 2

    private var requests = BoundedRecentDateTracker(
        ttl: requestTTL,
        maxKeys: 128,
        maxDatesPerKey: 4
    )

    func consume(_ url: URL) -> Bool {
        guard let key = key(for: url) else { return false }
        return requests.consume(key: key)
    }

    func record(_ url: URL?) {
        guard let key = key(for: url) else { return }
        requests.record(key: key)
    }

    func removeAll() {
        requests.removeAll()
    }

    private nonisolated func key(for url: URL?) -> String? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url.absoluteString
    }
}
