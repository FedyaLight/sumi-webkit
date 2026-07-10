import SumiDomain

enum SumiProtectionBundleProfile {
    static let unified = "adguardAdsPrivacy"
    static let adblock = "adguardAdsPrivacy"
}

extension SumiProtectionLevel {
    var displayTitle: String {
        switch self {
        case .off:
            return "Off"
        case .protection:
            return "Protection"
        case .adblock:
            return "Adblock"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "No blocking."
        case .protection:
            return "Lightweight tracker protection."
        case .adblock:
            return "Recommended native ad blocking with tracker protection."
        }
    }

    var preferredBundleProfileId: String? {
        switch self {
        case .off:
            return nil
        case .protection, .adblock:
            return SumiProtectionBundleProfile.unified
        }
    }

    var adblockRuleGroupKinds: Set<AdblockCompiledRuleGroupKind> {
        switch self {
        case .off, .protection:
            return []
        case .adblock:
            return [.network]
        }
    }
}
