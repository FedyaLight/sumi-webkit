import Foundation
import WebKit

/// Per-target permission routing. URL preflight is query-only; mutations stay
/// in `ExtensionPermissionCallbackSettlement`, where authority can be checked
/// between effects.
@available(macOS 15.5, *)
@MainActor
enum ExtensionPermissionPromptRouting {
    enum URLPermissionPromptResolution {
        case alreadyGranted
        case alreadyDenied
        case configured(SafariExtensionSiteAccessLevel)
        case unresolved
    }

    static func grantedPermissions(
        from permissions: Set<WKWebExtension.Permission>,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> Set<WKWebExtension.Permission> {
        permissions.filter {
            ExtensionPermissionStatusResolver.isGranted(
                ExtensionPermissionStatusResolver.effectiveStatus(
                    for: $0,
                    in: extensionContext,
                    tab: tab
                )
            )
        }
    }

    static func grantedMatchPatterns(
        from matchPatterns: Set<WKWebExtension.MatchPattern>,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> Set<WKWebExtension.MatchPattern> {
        matchPatterns.filter {
            ExtensionPermissionStatusResolver.isGranted(
                ExtensionPermissionStatusResolver.effectiveStatus(
                    for: $0,
                    in: extensionContext,
                    tab: tab
                )
            )
        }
    }

    static func applyStoredPermissionDecision(
        to permission: WKWebExtension.Permission,
        in extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        decisions: ExtensionPermissionDecisionStore
    ) -> Bool {
        guard let stored = decisions.storedExtensionPermissionDecision(
            extensionId: extensionId,
            profileId: profileId,
            targetKind: .permission,
            target: permission.rawValue
        ) else { return false }
        let status: WKWebExtensionContext.PermissionStatus =
            stored.state == .allowed ? .grantedExplicitly : .deniedExplicitly
        extensionContext.setPermissionStatus(
            status,
            for: permission,
            expirationDate: stored.expiresAt
        )
        return true
    }

    static func applyConfiguredSiteAccessDecision(
        to matchPattern: WKWebExtension.MatchPattern,
        in extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        siteAccess: ExtensionSiteAccessPolicyCoordinator
    ) -> Bool {
        switch siteAccess.configuredSiteAccessLevel(
            for: matchPattern,
            extensionId: extensionId,
            profileId: profileId
        ) {
        case .allow:
            extensionContext.setPermissionStatus(
                .grantedExplicitly,
                for: matchPattern
            )
            return true
        case .deny:
            extensionContext.setPermissionStatus(
                .deniedExplicitly,
                for: matchPattern
            )
            return true
        case .ask:
            return false
        }
    }

    static func resolveURLPermissionBeforePrompt(
        url: URL,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?,
        extensionId: String,
        profileId: UUID,
        siteAccess: ExtensionSiteAccessPolicyCoordinator
    ) -> URLPermissionPromptResolution {
        let status = ExtensionPermissionStatusResolver.effectiveStatus(
            for: url,
            in: extensionContext,
            tab: tab
        )
        if ExtensionPermissionStatusResolver.isGranted(status) {
            return .alreadyGranted
        }
        if status == .deniedExplicitly {
            return .alreadyDenied
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return .unresolved
        }
        switch siteAccess.configuredSiteAccessLevel(
            for: url,
            extensionId: extensionId,
            profileId: profileId
        ) {
        case .allow:
            return .configured(.allow)
        case .deny:
            return .configured(.deny)
        case .ask:
            return .unresolved
        }
    }
}
