import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionPermissionDelegateCallbackOwner {
    func promptForPermissions(
        _ permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        manager: ExtensionManager,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        let manifest = manager.extensionID(for: extensionContext)
            .flatMap { manager.loadedExtensionManifests[$0] } ?? [:]
        let policyDeniedPermissions = permissions
            .filter { manager.shouldDenyAutoGrantForWebKitRuntime($0, manifest: manifest) }
        for permission in policyDeniedPermissions {
            extensionContext.setPermissionStatus(.deniedExplicitly, for: permission)
        }

        let unresolvedPermissions = permissions.subtracting(policyDeniedPermissions).filter {
            manager.isGrantedPermissionStatus(
                manager.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
            ) == false
        }
        let extensionId = manager.extensionID(for: extensionContext)
        let profileId = manager.profileId(for: extensionContext)
        let storedResolvedPermissions = ExtensionPermissionPromptRoutingOwner
            .applyStoredPermissionDecisions(
                to: unresolvedPermissions,
                in: extensionContext,
                extensionId: extensionId,
                profileId: profileId,
                manager: manager
            )

        let promptPermissions = unresolvedPermissions.subtracting(storedResolvedPermissions)

        guard promptPermissions.isEmpty == false else {
            completionHandler(
                ExtensionPermissionPromptRoutingOwner.grantedPermissions(
                    from: permissions,
                    in: extensionContext,
                    tab: tab,
                    manager: manager
                ),
                nil
            )
            return
        }

        Task { @MainActor [weak manager] in
            guard let manager else {
                completionHandler([], nil)
                return
            }
            let decision = await manager.promptForExtensionPermissionDecision(
                extensionContext: extensionContext,
                targets: promptPermissions.map(\.rawValue),
                reason: "promptForPermissions",
                dedupeKey: manager.permissionPromptDedupeKey(
                    extensionContext: extensionContext,
                    targets: promptPermissions.map(\.rawValue)
                )
            )
            switch decision {
            case .allow(let expirationDate):
                for permission in promptPermissions {
                    extensionContext.setPermissionStatus(
                        .grantedExplicitly,
                        for: permission,
                        expirationDate: expirationDate
                    )
                    if let extensionId, let profileId {
                        manager.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .permission,
                            target: permission.rawValue,
                            state: .allowed,
                            expiresAt: expirationDate
                        )
                    }
                }
                completionHandler(
                    ExtensionPermissionPromptRoutingOwner.grantedPermissions(
                        from: permissions,
                        in: extensionContext,
                        tab: tab,
                        manager: manager
                    ),
                    expirationDate
                )
            case .deny:
                for permission in promptPermissions {
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: permission,
                        expirationDate: nil
                    )
                    if let extensionId, let profileId {
                        manager.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .permission,
                            target: permission.rawValue,
                            state: .denied,
                            expiresAt: nil
                        )
                    }
                }
                completionHandler(
                    ExtensionPermissionPromptRoutingOwner.grantedPermissions(
                        from: permissions,
                        in: extensionContext,
                        tab: tab,
                        manager: manager
                    ),
                    nil
                )
            }
        }
    }

    func promptForPermissionMatchPatterns(
        _ matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        manager: ExtensionManager,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let unresolvedMatches = matchPatterns.filter {
            manager.isGrantedPermissionStatus(
                manager.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
            ) == false
        }
        let extensionId = manager.extensionID(for: extensionContext)
        let profileId = manager.profileId(for: extensionContext)
        let policyResolvedMatches = ExtensionPermissionPromptRoutingOwner
            .applyConfiguredSiteAccessDecisions(
                to: unresolvedMatches,
                in: extensionContext,
                extensionId: extensionId,
                profileId: profileId,
                manager: manager
            )

        let promptMatches = unresolvedMatches
            .subtracting(policyResolvedMatches)

        guard promptMatches.isEmpty == false else {
            completionHandler(
                ExtensionPermissionPromptRoutingOwner.grantedMatchPatterns(
                    from: matchPatterns,
                    in: extensionContext,
                    tab: tab,
                    manager: manager
                ),
                nil
            )
            return
        }

        Task { @MainActor [weak manager] in
            guard let manager else {
                completionHandler([], nil)
                return
            }
            let decision = await manager.promptForExtensionPermissionDecision(
                extensionContext: extensionContext,
                targets: promptMatches.map(Self.extensionPermissionTarget(for:)),
                reason: "promptForPermissionMatchPatterns",
                dedupeKey: manager.permissionPromptDedupeKey(
                    extensionContext: extensionContext,
                    targets: promptMatches.map(\.string)
                )
            )
            switch decision {
            case .allow(let expirationDate):
                for matchPattern in promptMatches {
                    extensionContext.setPermissionStatus(
                        .grantedExplicitly,
                        for: matchPattern,
                        expirationDate: expirationDate
                    )
                    if let extensionId, let profileId {
                        manager.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .matchPattern,
                            target: matchPattern.string,
                            state: .allowed,
                            expiresAt: expirationDate
                        )
                        manager.setConfiguredSiteAccess(
                            .allow,
                            extensionId: extensionId,
                            profileId: profileId,
                            matchPatternString: matchPattern.string,
                            expiresAt: expirationDate
                        )
                    }
                }
                completionHandler(
                    ExtensionPermissionPromptRoutingOwner.grantedMatchPatterns(
                        from: matchPatterns,
                        in: extensionContext,
                        tab: tab,
                        manager: manager
                    ),
                    expirationDate
                )
            case .deny:
                for matchPattern in promptMatches {
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: matchPattern,
                        expirationDate: nil
                    )
                    if let extensionId, let profileId {
                        manager.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .matchPattern,
                            target: matchPattern.string,
                            state: .denied,
                            expiresAt: nil
                        )
                        manager.setConfiguredSiteAccess(
                            .deny,
                            extensionId: extensionId,
                            profileId: profileId,
                            matchPatternString: matchPattern.string
                        )
                    }
                }
                completionHandler(
                    ExtensionPermissionPromptRoutingOwner.grantedMatchPatterns(
                        from: matchPatterns,
                        in: extensionContext,
                        tab: tab,
                        manager: manager
                    ),
                    nil
                )
            }
        }
    }

    func promptForPermissionToAccess(
        _ urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        manager: ExtensionManager,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        let extensionId = manager.extensionID(for: extensionContext)
        let profileId = manager.profileId(for: extensionContext)
        let resolution = ExtensionPermissionPromptRoutingOwner.resolveURLPermissionsBeforePrompt(
            urls: urls,
            in: extensionContext,
            tab: tab,
            extensionId: extensionId,
            profileId: profileId,
            manager: manager
        )

        guard resolution.unresolved.isEmpty == false else {
            completionHandler(resolution.autoGranted, nil)
            return
        }

        Task { @MainActor [weak manager] in
            guard let manager else {
                completionHandler(resolution.autoGranted, nil)
                return
            }
            let promptPatterns = resolution.unresolved.compactMap {
                manager.hostMatchPatternString(for: $0)
            }
            let decision = await manager.promptForExtensionPermissionDecision(
                extensionContext: extensionContext,
                targets: resolution.unresolved.map(Self.extensionPermissionTarget(for:)),
                reason: "promptForPermissionToAccess",
                dedupeKey: manager.permissionPromptDedupeKey(
                    extensionContext: extensionContext,
                    targets: promptPatterns.isEmpty
                        ? resolution.unresolved.map(Self.extensionPermissionTarget(for:))
                        : promptPatterns
                )
            )
            switch decision {
            case .allow(let expirationDate):
                for url in resolution.unresolved {
                    manager.grantSiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId,
                        expirationDate: expirationDate
                    )
                    if let patternString = manager.hostMatchPatternString(for: url),
                       let extensionId,
                       let profileId {
                        manager.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .matchPattern,
                            target: patternString,
                            state: .allowed,
                            expiresAt: expirationDate
                        )
                    }
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: true,
                        extensionId: extensionId,
                        reason: "promptAllowed"
                    )
                }
                completionHandler(
                    resolution.autoGranted.union(resolution.unresolved),
                    expirationDate
                )
            case .deny:
                for url in resolution.unresolved {
                    manager.denySiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId
                    )
                    if let patternString = manager.hostMatchPatternString(for: url),
                       let extensionId,
                       let profileId {
                        manager.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .matchPattern,
                            target: patternString,
                            state: .denied,
                            expiresAt: nil
                        )
                    }
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: false,
                        extensionId: extensionId,
                        reason: "promptDenied"
                    )
                }
                completionHandler(resolution.autoGranted, nil)
            }
        }
    }

    nonisolated private static func extensionPermissionTarget(for url: URL) -> String {
        if let host = url.host, host.isEmpty == false {
            return host
        }
        if let scheme = url.scheme, scheme.isEmpty == false {
            return "\(scheme):"
        }
        return "this site"
    }

    private static func extensionPermissionTarget(
        for matchPattern: WKWebExtension.MatchPattern
    ) -> String {
        if matchPattern.matchesAllURLs || matchPattern.matchesAllHosts {
            return "all websites"
        }
        if let host = matchPattern.host, host.isEmpty == false {
            return host
        }
        return matchPattern.string
    }
}
