import Foundation

@MainActor
final class SumiPermissionSidebarPinningController {
    private struct SessionRecord {
        let pageId: String
        let windowID: UUID
        let source: SidebarTransientPresentationSource
        let token: SidebarTransientSessionToken
    }

    private var sessionsByQueryID: [String: SessionRecord] = [:]

    func reconcile(
        activeQueries: [SumiPermissionAuthorizationQuery],
        windowForPageId: (String) -> BrowserWindowState?,
        reason: String
    ) {
        let promptableQueries = activeQueries.filter(Self.isPromptable)
        let activeQueryIDs = Set(promptableQueries.map(\.id))

        for queryID in Array(sessionsByQueryID.keys) where !activeQueryIDs.contains(queryID) {
            finishSession(
                queryID: queryID,
                reason: "\(reason):inactive"
            )
        }

        for query in promptableQueries {
            guard let windowState = windowForPageId(query.pageId) else {
                finishSession(
                    queryID: query.id,
                    reason: "\(reason):window-missing"
                )
                continue
            }

            if let record = sessionsByQueryID[query.id] {
                guard record.pageId != query.pageId || record.windowID != windowState.id else {
                    continue
                }
                finishSession(
                    queryID: query.id,
                    reason: "\(reason):window-changed"
                )
            }

            beginSession(
                for: query,
                in: windowState,
                reason: reason
            )
        }
    }

    private func beginSession(
        for query: SumiPermissionAuthorizationQuery,
        in windowState: BrowserWindowState,
        reason: String
    ) {
        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: windowState.window
        )
        let token = windowState.sidebarTransientSessionCoordinator.beginSession(
            kind: .permissionPrompt,
            source: source,
            path: "SumiPermissionSidebarPinningController.\(reason)"
        )
        sessionsByQueryID[query.id] = SessionRecord(
            pageId: query.pageId,
            windowID: windowState.id,
            source: source,
            token: token
        )
    }

    private func finishSession(
        queryID: String,
        reason: String
    ) {
        guard let record = sessionsByQueryID.removeValue(forKey: queryID) else { return }
        record.source.coordinator?.finishSession(
            record.token,
            reason: "SumiPermissionSidebarPinningController.\(reason)"
        )
    }

    private static func isPromptable(_ query: SumiPermissionAuthorizationQuery) -> Bool {
        let primary = SumiPermissionPromptViewModel.primaryPermissionType(
            permissionTypes: query.permissionTypes,
            presentationPermissionType: query.presentationPermissionType
        )
        return SumiPermissionPromptViewModel.isPromptable(primary)
    }
}
