import SumiDomain

struct SumiProtectionRulePlan: Equatable, Sendable {
    let requestedLevel: SumiProtectionLevel
    let effectiveLevel: SumiProtectionLevel
    let siteHost: String?
    let sitePolicyAllowsProtection: Bool
    let activeGroups: [SumiProtectionGroupKind]
    let activeGenerationId: String?
    let expectedRuleListIdentifiers: [String]

    var attachmentState: SumiProtectionAttachmentState {
        SumiProtectionAttachmentState(
            siteHost: siteHost,
            requestedLevel: requestedLevel,
            effectiveLevel: effectiveLevel,
            activeGroups: activeGroups,
            attachedRuleListIdentifiers: expectedRuleListIdentifiers,
            activeGenerationId: activeGenerationId
        )
    }

    var adblockGroupActive: Bool {
        activeGroups.contains(.adblockAdsPrivacyNetwork)
    }
}
