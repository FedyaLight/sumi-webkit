import Foundation

enum SumiAutoplayDecisionMapper {
    static let metadataKey = "autoplayPolicy"

    static func decision(
        for policy: SumiAutoplayPolicy,
        source: SumiPermissionDecisionSource,
        now: Date = Date()
    ) -> SumiPermissionDecision? {
        guard policy != .default else { return nil }

        return SumiPermissionDecision(
            state: state(for: policy),
            persistence: .persistent,
            source: source,
            reason: "autoplay-site-setting",
            createdAt: now,
            updatedAt: now,
            metadata: [metadataKey: policy.rawValue]
        )
    }

    static func policy(from record: SumiPermissionStoreRecord?) -> SumiAutoplayPolicy {
        guard let record else { return .default }
        return policy(from: record.decision)
    }

    static func policy(from decision: SumiPermissionDecision) -> SumiAutoplayPolicy {
        if let rawPolicy = decision.metadata?[metadataKey],
           let policy = SumiAutoplayPolicy(rawValue: rawPolicy)
        {
            return policy
        }

        switch decision.state {
        case .ask:
            return .default
        case .allow:
            return .allowAll
        case .deny:
            return .blockAudible
        }
    }

    private static func state(for policy: SumiAutoplayPolicy) -> SumiPermissionState {
        switch policy {
        case .default:
            return .ask
        case .allowAll:
            return .allow
        case .blockAudible, .blockAll:
            return .deny
        }
    }
}
