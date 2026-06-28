import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
enum ExtensionPermissionPromptRoutingOwner {
    struct URLPermissionPromptResolution {
        let autoGranted: Set<URL>
        let unresolved: Set<URL>
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

    static func applyStoredPermissionDecisions(
        to permissions: Set<WKWebExtension.Permission>,
        in extensionContext: WKWebExtensionContext,
        extensionId: String?,
        profileId: UUID?,
        manager: ExtensionManager
    ) -> Set<WKWebExtension.Permission> {
        guard let extensionId, let profileId else { return [] }

        var resolvedPermissions = Set<WKWebExtension.Permission>()
        for permission in permissions {
            guard let stored = manager.storedExtensionPermissionDecision(
                extensionId: extensionId,
                profileId: profileId,
                targetKind: .permission,
                target: permission.rawValue
            ) else { continue }
            let status: WKWebExtensionContext.PermissionStatus =
                stored.state == .allowed ? .grantedExplicitly : .deniedExplicitly
            extensionContext.setPermissionStatus(
                status,
                for: permission,
                expirationDate: stored.expiresAt
            )
            resolvedPermissions.insert(permission)
        }
        return resolvedPermissions
    }

    static func applyConfiguredSiteAccessDecisions(
        to matchPatterns: Set<WKWebExtension.MatchPattern>,
        in extensionContext: WKWebExtensionContext,
        extensionId: String?,
        profileId: UUID?,
        manager: ExtensionManager
    ) -> Set<WKWebExtension.MatchPattern> {
        guard let extensionId, let profileId else { return [] }

        var resolvedMatches = Set<WKWebExtension.MatchPattern>()
        for matchPattern in matchPatterns {
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
                resolvedMatches.insert(matchPattern)
            case .deny:
                extensionContext.setPermissionStatus(
                    .deniedExplicitly,
                    for: matchPattern
                )
                resolvedMatches.insert(matchPattern)
            case .ask:
                break
            }
        }
        return resolvedMatches
    }

    static func resolveURLPermissionsBeforePrompt(
        urls: Set<URL>,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?,
        extensionId: String?,
        profileId: UUID?,
        manager: ExtensionManager
    ) -> URLPermissionPromptResolution {
        var autoGranted = Set<URL>()
        var unresolved = Set<URL>()

        for url in urls {
            let status = manager.effectivePermissionStatus(
                for: url,
                in: extensionContext,
                tab: tab
            )
            if manager.isGrantedPermissionStatus(status) {
                autoGranted.insert(url)
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: true,
                    extensionId: extensionId,
                    reason: "promptAlreadyGranted"
                )
            } else if status == .deniedExplicitly {
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: false,
                    extensionId: extensionId,
                    reason: "promptAlreadyDenied"
                )
            } else if manager.explicitlyGrantURLIfCoveredByGrantedMatchPattern(
                url,
                in: extensionContext,
                tab: tab
            ) {
                autoGranted.insert(url)
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: true,
                    extensionId: extensionId,
                    reason: "promptMatchPattern"
                )
            } else if let extensionId,
                      let profileId,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                switch manager.configuredSiteAccessLevel(
                    for: url,
                    extensionId: extensionId,
                    profileId: profileId
                ) {
                case .allow:
                    manager.grantSiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId,
                        persistPolicy: false
                    )
                    autoGranted.insert(url)
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: true,
                        extensionId: extensionId,
                        reason: "promptSiteAccessAllowed"
                    )
                case .deny:
                    manager.denySiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId,
                        persistPolicy: false
                    )
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: false,
                        extensionId: extensionId,
                        reason: "promptSiteAccessDenied"
                    )
                case .ask:
                    unresolved.insert(url)
                }
            } else if let patternString = manager.hostMatchPatternString(for: url),
                      let extensionId,
                      let profileId,
                      let stored = manager.storedExtensionPermissionDecision(
                          extensionId: extensionId,
                          profileId: profileId,
                          targetKind: .matchPattern,
                          target: patternString
                      ),
                      let matchPattern = try? WKWebExtension.MatchPattern(
                          string: patternString
                      ) {
                let storedStatus: WKWebExtensionContext.PermissionStatus =
                    stored.state == .allowed ? .grantedExplicitly : .deniedExplicitly
                extensionContext.setPermissionStatus(
                    storedStatus,
                    for: matchPattern,
                    expirationDate: stored.expiresAt
                )
                if stored.state == .allowed,
                   manager.explicitlyGrantURLIfCoveredByGrantedMatchPattern(
                       url,
                       in: extensionContext,
                       tab: tab
                   ) {
                    autoGranted.insert(url)
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: true,
                        extensionId: extensionId,
                        reason: "promptStoredMatchPattern"
                    )
                } else {
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: false,
                        extensionId: extensionId,
                        reason: "promptStoredDeniedMatchPattern"
                    )
                }
            } else {
                unresolved.insert(url)
            }
        }

        return URLPermissionPromptResolution(
            autoGranted: autoGranted,
            unresolved: unresolved
        )
    }
}
