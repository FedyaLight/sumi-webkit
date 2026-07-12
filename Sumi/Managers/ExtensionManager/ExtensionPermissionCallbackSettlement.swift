import Foundation
import WebKit

/// Settles the three WebKit permission-prompt delegate callbacks against
/// typed callback evidence. Every observable or persistent effect is
/// revalidated against the exact current controller/context binding; a stale
/// callback stops before its next effect and answers fail-closed exactly once.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPermissionCallbackSettlement {
    private let admission: ExtensionControllerCallbackAdmission

    init(admission: ExtensionControllerCallbackAdmission) {
        self.admission = admission
    }

    func promptForPermissions(
        _ permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        evidence: ExtensionControllerCallbackEvidence,
        manager: ExtensionManager,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        let extensionContext = evidence.context
        let unresolvedPermissions = permissions.filter {
            manager.isGrantedPermissionStatus(
                manager.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
            ) == false
        }

        var storedResolvedPermissions = Set<WKWebExtension.Permission>()
        for permission in unresolvedPermissions {
            // Each stored-decision replay publishes observable context state
            // that can reentrantly replace the binding.
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            if ExtensionPermissionPromptRouting.applyStoredPermissionDecision(
                to: permission,
                in: extensionContext,
                extensionId: evidence.extensionID,
                profileId: evidence.profileID,
                manager: manager
            ) {
                storedResolvedPermissions.insert(permission)
            }
        }

        let promptPermissions = unresolvedPermissions.subtracting(storedResolvedPermissions)

        guard promptPermissions.isEmpty == false else {
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            completionHandler(
                ExtensionPermissionPromptRouting.grantedPermissions(
                    from: permissions,
                    in: extensionContext,
                    tab: tab,
                    manager: manager
                ),
                nil
            )
            return
        }

        Task { @MainActor [weak manager, admission = self.admission] in
            guard let manager else {
                completionHandler([], nil)
                return
            }
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            let decision = await manager.promptForExtensionPermissionDecision(
                extensionContext: extensionContext,
                targets: promptPermissions.map(\.rawValue),
                reason: "promptForPermissions",
                dedupeKey: manager.permissionPromptDedupeKey(
                    profileID: evidence.profileID,
                    extensionID: evidence.extensionID,
                    targets: promptPermissions.map(\.rawValue)
                ),
                extensionIdentifier: evidence.extensionID
            )
            let settlement = Self.settlement(for: decision)

            for permission in promptPermissions {
                guard admission.isCurrent(evidence) else {
                    completionHandler([], nil)
                    return
                }
                extensionContext.setPermissionStatus(
                    settlement.status,
                    for: permission,
                    expirationDate: settlement.expirationDate
                )
                guard admission.isCurrent(evidence) else {
                    completionHandler([], nil)
                    return
                }
                manager.persistExtensionPermissionDecision(
                    extensionId: evidence.extensionID,
                    profileId: evidence.profileID,
                    targetKind: .permission,
                    target: permission.rawValue,
                    state: settlement.storedState,
                    expiresAt: settlement.expirationDate
                )
            }
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            completionHandler(
                ExtensionPermissionPromptRouting.grantedPermissions(
                    from: permissions,
                    in: extensionContext,
                    tab: tab,
                    manager: manager
                ),
                settlement.expirationDate
            )
        }
    }

    func promptForPermissionMatchPatterns(
        _ matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        evidence: ExtensionControllerCallbackEvidence,
        manager: ExtensionManager,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let extensionContext = evidence.context
        let unresolvedMatches = matchPatterns.filter {
            manager.isGrantedPermissionStatus(
                manager.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
            ) == false
        }

        var policyResolvedMatches = Set<WKWebExtension.MatchPattern>()
        for matchPattern in unresolvedMatches {
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            if ExtensionPermissionPromptRouting.applyConfiguredSiteAccessDecision(
                to: matchPattern,
                in: extensionContext,
                extensionId: evidence.extensionID,
                profileId: evidence.profileID,
                manager: manager
            ) {
                policyResolvedMatches.insert(matchPattern)
            }
        }

        let promptMatches = unresolvedMatches.subtracting(policyResolvedMatches)

        guard promptMatches.isEmpty == false else {
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            completionHandler(
                ExtensionPermissionPromptRouting.grantedMatchPatterns(
                    from: matchPatterns,
                    in: extensionContext,
                    tab: tab,
                    manager: manager
                ),
                nil
            )
            return
        }

        Task { @MainActor [weak manager, admission = self.admission] in
            guard let manager else {
                completionHandler([], nil)
                return
            }
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            let decision = await manager.promptForExtensionPermissionDecision(
                extensionContext: extensionContext,
                targets: promptMatches.map(Self.extensionPermissionTarget(for:)),
                reason: "promptForPermissionMatchPatterns",
                dedupeKey: manager.permissionPromptDedupeKey(
                    profileID: evidence.profileID,
                    extensionID: evidence.extensionID,
                    targets: promptMatches.map(\.string)
                ),
                extensionIdentifier: evidence.extensionID
            )
            let settlement = Self.settlement(for: decision)

            for matchPattern in promptMatches {
                guard admission.isCurrent(evidence) else {
                    completionHandler([], nil)
                    return
                }
                extensionContext.setPermissionStatus(
                    settlement.status,
                    for: matchPattern,
                    expirationDate: settlement.expirationDate
                )
                guard admission.isCurrent(evidence) else {
                    completionHandler([], nil)
                    return
                }
                manager.persistExtensionPermissionDecision(
                    extensionId: evidence.extensionID,
                    profileId: evidence.profileID,
                    targetKind: .matchPattern,
                    target: matchPattern.string,
                    state: settlement.storedState,
                    expiresAt: settlement.expirationDate
                )
                guard admission.isCurrent(evidence) else {
                    completionHandler([], nil)
                    return
                }
                manager.setConfiguredSiteAccess(
                    settlement.storedState == .allowed ? .allow : .deny,
                    extensionId: evidence.extensionID,
                    profileId: evidence.profileID,
                    matchPatternString: matchPattern.string,
                    expiresAt: settlement.expirationDate
                )
            }
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            completionHandler(
                ExtensionPermissionPromptRouting.grantedMatchPatterns(
                    from: matchPatterns,
                    in: extensionContext,
                    tab: tab,
                    manager: manager
                ),
                settlement.expirationDate
            )
        }
    }

    private struct DecisionSettlement {
        let status: WKWebExtensionContext.PermissionStatus
        let storedState: ExtensionManager.ExtensionStoredPermissionState
        let expirationDate: Date?
    }

    private static func settlement(
        for decision: ExtensionManager.ExtensionPermissionPromptDecision
    ) -> DecisionSettlement {
        switch decision {
        case .allow(let expirationDate):
            return DecisionSettlement(
                status: .grantedExplicitly,
                storedState: .allowed,
                expirationDate: expirationDate
            )
        case .deny:
            return DecisionSettlement(
                status: .deniedExplicitly,
                storedState: .denied,
                expirationDate: nil
            )
        }
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
