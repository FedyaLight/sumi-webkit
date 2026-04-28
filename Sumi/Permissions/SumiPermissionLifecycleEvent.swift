import Foundation

enum SumiPermissionLifecycleEvent: Equatable, Sendable {
    case mainFrameNavigation(pageId: String, tabId: String, profilePartitionId: String?, targetURL: URL?, reason: String)
    case webViewReplaced(pageId: String, tabId: String, profilePartitionId: String?, reason: String)
    case webViewDeallocated(pageId: String, tabId: String, profilePartitionId: String?, reason: String)
    case tabClosed(pageId: String, tabId: String, profilePartitionId: String?, reason: String)
    case profileClosed(profilePartitionId: String, reason: String)
    case sessionClosed(ownerId: String, reason: String)
    case currentSiteReset(
        pageId: String?,
        tabId: String?,
        profilePartitionId: String,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        reason: String
    )

    var reason: String {
        switch self {
        case .mainFrameNavigation(_, _, _, _, let reason),
             .webViewReplaced(_, _, _, let reason),
             .webViewDeallocated(_, _, _, let reason),
             .tabClosed(_, _, _, let reason),
             .profileClosed(_, let reason),
             .sessionClosed(_, let reason),
             .currentSiteReset(_, _, _, _, _, let reason):
            return reason
        }
    }
}
