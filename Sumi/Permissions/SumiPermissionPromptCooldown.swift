import Foundation

struct SumiPermissionPromptCooldown: Equatable, Sendable {
    static let firstDismissCooldown: TimeInterval = 10 * 60
    static let secondDismissCooldown: TimeInterval = 24 * 60 * 60
    static let thirdDismissEmbargo: TimeInterval = 7 * 24 * 60 * 60
    static let explicitDenyCooldown: TimeInterval = 24 * 60 * 60
    static let systemBlockedCooldown: TimeInterval = 10 * 60
    static let secondDismissWindow: TimeInterval = 24 * 60 * 60
    static let embargoWindow: TimeInterval = 7 * 24 * 60 * 60
    static let eventRetention: TimeInterval = 90 * 24 * 60 * 60
    static let maximumEventsPerProfile = 1_000

    let startedAt: Date
    let duration: TimeInterval

    var expiresAt: Date {
        startedAt.addingTimeInterval(duration)
    }

    func contains(_ date: Date) -> Bool {
        date < expiresAt
    }
}
