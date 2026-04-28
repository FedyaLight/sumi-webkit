import Foundation

struct SumiPermissionCoordinatorState: Equatable, Sendable {
    var activeQueriesByPageId: [String: SumiPermissionAuthorizationQuery]
    var queueCountByPageId: [String: Int]
    var latestEvent: SumiPermissionCoordinatorEvent?
    var latestSystemBlockedEvent: SumiPermissionCoordinatorEvent?

    init(
        activeQueriesByPageId: [String: SumiPermissionAuthorizationQuery] = [:],
        queueCountByPageId: [String: Int] = [:],
        latestEvent: SumiPermissionCoordinatorEvent? = nil,
        latestSystemBlockedEvent: SumiPermissionCoordinatorEvent? = nil
    ) {
        self.activeQueriesByPageId = activeQueriesByPageId
        self.queueCountByPageId = queueCountByPageId
        self.latestEvent = latestEvent
        self.latestSystemBlockedEvent = latestSystemBlockedEvent
    }
}
