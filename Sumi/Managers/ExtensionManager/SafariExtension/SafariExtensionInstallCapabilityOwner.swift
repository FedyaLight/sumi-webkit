//
//  SafariExtensionInstallCapabilityOwner.swift
//  Sumi
//
//  WebKit permission and capability policy applied while extension contexts are built.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionInstallCapabilityOwner {
    struct SiteAccessApplicationInput {
        let extensionId: String
        let profileId: UUID
        let policy: SafariExtensionSiteAccessPolicy
        let installedExtension: InstalledExtension?
        let manifest: [String: Any]?
    }

    func grantRequestedPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension,
        extensionId: String? = nil,
        profileId: UUID? = nil,
        manifest: [String: Any]
    ) {
        var permissions = webExtension.requestedPermissions
        permissions.formUnion(Self.requiredManifestWebExtensionPermissions(from: manifest))
        grantNativeMessagingPermissionIfDeclared(
            to: extensionContext,
            permissions: &permissions,
            extensionId: extensionId,
            profileId: profileId,
            manifest: manifest
        )

        for permission in permissions {
            if shouldDenyAutoGrantForWebKitRuntime(permission, manifest: manifest) {
                extensionContext.setPermissionStatus(.deniedExplicitly, for: permission)
                continue
            }
            extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
        }
    }

    func applyConfiguredSiteAccessPolicy(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension,
        input: SiteAccessApplicationInput
    ) {
        let policy = input.policy
        SafariExtensionPermissionLifecycleDiagnostics.logContextApplication(
            SafariExtensionContextApplicationSnapshot(
                contextLoaded: extensionContext.isLoaded,
                extensionBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    input.extensionId
                ),
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    input.profileId
                ),
                controllerBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    extensionContext.webExtensionController.map {
                        String(describing: ObjectIdentifier($0))
                    }
                ),
                appliedBeforeNavigation: nil,
                permissionAPIPath: .global,
                persistedPolicyDivergenceObserved: nil
            )
        )
        extensionContext.hasAccessToPrivateData =
            policy.privateAccessAllowed
            && (input.installedExtension?.incognitoMode.allowsPrivateAccess ?? true)
        extensionContext.hasRequestedOptionalAccessToAllHosts =
            policy.hasRequestedOptionalAccessToAllHosts

        let declaredPatterns = declaredSiteAccessMatchPatterns(
            for: webExtension,
            manifest: input.manifest
        )
        if let manifest = input.manifest {
            let surfaces = SafariExtensionManifestAccessSurfaces.from(manifest: manifest)
            SafariExtensionPermissionLifecycleDiagnostics.logPolicySnapshot(
                SafariExtensionPolicySnapshot(
                    extensionEnabled: input.installedExtension?.isEnabled ?? true,
                    extensionBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                        input.extensionId
                    ),
                    profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                        input.profileId
                    ),
                    tabBucket: nil,
                    isPrivate: extensionContext.hasAccessToPrivateData,
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
                $0.access == .allow && Self.isAllHostsMatchPatternString($0.matchPattern)
            }
        if policyAllowsAllHosts {
            extensionContext.hasRequestedOptionalAccessToAllHosts = true
        }
        for matchPattern in declaredPatterns {
            extensionContext.setPermissionStatus(.unknown, for: matchPattern)
        }

        switch policy.defaultAccess {
        case .allow:
            for matchPattern in declaredPatterns {
                extensionContext.setPermissionStatus(
                    .grantedExplicitly,
                    for: matchPattern
                )
            }
        case .deny:
            for matchPattern in declaredPatterns {
                extensionContext.setPermissionStatus(
                    .deniedExplicitly,
                    for: matchPattern
                )
            }
        case .ask:
            break
        }

        for rule in policy.rulesByIncreasingSpecificity {
            guard let matchPattern = try? WKWebExtension.MatchPattern(
                string: rule.matchPattern
            )
            else {
                continue
            }
            extensionContext.setPermissionStatus(
                rule.access.status,
                for: matchPattern,
                expirationDate: rule.expiresAt
            )
        }
    }

    func declaredSiteAccessMatchPatterns(
        for webExtension: WKWebExtension,
        manifest: [String: Any]? = nil
    ) -> Set<WKWebExtension.MatchPattern> {
        var matchPatterns = webExtension.requestedPermissionMatchPatterns
            .union(webExtension.allRequestedMatchPatterns)
            .union(webExtension.optionalPermissionMatchPatterns)
        if let manifest {
            let rawSiteAccessPatterns = rawManifestSiteAccessMatchPatterns(
                from: manifest
            )
            let externalMessagingOnlyPatterns = rawManifestExternalMessagingMatchPatterns(
                from: manifest
            ).subtracting(rawSiteAccessPatterns)
            matchPatterns.formUnion(rawSiteAccessPatterns)
            matchPatterns.subtract(externalMessagingOnlyPatterns)
        }
        return matchPatterns
    }

    /// Grants temporary host access for the active tab when the manifest declares `activeTab`.
    func grantActiveTabURLAccess(
        for extensionContext: WKWebExtensionContext,
        tab: Tab,
        manifest: [String: Any],
        extensionId: String?,
        profileId: UUID?
    ) {
        let url = tab.url
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            SafariExtensionAutofillFillDiagnostics.recordActiveTabPermission(
                granted: false,
                extensionId: extensionId,
                reason: "nonHTTPActiveTab"
            )
            return
        }

        let permissions = (manifest["permissions"] as? [String] ?? [])
            + (manifest["optional_permissions"] as? [String] ?? [])
        guard permissions.contains("activeTab") else {
            SafariExtensionAutofillFillDiagnostics.recordActiveTabPermission(
                granted: false,
                extensionId: extensionId,
                reason: "activeTabNotDeclared"
            )
            return
        }

        extensionContext.setPermissionStatus(.grantedExplicitly, for: url)
        SafariExtensionPermissionLifecycleDiagnostics.logPolicySnapshot(
            SafariExtensionPolicySnapshot(
                extensionEnabled: true,
                extensionBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    extensionId
                ),
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    profileId
                ),
                tabBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(tab.id),
                isPrivate: tab.isEphemeral,
                originHost: SafariExtensionPermissionLifecycleDiagnostics.host(from: url),
                decisionSource: .activeTabTemporaryGrant,
                declaredSurfaces: [.activeTab],
                externallyConnectableReportedSeparately: true
            )
        )
        SafariExtensionPermissionLifecycleDiagnostics.logContextApplication(
            SafariExtensionContextApplicationSnapshot(
                contextLoaded: extensionContext.isLoaded,
                extensionBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    extensionId
                ),
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    profileId
                ),
                controllerBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    extensionContext.webExtensionController.map {
                        String(describing: ObjectIdentifier($0))
                    }
                ),
                appliedBeforeNavigation: false,
                permissionAPIPath: .global,
                persistedPolicyDivergenceObserved: nil
            )
        )
        SafariExtensionAutofillFillDiagnostics.recordActiveTabPermission(
            granted: true,
            extensionId: extensionId,
            reason: "activeTabGranted"
        )
    }

    func prepareExtensionContextForRuntime(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        manifest: [String: Any]
    ) {
        extensionContext.unsupportedAPIs = Self.webKitRuntimeUnsupportedAPIs(
            for: manifest
        )
        SafariExtensionAutofillFillDiagnostics.recordScriptingAvailability(
            extensionContext: extensionContext,
            manifest: manifest
        )
        SafariExtensionNativeMessagingPermissionDiagnostics.logContextState(
            extensionId: extensionId,
            profileId: profileId,
            manifestDeclaresNativeMessaging: Self.manifestDeclaresNativeMessaging(
                manifest
            ),
            permissionGranted: isGrantedPermissionStatus(
                extensionContext.permissionStatus(for: .nativeMessaging)
            ),
            unsupportedAPIsContainNativeMessaging: extensionContext.unsupportedAPIs
                .contains { $0.localizedCaseInsensitiveContains("nativeMessaging") }
        )
    }

    func webExtensionStoreCapabilitySnapshot(
        for manifest: [String: Any]
    ) -> WebExtensionStorageCleanupPlanner.StoreCapabilitySnapshot {
        WebExtensionStorageCleanupPlanner.shared.storeCapabilitySnapshot(
            for: manifest,
            unsupportedAPIs: Self.webKitRuntimeUnsupportedAPIs(for: manifest)
        )
    }

    func shouldDenyAutoGrantForWebKitRuntime(
        _ permission: WKWebExtension.Permission,
        manifest: [String: Any]
    ) -> Bool {
        Self.shouldDenyAutoGrantForWebKitRuntime(permission, manifest: manifest)
    }

    func isGrantedPermissionStatus(
        _ status: WKWebExtensionContext.PermissionStatus
    ) -> Bool {
        status == .grantedExplicitly || status == .grantedImplicitly
    }

    func effectivePermissionStatus(
        for permission: WKWebExtension.Permission,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        guard let tab else {
            return extensionContext.permissionStatus(for: permission)
        }
        let tabStatus = extensionContext.permissionStatus(for: permission, in: tab)
        guard tabStatus == .unknown else { return tabStatus }
        return extensionContext.permissionStatus(for: permission)
    }

    func effectivePermissionStatus(
        for matchPattern: WKWebExtension.MatchPattern,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        guard let tab else {
            return extensionContext.permissionStatus(for: matchPattern)
        }
        let tabStatus = extensionContext.permissionStatus(for: matchPattern, in: tab)
        guard tabStatus == .unknown else { return tabStatus }
        return extensionContext.permissionStatus(for: matchPattern)
    }

    func effectivePermissionStatus(
        for url: URL,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        guard let tab else {
            return extensionContext.permissionStatus(for: url)
        }
        let tabStatus = extensionContext.permissionStatus(for: url, in: tab)
        guard tabStatus == .unknown else { return tabStatus }
        return extensionContext.permissionStatus(for: url)
    }

    func explicitlyGrantURLIfCoveredByGrantedMatchPattern(
        _ url: URL,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)? = nil
    ) -> Bool {
        var grantedPatterns = Set(extensionContext.grantedPermissionMatchPatterns.keys)
        let declaredPatterns = extensionContext.webExtension
            .allRequestedMatchPatterns
            .union(extensionContext.webExtension.optionalPermissionMatchPatterns)

        var tabScopedGrantedPatterns = Set<WKWebExtension.MatchPattern>()
        for pattern in declaredPatterns {
            if isGrantedPermissionStatus(extensionContext.permissionStatus(for: pattern)) {
                grantedPatterns.insert(pattern)
            } else if let tab,
                      isGrantedPermissionStatus(extensionContext.permissionStatus(for: pattern, in: tab)) {
                tabScopedGrantedPatterns.insert(pattern)
            }
        }

        if let matchingPattern = grantedPatterns.first(where: { $0.matches(url) }) {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: url)
            RuntimeDiagnostics.debug(category: "Extensions") {
                let host = url.host ?? url.scheme ?? "unknown"
                return "Auto-granted URL access for \(extensionContext.webExtension.displayName ?? extensionContext.uniqueIdentifier): host=\(host) via \(matchingPattern.string)"
            }
            return true
        }

        guard tabScopedGrantedPatterns.contains(where: { $0.matches(url) }) else {
            return false
        }
        return true
    }

    private func grantNativeMessagingPermissionIfDeclared(
        to extensionContext: WKWebExtensionContext,
        permissions: inout Set<WKWebExtension.Permission>,
        extensionId: String?,
        profileId: UUID?,
        manifest: [String: Any]
    ) {
        guard Self.manifestDeclaresNativeMessaging(manifest) else { return }

        permissions.insert(.nativeMessaging)
        extensionContext.setPermissionStatus(
            .grantedExplicitly,
            for: .nativeMessaging
        )
        SafariExtensionNativeMessagingPermissionDiagnostics.logGrant(
            extensionId: extensionId,
            profileId: profileId,
            manifestDeclaresNativeMessaging: true,
            permissionGranted: isGrantedPermissionStatus(
                extensionContext.permissionStatus(for: .nativeMessaging)
            )
        )
    }

    private func rawManifestSiteAccessMatchPatterns(
        from manifest: [String: Any]
    ) -> Set<WKWebExtension.MatchPattern> {
        let permissions = Self.manifestStringArray(from: manifest["permissions"])
        let optionalPermissions = Self.manifestStringArray(
            from: manifest["optional_permissions"]
        )
        let contentScriptMatches =
            (manifest["content_scripts"] as? [[String: Any]] ?? [])
                .flatMap { Self.manifestStringArray(from: $0["matches"]) }

        let patternStrings =
            Self.manifestStringArray(from: manifest["host_permissions"])
            + Self.manifestStringArray(from: manifest["optional_host_permissions"])
            + permissions.filter(Self.isManifestHostPermissionPattern)
            + optionalPermissions.filter(Self.isManifestHostPermissionPattern)
            + contentScriptMatches

        return Set(
            patternStrings.compactMap {
                try? WKWebExtension.MatchPattern(string: $0)
            }
        )
    }

    private func rawManifestExternalMessagingMatchPatterns(
        from manifest: [String: Any]
    ) -> Set<WKWebExtension.MatchPattern> {
        let patternStrings =
            (manifest["externally_connectable"] as? [String: Any])
                .map { Self.manifestStringArray(from: $0["matches"]) } ?? []

        return Set(
            patternStrings.compactMap {
                try? WKWebExtension.MatchPattern(string: $0)
            }
        )
    }

    private static func requiredManifestWebExtensionPermissions(
        from manifest: [String: Any]
    ) -> Set<WKWebExtension.Permission> {
        Set(
            manifestStringArray(from: manifest["permissions"])
                .filter { isManifestWebExtensionPermission($0) }
                .map { WKWebExtension.Permission(rawValue: $0) }
        )
    }

    nonisolated static func manifestDeclaresNativeMessaging(
        _ manifest: [String: Any]
    ) -> Bool {
        let permissions = manifestStringArray(from: manifest["permissions"])
        return permissions.contains("nativeMessaging")
    }

    nonisolated static func manifestDeclaresWebKitBrowserTarget(
        for manifest: [String: Any]
    ) -> Bool {
        guard let browserSpecificSettings = manifest["browser_specific_settings"] as? [String: Any] else {
            return false
        }

        return browserSpecificSettings["safari"] != nil
            || browserSpecificSettings["webkit"] != nil
            || browserSpecificSettings["WebKit"] != nil
    }

    nonisolated static func shouldDenyAutoGrantForWebKitRuntime(
        _ permission: WKWebExtension.Permission,
        manifest: [String: Any]
    ) -> Bool {
        guard manifestDeclaresWebKitBrowserTarget(for: manifest) else {
            return false
        }

        return permission.rawValue == "scripting"
    }

    nonisolated static func webKitRuntimeUnsupportedAPIs(
        for manifest: [String: Any]
    ) -> Set<String> {
        guard manifestDeclaresWebKitBrowserTarget(for: manifest) else {
            return []
        }

        return [
            "browser.contentScripts.register",
            "browser.scripting.executeScript",
            "browser.scripting.insertCSS",
            "browser.scripting.registerContentScripts",
            "browser.tabs.executeScript",
            "browser.tabs.insertCSS",
        ]
    }

    private nonisolated static func manifestStringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func isManifestWebExtensionPermission(
        _ value: String
    ) -> Bool {
        (try? WKWebExtension.MatchPattern(string: value)) == nil
    }

    private static func isManifestHostPermissionPattern(
        _ value: String
    ) -> Bool {
        value == "<all_urls>"
            || value.hasPrefix("http://")
            || value.hasPrefix("https://")
            || value.hasPrefix("*://")
    }

    private static func isAllHostsMatchPatternString(
        _ value: String
    ) -> Bool {
        guard let matchPattern = try? WKWebExtension.MatchPattern(string: value) else {
            return false
        }
        return matchPattern == WKWebExtension.MatchPattern.allHostsAndSchemes()
            || matchPattern == WKWebExtension.MatchPattern.allURLs()
    }
}
