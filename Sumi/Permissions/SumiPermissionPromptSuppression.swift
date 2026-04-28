import Foundation

struct SumiPermissionPromptSuppression: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case cooldown
        case embargo
    }

    enum Trigger: String, Codable, CaseIterable, Hashable, Sendable {
        case dismissal
        case explicitDeny
        case systemBlocked
    }

    let kind: Kind
    let trigger: Trigger
    let key: SumiPermissionKey
    let until: Date
    let reason: String

    var eventType: SumiPermissionAntiAbuseEvent.EventType {
        switch kind {
        case .cooldown:
            return .requestSuppressedByCooldown
        case .embargo:
            return .requestSuppressedByEmbargo
        }
    }

    var decisionSource: SumiPermissionDecisionSource {
        switch kind {
        case .cooldown:
            return .cooldown
        case .embargo:
            return .embargo
        }
    }

    var shouldResolveNotificationsAsDefault: Bool {
        trigger == .dismissal
    }
}
