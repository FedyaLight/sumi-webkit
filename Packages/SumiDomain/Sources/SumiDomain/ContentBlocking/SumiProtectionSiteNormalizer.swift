import Foundation

/// Thin protection-facing façade over `SumiSiteNormalizer` so content-blocking
/// and favicon/cookie site keys share one host pipeline.
public struct SumiProtectionSiteNormalizer {
    private let siteNormalizer: SumiSiteNormalizer

    public init(registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()) {
        self.siteNormalizer = SumiSiteNormalizer(
            registrableDomainResolver: registrableDomainResolver
        )
    }

    public init(siteNormalizer: SumiSiteNormalizer) {
        self.siteNormalizer = siteNormalizer
    }

    public func normalizedHost(for url: URL?) -> String? {
        siteNormalizer.normalizedHost(for: url)
    }

    public func normalizedHost(fromRawHost rawHost: String) -> String? {
        siteNormalizer.siteDomain(fromRawDomain: rawHost)
    }
}
