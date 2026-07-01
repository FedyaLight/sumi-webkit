import Foundation

struct SumiSiteIdentity: Equatable, Hashable, Sendable {
    let normalizedURL: URL
    let host: String
    let displayDomain: String
    let siteDomain: String
}

struct SumiSiteNormalizer: Sendable {
    private let registrableDomainResolver: any SumiRegistrableDomainResolving

    init(registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()) {
        self.registrableDomainResolver = registrableDomainResolver
    }

    func identity(for url: URL?) -> SumiSiteIdentity? {
        guard let url,
              let host = host(for: url),
              let normalizedURL = normalizedURL(for: url, host: host)
        else {
            return nil
        }
        return SumiSiteIdentity(
            normalizedURL: normalizedURL,
            host: host,
            displayDomain: displayDomain(forHost: host),
            siteDomain: siteDomain(forHost: host)
        )
    }

    func normalizedURL(for url: URL?) -> URL? {
        guard let url,
              let host = host(for: url)
        else { return nil }
        return normalizedURL(for: url, host: host)
    }

    func host(for url: URL?) -> String? {
        guard let rawHost = rawHost(for: url) else { return nil }
        return host(fromRawHost: rawHost)
    }

    func host(fromRawHost rawHost: String) -> String? {
        let host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return host.isEmpty ? nil : host
    }

    func displayDomain(for url: URL?) -> String? {
        host(for: url).map(displayDomain(forHost:))
    }

    func displayDomain(fromRawHost rawHost: String) -> String? {
        host(fromRawHost: rawHost).map(displayDomain(forHost:))
    }

    func siteDomain(for url: URL?) -> String? {
        host(for: url).map(siteDomain(forHost:))
    }

    func siteDomain(fromRawDomain rawDomain: String) -> String? {
        host(fromRawHost: rawDomain).map(siteDomain(forHost:))
    }

    func normalizedHost(for url: URL?) -> String? {
        siteDomain(for: url)
    }

    func normalizedHost(fromRawHost rawHost: String) -> String? {
        siteDomain(fromRawDomain: rawHost)
    }

    private func normalizedURL(for url: URL, host: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = components.scheme?.lowercased()
        components.host = host
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        if components.scheme == "http", components.port == 80 {
            components.port = nil
        } else if components.scheme == "https", components.port == 443 {
            components.port = nil
        }

        return components.url
    }

    private func rawHost(for url: URL?) -> String? {
        guard let url else { return nil }
        return url.host(percentEncoded: false) ?? url.host
    }

    private func displayDomain(forHost host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func siteDomain(forHost host: String) -> String {
        registrableDomainResolver.registrableDomain(forHost: host) ?? host
    }
}
