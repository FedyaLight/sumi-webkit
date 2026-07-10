import Foundation
import SumiDomain

struct SumiProtectionDedupeSummary: Equatable, Sendable {
    let inputRuleListCount: Int
    let finalRuleListCount: Int
    let duplicateIdentifierCountRemoved: Int
    let duplicateCanonicalJSONCountRemoved: Int
    let duplicateGroupContentHashCountRemoved: Int
    let canonicalJSONUnavailableCount: Int
    let removedIdentifiers: [String]

    static let empty = SumiProtectionDedupeSummary(
        inputRuleListCount: 0,
        finalRuleListCount: 0,
        duplicateIdentifierCountRemoved: 0,
        duplicateCanonicalJSONCountRemoved: 0,
        duplicateGroupContentHashCountRemoved: 0,
        canonicalJSONUnavailableCount: 0,
        removedIdentifiers: []
    )

    var reportLine: String {
        "input=\(inputRuleListCount); final=\(finalRuleListCount); duplicateIdentifiersRemoved=\(duplicateIdentifierCountRemoved); duplicateCanonicalJSONRemoved=\(duplicateCanonicalJSONCountRemoved); duplicateGroupContentHashRemoved=\(duplicateGroupContentHashCountRemoved); canonicalJSONUnavailable=\(canonicalJSONUnavailableCount)"
    }
}

struct SumiProtectionOverlapSummary: Equatable, Sendable {
    let exactCanonicalOverlapCount: Int
    let domainResourceOverlapCount: Int
    let exactComparisonAvailable: Bool
    let notes: [String]

    static let deferred = SumiProtectionOverlapSummary(
        exactCanonicalOverlapCount: 0,
        domainResourceOverlapCount: 0,
        exactComparisonAvailable: false,
        notes: ["Detailed overlap diagnostics are available in Copy Diagnostics."]
    )

    var reportLine: String {
        "exactCanonicalOverlap=\(exactCanonicalOverlapCount); domainResourceOverlap=\(domainResourceOverlapCount); exactComparisonAvailable=\(exactComparisonAvailable); notes=\(notes.joined(separator: " | "))"
    }
}

struct SumiProtectionRulePlan: Equatable, Sendable {
    let requestedLevel: SumiProtectionLevel
    let effectiveLevel: SumiProtectionLevel
    let siteHost: String?
    let siteOverride: SumiAdblockSiteOverride
    let sitePolicyAllowsProtection: Bool
    let activeGroups: [SumiProtectionGroupKind]
    let inactiveGroups: [SumiProtectionGroupKind]
    let bundleSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let requiredBundleProfileId: String?
    let activeGenerationId: String?
    let previousGenerationId: String?
    let previousGenerationRetained: Bool
    let ruleCountsByGroup: [SumiProtectionGroupKind: Int]
    let shardCountsByGroup: [SumiProtectionGroupKind: Int]
    let expectedRuleListIdentifiers: [String]
    let dedupeSummary: SumiProtectionDedupeSummary
    let overlapSummary: SumiProtectionOverlapSummary
    let ineligibleSurfaceReason: String?
    let planningErrors: [String]
    let ruleDefinitions: [SumiContentRuleListDefinition]

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

    var trackingGroupActive: Bool {
        activeGroups.contains(.trackingNetwork)
    }

    var adblockGroupActive: Bool {
        activeGroups.contains(.adblockAdsPrivacyNetwork)
    }
}
