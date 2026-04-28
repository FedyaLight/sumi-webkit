import Foundation

struct SumiPermissionAutoRevokedEvent: Equatable, Identifiable, Sendable {
    static let cleanupReason = "unused-site-permission-cleanup"

    let id: String
    let displayDomain: String
    let key: SumiPermissionKey
    let priorState: SumiPermissionState
    let priorSource: SumiPermissionDecisionSource
    let reason: String
    let revokedAt: Date
    let staleReferenceDate: Date

    init(
        id: String = UUID().uuidString,
        displayDomain: String,
        key: SumiPermissionKey,
        priorState: SumiPermissionState,
        priorSource: SumiPermissionDecisionSource,
        reason: String = Self.cleanupReason,
        revokedAt: Date,
        staleReferenceDate: Date
    ) {
        self.id = id
        self.displayDomain = SumiPermissionStoreRecord.normalizedDisplayDomain(displayDomain)
        self.key = key
        self.priorState = priorState
        self.priorSource = priorSource
        self.reason = reason
        self.revokedAt = revokedAt
        self.staleReferenceDate = staleReferenceDate
    }
}
