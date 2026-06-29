import Foundation

final class SumiPermissionDomainCache: @unchecked Sendable {
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
            registrableDomains.removeAll(keepingCapacity: true)
        }
    }

    func lowercasedDisplayDomain(
        _ value: String,
        fallback: String = "Unknown Origin"
    ) -> String {
        SumiPermissionDisplayDomainFormatter.lowercasedDisplayDomain(value, fallback: fallback)
    }

    func trimmedDisplayDomain(
        _ value: String,
        fallback: String = "Current site"
    ) -> String {
        SumiPermissionDisplayDomainFormatter.trimmedDisplayDomain(value, fallback: fallback)
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

    private func withLock<R>(_ body: () -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body()
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
