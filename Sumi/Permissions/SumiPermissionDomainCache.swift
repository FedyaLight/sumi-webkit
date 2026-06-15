import Foundation

final class SumiPermissionDomainCache: @unchecked Sendable {
    static let shared = SumiPermissionDomainCache()

    private struct DisplayDomainKey: Hashable {
        let value: String
        let fallback: String
        let lowercased: Bool
    }

    private enum RegistrableDomainValue: Hashable {
        case value(String)
        case none

        init(_ value: String?) {
            if let value {
                self = .value(value)
            } else {
                self = .none
            }
        }

        var stringValue: String? {
            switch self {
            case .value(let value):
                return value
            case .none:
                return nil
            }
        }
    }

    private let lock = NSLock()
    private let limit: Int
    private let registrableDomainResolver: any SumiRegistrableDomainResolving
    private var displayDomains: [DisplayDomainKey: String] = [:]
    private var registrableDomains: [String: RegistrableDomainValue] = [:]

    init(
        registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver(),
        limit: Int = 128
    ) {
        self.registrableDomainResolver = registrableDomainResolver
        self.limit = max(1, limit)
    }

    func clear() {
        withLock {
            displayDomains.removeAll(keepingCapacity: true)
            registrableDomains.removeAll(keepingCapacity: true)
        }
    }

    func lowercasedDisplayDomain(
        _ value: String,
        fallback: String = "Unknown Origin"
    ) -> String {
        normalizedDisplayDomain(value, fallback: fallback, lowercased: true)
    }

    func trimmedDisplayDomain(
        _ value: String,
        fallback: String = "Current site"
    ) -> String {
        normalizedDisplayDomain(value, fallback: fallback, lowercased: false)
    }

    func registrableDomain(forHost host: String?) -> String? {
        guard let host else { return nil }
        return withLock { () -> String? in
            if let cached = registrableDomains[host] {
                return cached.stringValue
            }

            let resolved = registrableDomainResolver.registrableDomain(forHost: host)
            insert(RegistrableDomainValue(resolved), for: host, into: &registrableDomains)
            return resolved
        }
    }

    private func normalizedDisplayDomain(
        _ value: String,
        fallback: String,
        lowercased: Bool
    ) -> String {
        let key = DisplayDomainKey(value: value, fallback: fallback, lowercased: lowercased)
        return withLock {
            if let cached = displayDomains[key] {
                return cached
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized: String
            if trimmed.isEmpty {
                normalized = fallback
            } else if lowercased {
                normalized = trimmed.lowercased()
            } else {
                normalized = trimmed
            }
            insert(normalized, for: key, into: &displayDomains)
            return normalized
        }
    }

    private func withLock<R>(_ body: () -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func insert<Key: Hashable, Value>(
        _ value: Value,
        for key: Key,
        into cache: inout [Key: Value]
    ) {
        if cache.count >= limit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = value
    }

    private func insert(
        _ value: RegistrableDomainValue,
        for key: String,
        into cache: inout [String: RegistrableDomainValue]
    ) {
        if cache.count >= limit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = value
    }
}
