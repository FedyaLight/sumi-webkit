import Foundation

/// Thin protection-facing façade over `SumiSiteNormalizer` so content-blocking
/// and favicon/cookie site keys share one host pipeline.
struct SumiProtectionSiteNormalizer {
    private let siteNormalizer: SumiSiteNormalizer

    init(registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()) {
        self.siteNormalizer = SumiSiteNormalizer(
            registrableDomainResolver: registrableDomainResolver
        )
    }

    init(siteNormalizer: SumiSiteNormalizer) {
        self.siteNormalizer = siteNormalizer
    }

    func normalizedHost(for url: URL?) -> String? {
        siteNormalizer.normalizedHost(for: url)
    }

    func normalizedHost(fromRawHost rawHost: String) -> String? {
        siteNormalizer.siteDomain(fromRawDomain: rawHost)
    }
}
