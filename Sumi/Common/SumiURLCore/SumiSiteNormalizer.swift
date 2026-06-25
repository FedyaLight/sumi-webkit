import Foundation

struct SumiSiteNormalizer {
    private let registrableDomainResolver: any SumiRegistrableDomainResolving

    init(registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()) {
        self.registrableDomainResolver = registrableDomainResolver
    }

    func normalizedHost(for url: URL?) -> String? {
        guard let rawHost = url?.host else { return nil }
        return normalizedHost(fromRawHost: rawHost)
    }

    func normalizedHost(fromRawHost rawHost: String) -> String? {
        let host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !host.isEmpty else { return nil }
        return registrableDomainResolver.registrableDomain(forHost: host) ?? host
    }
}
