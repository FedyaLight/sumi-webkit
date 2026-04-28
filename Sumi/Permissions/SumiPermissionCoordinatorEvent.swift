import Foundation

enum SumiPermissionCoordinatorEvent: Equatable, Sendable {
    case queryActivated(SumiPermissionAuthorizationQuery)
    case queryQueued(SumiPermissionAuthorizationQuery, position: Int)
    case queryCoalesced(queryId: String, requestId: String)
    case queryPromoted(SumiPermissionAuthorizationQuery)
    case querySettled(queryId: String, decision: SumiPermissionCoordinatorDecision)
    case requestCancelled(requestIds: [String], decision: SumiPermissionCoordinatorDecision)
    case pageCancelled(pageId: String, decision: SumiPermissionCoordinatorDecision)
    case profileCancelled(profilePartitionId: String, decision: SumiPermissionCoordinatorDecision)
    case sessionCancelled(sessionOwnerId: String, decision: SumiPermissionCoordinatorDecision)
    case systemBlocked(SumiPermissionCoordinatorDecision)
    case promptSuppressed(SumiPermissionPromptSuppression, decision: SumiPermissionCoordinatorDecision)
}
