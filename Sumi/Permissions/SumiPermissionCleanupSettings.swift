import Foundation

struct SumiPermissionCleanupSettings: Equatable, Sendable {
    static let defaultThresholdDays = 90
    static let defaultThreshold: TimeInterval = TimeInterval(defaultThresholdDays * 24 * 60 * 60)

    var isAutomaticCleanupEnabled: Bool
    var staleThreshold: TimeInterval
    var lastRunAt: Date?
    var lastRemovedCount: Int?

    init(
        isAutomaticCleanupEnabled: Bool = false,
        staleThreshold: TimeInterval = Self.defaultThreshold,
        lastRunAt: Date? = nil,
        lastRemovedCount: Int? = nil
    ) {
        self.isAutomaticCleanupEnabled = isAutomaticCleanupEnabled
        self.staleThreshold = staleThreshold
        self.lastRunAt = lastRunAt
        self.lastRemovedCount = lastRemovedCount
    }

    var thresholdDays: Int {
        max(1, Int(staleThreshold / (24 * 60 * 60)))
    }
}
