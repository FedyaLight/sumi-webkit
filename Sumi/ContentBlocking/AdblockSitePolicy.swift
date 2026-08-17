import Combine
import Foundation
import OSLog
import SumiDomain

enum SumiAdblockSiteOverride: String, Codable, CaseIterable, Sendable {
    case inherit
    case allowed
    case disabled
}

struct SumiAdblockEffectivePolicy: Equatable, Sendable {
    let host: String?
    let isEnabled: Bool
}

struct SumiAdblockSurfaceEligibility: Equatable, Sendable {
    let isEligible: Bool
    let normalizedSiteHost: String?
    let ineligibleReason: String?

    static func evaluate(
        url: URL?,
        normalizer: SumiProtectionSiteNormalizer
    ) -> SumiAdblockSurfaceEligibility {
        guard let url else {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "No URL"
            )
        }
        let scheme = url.scheme?.lowercased()
        if SumiSurface.isEmptyNewTabURL(url) || scheme == "about" {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "Sumi empty/new tab surface"
            )
        }
        if scheme == "sumi" {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "Internal Sumi surface"
            )
        }
        if scheme == "file" {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "Local file URL"
            )
        }
        guard scheme == "http" || scheme == "https" else {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "Unsupported URL scheme: \(scheme ?? "nil")"
            )
        }
        guard let host = normalizer.normalizedHost(for: url) else {
            return SumiAdblockSurfaceEligibility(
                isEligible: false,
                normalizedSiteHost: nil,
                ineligibleReason: "No normalized web host"
            )
        }
        return SumiAdblockSurfaceEligibility(
            isEligible: true,
            normalizedSiteHost: host,
            ineligibleReason: nil
        )
    }
}

@MainActor
final class AdblockSitePolicyStore: ObservableObject {
    private static let log = Logger.sumi(category: "ContentBlocking")
    private static let documentKey = "adblock.site-overrides"

    @Published private(set) var siteOverrides: [String: SumiAdblockSiteOverride]
    private let database: SumiDatabase?
    private let siteNormalizer: SumiProtectionSiteNormalizer
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    var disabledHosts: [String] {
        siteOverrides.compactMap { host, override in
            override == .disabled ? host : nil
        }.sorted()
    }

    init(
        database: SumiDatabase? = nil,
        registrableDomainResolver: any SumiRegistrableDomainResolving =
            SumiRegistrableDomainResolver()
    ) {
        self.database = database
        siteNormalizer = SumiProtectionSiteNormalizer(
            registrableDomainResolver: registrableDomainResolver
        )
        siteOverrides = Self.loadSiteOverrides(from: database)
    }

    func effectivePolicy(
        for url: URL?,
        globalEnabled: Bool
    ) -> SumiAdblockEffectivePolicy {
        guard let host = normalizedHost(for: url) else {
            return SumiAdblockEffectivePolicy(host: nil, isEnabled: false)
        }
        switch siteOverrides[host] ?? .inherit {
        case .allowed:
            return SumiAdblockEffectivePolicy(host: host, isEnabled: true)
        case .disabled:
            return SumiAdblockEffectivePolicy(host: host, isEnabled: false)
        case .inherit:
            return SumiAdblockEffectivePolicy(host: host, isEnabled: globalEnabled)
        }
    }

    func override(for url: URL?) -> SumiAdblockSiteOverride {
        guard let host = normalizedHost(for: url) else { return .inherit }
        return siteOverrides[host] ?? .inherit
    }

    func setSiteOverride(_ override: SumiAdblockSiteOverride, for url: URL?) {
        guard let host = normalizedHost(for: url) else { return }
        setSiteOverride(override, forNormalizedHost: host)
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        SumiAdblockSurfaceEligibility.evaluate(url: url, normalizer: siteNormalizer)
    }

    private func normalizedHost(for url: URL?) -> String? {
        surfaceEligibility(for: url).normalizedSiteHost
    }

    private func setSiteOverride(
        _ override: SumiAdblockSiteOverride,
        forNormalizedHost host: String
    ) {
        var updated = siteOverrides
        if override == .inherit {
            updated.removeValue(forKey: host)
        } else {
            updated[host] = override
        }
        guard updated != siteOverrides else { return }
        do {
            try database?.transaction {
                if updated.isEmpty {
                    try $0.documents.delete(key: Self.documentKey)
                } else {
                    try $0.documents.save(
                        updated.mapValues(\.rawValue),
                        forKey: Self.documentKey
                    )
                }
            }
        } catch {
            Self.log.error(
                "Failed to persist adblock site overrides: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        siteOverrides = updated
        changesSubject.send(())
    }

    private static func loadSiteOverrides(
        from database: SumiDatabase?
    ) -> [String: SumiAdblockSiteOverride] {
        guard let database else {
            return [:]
        }
        let decoded: [String: String]
        do {
            decoded = try database.read {
                try $0.documents.value(
                    [String: String].self,
                    forKey: documentKey
                )
            } ?? [:]
        } catch {
            log.error(
                "Failed to load adblock site overrides: \(error.localizedDescription, privacy: .public)"
            )
            return [:]
        }
        return decoded.reduce(into: [:]) { result, entry in
            guard let override = SumiAdblockSiteOverride(rawValue: entry.value),
                  override != .inherit
            else { return }
            result[entry.key] = override
        }
    }
}
