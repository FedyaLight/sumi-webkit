import Foundation

public enum SumiPermissionSecurityContextBuilder {
    /// Builds a `SumiPermissionSecurityContext` from fields shared by permission bridges.
    ///
    /// When `hasUserGesture` is `nil`, the request records `false` and the context records `nil`.
    /// When `topOrigin` is `nil`, it is derived from `committedURL ?? mainFrameURL ?? visibleURL`.
    public static func make(
        requestId: String,
        tabId: String,
        pageId: String,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin? = nil,
        displayDomain: String? = nil,
        permissionTypes: [SumiPermissionType],
        hasUserGesture: Bool? = nil,
        isMainFrame: Bool,
        committedURL: URL?,
        visibleURL: URL?,
        mainFrameURL: URL?,
        isActiveTab: Bool,
        isVisibleTab: Bool,
        isEphemeralProfile: Bool,
        profilePartitionId: String,
        surface: SumiPermissionSecurityContext.Surface,
        navigationOrPageGeneration: String?,
        now: Date
    ) -> SumiPermissionSecurityContext {
        let resolvedTopOrigin = topOrigin ?? SumiPermissionOrigin(
            url: committedURL ?? mainFrameURL ?? visibleURL
        )
        let requestHasUserGesture = hasUserGesture ?? false
        let permissionRequest = SumiPermissionRequest(
            id: requestId,
            tabId: tabId,
            pageId: pageId,
            frameId: nil,
            requestingOrigin: requestingOrigin,
            topOrigin: resolvedTopOrigin,
            displayDomain: displayDomain,
            permissionTypes: permissionTypes,
            hasUserGesture: requestHasUserGesture,
            requestedAt: now,
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: profilePartitionId
        )

        return SumiPermissionSecurityContext(
            request: permissionRequest,
            requestingOrigin: requestingOrigin,
            topOrigin: resolvedTopOrigin,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: mainFrameURL,
            isMainFrame: isMainFrame,
            isActiveTab: isActiveTab,
            isVisibleTab: isVisibleTab,
            hasUserGesture: hasUserGesture,
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: profilePartitionId,
            transientPageId: pageId,
            surface: surface,
            navigationOrPageGeneration: navigationOrPageGeneration,
            now: permissionRequest.requestedAt
        )
    }
}
