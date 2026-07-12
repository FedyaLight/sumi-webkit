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
        case contextMatchPattern
        case tabMatchPattern
        case configured(SafariExtensionSiteAccessLevel)
        case unresolved
    }

    static func grantedPermissions(
        from permissions: Set<WKWebExtension.Permission>,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?,
        manager: ExtensionManager
    ) -> Set<WKWebExtension.Permission> {
        permissions.filter {
            manager.isGrantedPermissionStatus(
                manager.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
            )
        }
    }

    static func grantedMatchPatterns(
        from matchPatterns: Set<WKWebExtension.MatchPattern>,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?,
        manager: ExtensionManager
    ) -> Set<WKWebExtension.MatchPattern> {
        matchPatterns.filter {
            manager.isGrantedPermissionStatus(
                manager.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
            )
        }
    }

    static func applyStoredPermissionDecision(
        to permission: WKWebExtension.Permission,
        in extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        manager: ExtensionManager
    ) -> Bool {
        guard let stored = manager.storedExtensionPermissionDecision(
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
        manager: ExtensionManager
    ) -> Bool {
        switch manager.configuredSiteAccessLevel(
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
        manager: ExtensionManager
    ) -> URLPermissionPromptResolution {
        let status = manager.effectivePermissionStatus(
            for: url,
            in: extensionContext,
            tab: tab
        )
        if manager.isGrantedPermissionStatus(status) {
            return .alreadyGranted
        }
        if status == .deniedExplicitly {
            return .alreadyDenied
        }
        switch grantedMatchPatternCoverage(
            for: url,
            in: extensionContext,
            tab: tab,
            manager: manager
        ) {
        case .context:
            return .contextMatchPattern
        case .tab:
            return .tabMatchPattern
        case .none:
            break
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return .unresolved
        }
        switch manager.configuredSiteAccessLevel(
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

    private enum MatchPatternCoverage {
        case context
        case tab
        case none
    }

    private static func grantedMatchPatternCoverage(
        for url: URL,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?,
        manager: ExtensionManager
    ) -> MatchPatternCoverage {
        let declaredPatterns = extensionContext.webExtension
            .allRequestedMatchPatterns
            .union(extensionContext.webExtension.optionalPermissionMatchPatterns)
        var contextPatterns = Set(extensionContext.grantedPermissionMatchPatterns.keys)
        var tabPatterns = Set<WKWebExtension.MatchPattern>()

        for pattern in declaredPatterns {
            if manager.isGrantedPermissionStatus(
                extensionContext.permissionStatus(for: pattern)
            ) {
                contextPatterns.insert(pattern)
            } else if let tab,
                      manager.isGrantedPermissionStatus(
                          extensionContext.permissionStatus(for: pattern, in: tab)
                      ) {
                tabPatterns.insert(pattern)
            }
        }

        if contextPatterns.contains(where: { $0.matches(url) }) {
            return .context
        }
        if tabPatterns.contains(where: { $0.matches(url) }) {
            return .tab
        }
        return .none
    }
}
