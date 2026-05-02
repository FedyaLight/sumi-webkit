import Foundation

struct SumiPermissionAutoRevokedEvent: Equatable, Identifiable, Sendable {
    let id: String
    let displayDomain: String
    let key: SumiPermissionKey
    let revokedAt: Date

    init(
        id: String = UUID().uuidString,
        displayDomain: String,
        key: SumiPermissionKey,
        revokedAt: Date
    ) {
        self.id = id
        self.displayDomain = SumiPermissionStoreRecord.normalizedDisplayDomain(displayDomain)
        self.key = key
        self.revokedAt = revokedAt
    }
}
