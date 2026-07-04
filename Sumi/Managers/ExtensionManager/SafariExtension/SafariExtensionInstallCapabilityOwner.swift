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

        // Desired status per pattern: the profile default for every declared
        // pattern, overlaid by configured rules (a rule for the same pattern
        // wins; increasing specificity keeps the most specific rule last).
        var desiredStates: [WKWebExtension.MatchPattern: (
            access: SafariExtensionSiteAccessLevel,
            expiresAt: Date?
        )] = [:]
        for matchPattern in declaredPatterns {
            desiredStates[matchPattern] = (policy.defaultAccess, nil)
        }
        for rule in policy.rulesByIncreasingSpecificity {
            guard let matchPattern = Self.matchPattern(
                from: rule.matchPattern,
                purpose: "configuredRule"
            ) else { continue }
            desiredStates[matchPattern] = (rule.access, rule.expiresAt)
        }

        // Apply as a diff against the context's current grant/deny state.
        // Safari parity: permission state changes only when configuration
        // actually changed. Re-applying an unchanged policy (context load,
        // popup open, tab reconcile) must be a no-op — a remove-then-regrant
        // sweep fires permissions.onRemoved/onAdded storms into extension
        // workers, which e.g. Proton Pass turns into a cached
        // "permissions missing" state for its popup.
        let grantedPatterns = extensionContext.grantedPermissionMatchPatterns
        let deniedPatterns = extensionContext.deniedPermissionMatchPatterns
        for (matchPattern, desired) in desiredStates {
            switch desired.access {
            case .allow:
                if let currentExpiration = grantedPatterns[matchPattern],
                   Self.expirationDatesEquivalent(currentExpiration, desired.expiresAt) {
                    continue
                }
                if grantedPatterns[matchPattern] != nil {
                    // Same status with a different expiration: WebKit's grant
                    // is add-only and keeps the old expiration, so clear first.
                    extensionContext.setPermissionStatus(.unknown, for: matchPattern)
                }
                extensionContext.setPermissionStatus(
                    .grantedExplicitly,
                    for: matchPattern,
                    expirationDate: desired.expiresAt
                )
            case .deny:
                if let currentExpiration = deniedPatterns[matchPattern],
                   Self.expirationDatesEquivalent(currentExpiration, desired.expiresAt) {
                    continue
                }
                if deniedPatterns[matchPattern] != nil {
                    extensionContext.setPermissionStatus(.unknown, for: matchPattern)
                }
                extensionContext.setPermissionStatus(
                    .deniedExplicitly,
                    for: matchPattern,
                    expirationDate: desired.expiresAt
                )
            case .ask:
                if grantedPatterns[matchPattern] != nil
                    || deniedPatterns[matchPattern] != nil {
                    extensionContext.setPermissionStatus(.unknown, for: matchPattern)
                }
            }
        }
    }

    /// WebKit bridges a never-expiring grant as a far-future date; treat any
    /// far-future expiration as equivalent to "no expiration".
    private static func expirationDatesEquivalent(
        _ current: Date,
        _ desired: Date?
    ) -> Bool {
        let farFutureThreshold = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 20)
        guard let desired else {
            return current >= farFutureThreshold
        }
        if current >= farFutureThreshold {
            return false
        }
        return abs(current.timeIntervalSince(desired)) < 1
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
                Self.matchPattern(from: $0, purpose: "manifestSiteAccess")
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
                Self.matchPattern(from: $0, purpose: "externallyConnectable")
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

    /// WebKit's native `browser.scripting` implementation (executeScript with
    /// files / func+args / MAIN world, insertCSS) is proven working through
    /// Sumi's tab adapters by `SafariExtensionScriptingRuntimeTests`, so the
    /// `scripting` permission is granted like any other and only legacy APIs
    /// without a verified WebKit implementation stay marked unsupported.
    nonisolated static func webKitRuntimeUnsupportedAPIs(
        for manifest: [String: Any]
    ) -> Set<String> {
        guard manifestDeclaresWebKitBrowserTarget(for: manifest) else {
            return []
        }

        return [
            "browser.contentScripts.register",
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
        do {
            _ = try WKWebExtension.MatchPattern(string: value)
            return false
        } catch {
            return true
        }
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
        guard let matchPattern = Self.matchPattern(
            from: value,
            purpose: "allHostsRule"
        ) else { return false }
        return matchPattern == WKWebExtension.MatchPattern.allHostsAndSchemes()
            || matchPattern == WKWebExtension.MatchPattern.allURLs()
    }

    private static func matchPattern(
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
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func grantRequestedPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension,
        extensionId: String? = nil,
        profileId: UUID? = nil,
        manifest: [String: Any]
    ) {
        installCapabilityOwner.grantRequestedPermissions(
            to: extensionContext,
            webExtension: webExtension,
            extensionId: extensionId,
            profileId: profileId,
            manifest: manifest
        )
    }

    static func manifestDeclaresNativeMessaging(_ manifest: [String: Any]) -> Bool {
        SafariExtensionInstallCapabilityOwner.manifestDeclaresNativeMessaging(manifest)
    }

    static func webKitRuntimeUnsupportedAPIs(
        for manifest: [String: Any]
    ) -> Set<String> {
        SafariExtensionInstallCapabilityOwner.webKitRuntimeUnsupportedAPIs(
            for: manifest
        )
    }

    func grantRequestedMatchPatterns(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension
    ) {
        guard let extensionId = extensionID(for: extensionContext),
              let profileId = profileId(for: extensionContext)
        else { return }
        let manifest = loadedExtensionManifests[extensionId]
            ?? installedExtensions.first { $0.id == extensionId }?.manifest
        applyConfiguredSiteAccessPolicy(
            to: extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            webExtension: webExtension,
            manifest: manifest
        )
    }

    /// Grants temporary host access for the active tab when the manifest declares `activeTab`.
    func grantActiveTabURLAccess(
        for extensionContext: WKWebExtensionContext,
        tab: Tab,
        manifest: [String: Any]
    ) {
        installCapabilityOwner.grantActiveTabURLAccess(
            for: extensionContext,
            tab: tab,
            manifest: manifest,
            extensionId: extensionID(for: extensionContext),
            profileId: profileId(for: extensionContext)
        )
    }

    func isGrantedPermissionStatus(
        _ status: WKWebExtensionContext.PermissionStatus
    ) -> Bool {
        installCapabilityOwner.isGrantedPermissionStatus(status)
    }

    func effectivePermissionStatus(
        for permission: WKWebExtension.Permission,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        installCapabilityOwner.effectivePermissionStatus(
            for: permission,
            in: extensionContext,
            tab: tab
        )
    }

    func effectivePermissionStatus(
        for matchPattern: WKWebExtension.MatchPattern,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        installCapabilityOwner.effectivePermissionStatus(
            for: matchPattern,
            in: extensionContext,
            tab: tab
        )
    }

    func effectivePermissionStatus(
        for url: URL,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        installCapabilityOwner.effectivePermissionStatus(
            for: url,
            in: extensionContext,
            tab: tab
        )
    }

    func explicitlyGrantURLIfCoveredByGrantedMatchPattern(
        _ url: URL,
        in extensionContext: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)? = nil
    ) -> Bool {
        installCapabilityOwner.explicitlyGrantURLIfCoveredByGrantedMatchPattern(
            url,
            in: extensionContext,
            tab: tab
        )
    }
}
