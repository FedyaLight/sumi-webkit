public enum SumiProtectionLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case protection
    case adblock

    public var id: String { rawValue }

    public var requestedGroups: [SumiProtectionGroupKind] {
        switch self {
        case .off:
            return []
        case .protection:
            return [.trackingNetwork]
        case .adblock:
            return [.trackingNetwork, .adblockAdsPrivacyNetwork]
        }
    }
}

public enum SumiProtectionGroupKind: String, Codable, CaseIterable, Hashable, Sendable {
    case trackingNetwork
    case adblockAdsPrivacyNetwork
    case cosmetic
}

public struct SumiProtectionAttachmentState: Equatable, Sendable {
    public let siteHost: String?
    public let requestedLevel: SumiProtectionLevel
    public let effectiveLevel: SumiProtectionLevel
    public let activeGroups: [SumiProtectionGroupKind]
    public let attachedRuleListIdentifiers: [String]
    public let activeGenerationId: String?

    public var isEnabled: Bool {
        effectiveLevel != .off && !activeGroups.isEmpty
    }

    public var effectiveWebViewRuleListIdentifiers: [String] {
        guard isEnabled else { return [] }
        return attachedRuleListIdentifiers
    }

    public func hasSameEffectiveWebViewAttachment(
        as other: SumiProtectionAttachmentState
    ) -> Bool {
        effectiveWebViewRuleListIdentifiers
            == other.effectiveWebViewRuleListIdentifiers
    }

    public init(
        siteHost: String?,
        requestedLevel: SumiProtectionLevel,
        effectiveLevel: SumiProtectionLevel,
        activeGroups: [SumiProtectionGroupKind],
        attachedRuleListIdentifiers: [String] = [],
        activeGenerationId: String? = nil
    ) {
        self.siteHost = siteHost
        self.requestedLevel = requestedLevel
        self.effectiveLevel = effectiveLevel
        self.activeGroups = Array(Set(activeGroups)).sorted {
            $0.rawValue < $1.rawValue
        }
        self.attachedRuleListIdentifiers = Array(
            Set(attachedRuleListIdentifiers)
        ).sorted()
        self.activeGenerationId = activeGenerationId
    }

    public static func disabled(
        siteHost: String?,
        requestedLevel: SumiProtectionLevel = .off
    ) -> SumiProtectionAttachmentState {
        SumiProtectionAttachmentState(
            siteHost: siteHost,
            requestedLevel: requestedLevel,
            effectiveLevel: .off,
            activeGroups: []
        )
    }
}

public struct SumiProtectionReloadRequirement: Equatable, Sendable {
    public let siteHost: String?
    public let desiredAttachmentState: SumiProtectionAttachmentState

    public init(
        siteHost: String?,
        desiredAttachmentState: SumiProtectionAttachmentState
    ) {
        self.siteHost = siteHost
        self.desiredAttachmentState = desiredAttachmentState
    }
}
