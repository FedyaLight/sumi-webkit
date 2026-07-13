import Foundation
import WebKit

/// Translates one persisted site-access policy into the smallest required
/// WebKit context diff. It deliberately owns neither persistence nor context
/// identity so callers retain transaction authority around the mutation.
@available(macOS 15.5, *)
@MainActor
struct ExtensionSiteAccessPolicyApplicator {
    struct Input {
        let extensionID: String
        let profileID: UUID
        let policy: SafariExtensionSiteAccessPolicy
        let installedExtension: InstalledExtension?
        let manifest: [String: Any]?
    }

    func apply(
        to context: WKWebExtensionContext,
        webExtension: WKWebExtension,
        input: Input
    ) {
        let policy = input.policy
        SafariExtensionPermissionLifecycleDiagnostics.logContextApplication(
            SafariExtensionContextApplicationSnapshot(
                contextLoaded: context.isLoaded,
                extensionBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    input.extensionID
                ),
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    input.profileID
                ),
                controllerBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    context.webExtensionController.map {
                        String(describing: ObjectIdentifier($0))
                    }
                ),
                appliedBeforeNavigation: nil,
                permissionAPIPath: .global,
                persistedPolicyDivergenceObserved: nil
            )
        )
        context.hasAccessToPrivateData =
            policy.privateAccessAllowed
            && (input.installedExtension?.incognitoMode.allowsPrivateAccess ?? true)
        context.hasRequestedOptionalAccessToAllHosts =
            policy.hasRequestedOptionalAccessToAllHosts

        let declaredPatterns = declaredMatchPatterns(
            for: webExtension,
            manifest: input.manifest
        )
        if let manifest = input.manifest {
            let surfaces = SafariExtensionManifestAccessSurfaces.from(
                manifest: manifest
            )
            SafariExtensionPermissionLifecycleDiagnostics.logPolicySnapshot(
                SafariExtensionPolicySnapshot(
                    extensionEnabled: input.installedExtension?.isEnabled ?? true,
                    extensionBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                        input.extensionID
                    ),
                    profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                        input.profileID
                    ),
                    tabBucket: nil,
                    isPrivate: context.hasAccessToPrivateData,
                    originHost: nil,
                    decisionSource: policy.defaultAccess.diagnosticDecisionSource,
                    declaredSurfaces: [
                        surfaces.contentScriptHosts.isEmpty ? nil : .contentScripts,
                        surfaces.hostPermissionHosts.isEmpty ? nil : .hostPermissions,
                        surfaces.optionalPermissionHosts.isEmpty ? nil : .optionalPermissions,
                        surfaces.externallyConnectableHosts.isEmpty ? nil : .externallyConnectable,
                    ].compactMap { $0 },
                    externallyConnectableReportedSeparately: true
                )
            )
        }

        let declaresAllHosts = declaredPatterns.contains {
            $0 == WKWebExtension.MatchPattern.allHostsAndSchemes()
                || $0 == WKWebExtension.MatchPattern.allURLs()
        }
        let policyAllowsAllHosts =
            (policy.defaultAccess == .allow && declaresAllHosts)
            || policy.siteRules.contains {
                $0.access == .allow && isAllHostsPattern($0.matchPattern)
            }
        if policyAllowsAllHosts {
            context.hasRequestedOptionalAccessToAllHosts = true
        }

        var desiredStates: [WKWebExtension.MatchPattern: (
            access: SafariExtensionSiteAccessLevel,
            expiresAt: Date?
        )] = [:]
        for pattern in declaredPatterns {
            desiredStates[pattern] = (policy.defaultAccess, nil)
        }
        for rule in policy.rulesByIncreasingSpecificity {
            guard let pattern = matchPattern(
                from: rule.matchPattern,
                purpose: "configuredRule"
            ) else {
                continue
            }
            desiredStates[pattern] = (rule.access, rule.expiresAt)
        }

        // Re-applying an unchanged policy must not emit WebKit permission
        // removal/addition storms. Change only status or expiration values
        // that actually differ.
        let grantedPatterns = context.grantedPermissionMatchPatterns
        let deniedPatterns = context.deniedPermissionMatchPatterns
        for (pattern, desired) in desiredStates {
            switch desired.access {
            case .allow:
                if let current = grantedPatterns[pattern],
                   expirationDatesEquivalent(current, desired.expiresAt) {
                    continue
                }
                if grantedPatterns[pattern] != nil {
                    context.setPermissionStatus(.unknown, for: pattern)
                }
                context.setPermissionStatus(
                    .grantedExplicitly,
                    for: pattern,
                    expirationDate: desired.expiresAt
                )
            case .deny:
                if let current = deniedPatterns[pattern],
                   expirationDatesEquivalent(current, desired.expiresAt) {
                    continue
                }
                if deniedPatterns[pattern] != nil {
                    context.setPermissionStatus(.unknown, for: pattern)
                }
                context.setPermissionStatus(
                    .deniedExplicitly,
                    for: pattern,
                    expirationDate: desired.expiresAt
                )
            case .ask:
                if grantedPatterns[pattern] != nil
                    || deniedPatterns[pattern] != nil {
                    context.setPermissionStatus(.unknown, for: pattern)
                }
            }
        }
    }

    func declaredMatchPatterns(
        for webExtension: WKWebExtension,
        manifest: [String: Any]? = nil
    ) -> Set<WKWebExtension.MatchPattern> {
        var patterns = webExtension.requestedPermissionMatchPatterns
            .union(webExtension.allRequestedMatchPatterns)
            .union(webExtension.optionalPermissionMatchPatterns)
        guard let manifest else { return patterns }

        let siteAccessPatterns = rawSiteAccessPatterns(from: manifest)
        let externalOnlyPatterns = rawExternalMessagingPatterns(from: manifest)
            .subtracting(siteAccessPatterns)
        patterns.formUnion(siteAccessPatterns)
        patterns.subtract(externalOnlyPatterns)
        return patterns
    }

    private func rawSiteAccessPatterns(
        from manifest: [String: Any]
    ) -> Set<WKWebExtension.MatchPattern> {
        let permissions = strings(from: manifest["permissions"])
        let optionalPermissions = strings(from: manifest["optional_permissions"])
        let contentScriptMatches =
            (manifest["content_scripts"] as? [[String: Any]] ?? [])
                .flatMap { strings(from: $0["matches"]) }
        let patternStrings =
            strings(from: manifest["host_permissions"])
            + strings(from: manifest["optional_host_permissions"])
            + permissions.filter(isHostPermissionPattern)
            + optionalPermissions.filter(isHostPermissionPattern)
            + contentScriptMatches
        return Set(patternStrings.compactMap {
            matchPattern(from: $0, purpose: "manifestSiteAccess")
        })
    }

    private func rawExternalMessagingPatterns(
        from manifest: [String: Any]
    ) -> Set<WKWebExtension.MatchPattern> {
        let patternStrings =
            (manifest["externally_connectable"] as? [String: Any])
                .map { strings(from: $0["matches"]) } ?? []
        return Set(patternStrings.compactMap {
            matchPattern(from: $0, purpose: "externallyConnectable")
        })
    }

    private func strings(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private func isHostPermissionPattern(_ value: String) -> Bool {
        value == "<all_urls>"
            || value.hasPrefix("http://")
            || value.hasPrefix("https://")
            || value.hasPrefix("*://")
    }

    private func isAllHostsPattern(_ value: String) -> Bool {
        guard let pattern = matchPattern(from: value, purpose: "allHostsRule")
        else {
            return false
        }
        return pattern == WKWebExtension.MatchPattern.allHostsAndSchemes()
            || pattern == WKWebExtension.MatchPattern.allURLs()
    }

    private func matchPattern(
        from value: String,
        purpose: String
    ) -> WKWebExtension.MatchPattern? {
        do {
            return try WKWebExtension.MatchPattern(string: value)
        } catch {
            RuntimeDiagnostics.debug(
                category: SafariExtensionPermissionLifecycleDiagnostics.category
            ) {
                let bucket = SafariExtensionPermissionLifecycleDiagnostics.bucket(value)
                    ?? "empty"
                return "Ignoring invalid extension match pattern: purpose=\(purpose) patternBucket=\(bucket) error=\(error.localizedDescription)"
            }
            return nil
        }
    }

    /// WebKit represents a never-expiring grant with a far-future date.
    private func expirationDatesEquivalent(
        _ current: Date,
        _ desired: Date?
    ) -> Bool {
        let farFutureThreshold = Date(
            timeIntervalSinceNow: 60 * 60 * 24 * 365 * 20
        )
        guard let desired else { return current >= farFutureThreshold }
        if current >= farFutureThreshold { return false }
        return abs(current.timeIntervalSince(desired)) < 1
    }
}
