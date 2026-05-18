import Foundation

struct SumiProtectionSiteNormalizer {
    private let registrableDomainResolver: any SumiRegistrableDomainResolving

    init(registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()) {
        self.registrableDomainResolver = registrableDomainResolver
    }

    func normalizedHost(for url: URL?) -> String? {
        guard let rawHost = url?.host else { return nil }
        return normalizedHost(fromRawHost: rawHost)
    }

    func normalizedHost(fromUserInput input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.host != nil {
            return normalizedHost(for: url)
        }
        if let url = URL(string: "https://\(trimmed)"), url.host != nil {
            return normalizedHost(for: url)
        }
        return normalizedHost(fromRawHost: trimmed)
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
