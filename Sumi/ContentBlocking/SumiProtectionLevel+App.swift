import SumiDomain

enum SumiProtectionBundleProfile {
    static let adblock = "adblockLocal"
}

extension SumiProtectionLevel {
    var displayTitle: String {
        switch self {
        case .off:
            return "Off"
        case .adblock:
            return "Adblock"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "No blocking."
        case .adblock:
            return "Full ad and tracker blocking."
        }
    }

    var preferredBundleProfileId: String? {
        switch self {
        case .off:
            return nil
        case .adblock:
            return SumiProtectionBundleProfile.adblock
        }
    }
}
