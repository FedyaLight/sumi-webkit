import Foundation
import WebKit

/// Owns per-profile site access policy for extensions: reads and updates the
/// policy store, applies policy to loaded contexts, and grants or denies
/// per-site access with optional persistence.
@available(macOS 15.5, *)
@MainActor
final class ExtensionSiteAccessPolicyCoordinator {
    struct Dependencies {
        let siteAccessPolicyStore: SafariExtensionSiteAccessPolicyStore
        let installCapabilityOwner: SafariExtensionInstallCapabilityOwner
        let installedExtensions: @MainActor () -> [InstalledExtension]
        let loadedExtensionManifests: @MainActor () -> [String: [String: Any]]
        let getExtensionContext: @MainActor (String, UUID) -> WKWebExtensionContext?
        let reconcileOpenTabsAfterExtensionContextLoad: @MainActor (String, UUID) -> Void
        let postSiteAccessPoliciesDidChange: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func siteAccessPolicy(
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessPolicy {
        let result = dependencies.siteAccessPolicyStore.policy(
            extensionId: extensionId,
            profileId: profileId
        )
        notifySiteAccessPoliciesDidChangeIfNeeded(result.didPersistChanges)
        return result.policy
    }

    func siteAccessPolicySnapshot(
        extensionIds: [String],
        profileId: UUID
    ) -> [String: SafariExtensionSiteAccessPolicy] {
        let result = dependencies.siteAccessPolicyStore.snapshot(
            extensionIds: extensionIds,
            profileId: profileId
        )
        notifySiteAccessPoliciesDidChangeIfNeeded(result.didPersistChanges)
        return result.policiesByExtensionId
    }

    func siteAccessPolicySnapshot(
        profileId: UUID
    ) -> [String: SafariExtensionSiteAccessPolicy] {
        siteAccessPolicySnapshot(
            extensionIds: dependencies.installedExtensions().map(\.id),
            profileId: profileId
        )
    }

    @discardableResult
    func seedSafariAppExtensionDefaultAccessIfNeeded(
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessPolicy {
        let result = dependencies.siteAccessPolicyStore
            .seedSafariAppExtensionDefaultAccessIfNeeded(
                extensionId: extensionId,
                profileId: profileId
            )
        notifySiteAccessPoliciesDidChangeIfNeeded(result.didPersistChanges)
        return result.policy
    }

    func setDefaultSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID
    ) {
        updateSiteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ) { policy in
            policy.defaultAccess = access
            policy.defaultAccessConfiguredByUser = true
            policy.updatedAt = Date()
        }
        applySiteAccessPolicyToLoadedContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func setPrivateBrowsingAccess(
        _ isAllowed: Bool,
        extensionId: String,
        profileId: UUID
    ) {
        updateSiteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ) { policy in
            policy.privateAccessAllowed = isAllowed
            policy.updatedAt = Date()
        }
        applySiteAccessPolicyToLoadedContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func setConfiguredSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID,
        matchPatternString: String,
        expiresAt: Date? = nil
    ) {
        let normalizedPattern =
            SafariExtensionSiteAccessPolicy.normalizedMatchPatternString(
                matchPatternString
            )
        guard normalizedPattern.isEmpty == false else { return }

        updateSiteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ) { policy in
            policy.siteRules.removeAll { $0.matchPattern == normalizedPattern }
            policy.siteRules.append(
                SafariExtensionSiteAccessRule(
                    matchPattern: normalizedPattern,
                    access: access,
                    expiresAt: expiresAt,
                    updatedAt: Date()
                )
            )
            policy.siteRules = SafariExtensionSiteAccessPolicy
                .normalizedRules(policy.siteRules)
            policy.updatedAt = Date()
        }
        applySiteAccessPolicyToLoadedContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func setCurrentSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID,
        url: URL
    ) {
        guard let patternString = hostMatchPatternString(for: url) else { return }
        setConfiguredSiteAccess(
            access,
            extensionId: extensionId,
            profileId: profileId,
            matchPatternString: patternString
        )
    }

    func configuredSiteAccessLevel(
        for url: URL,
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessLevel {
        siteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ).accessLevel(for: url)
    }

    func configuredSiteAccessLevel(
        for matchPattern: WKWebExtension.MatchPattern,
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessLevel {
        siteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        ).accessLevel(for: matchPattern)
    }

    func applyConfiguredSiteAccessPolicy(
        to extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        webExtension: WKWebExtension,
        manifest: [String: Any]? = nil
    ) {
        dependencies.installCapabilityOwner.applyConfiguredSiteAccessPolicy(
            to: extensionContext,
            webExtension: webExtension,
            input: SafariExtensionInstallCapabilityOwner.SiteAccessApplicationInput(
                extensionId: extensionId,
                profileId: profileId,
                policy: siteAccessPolicy(
                    extensionId: extensionId,
                    profileId: profileId
                ),
                installedExtension: dependencies.installedExtensions()
                    .first { $0.id == extensionId },
                manifest: manifest
            )
        )
    }

    func hostMatchPatternString(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              host.isEmpty == false
        else {
            return nil
        }
        return "\(scheme)://\(host)/*"
    }

    func grantSiteAccess(
        to url: URL,
        in extensionContext: WKWebExtensionContext,
        extensionId: String?,
        profileId: UUID?,
        expirationDate: Date? = nil,
        persistPolicy: Bool = true
    ) {
        if let patternString = hostMatchPatternString(for: url),
           let matchPattern = SafariExtensionMatchPatternDiagnostics.make(
               patternString,
               purpose: "grantSiteAccess.hostPattern"
           ) {
            extensionContext.setPermissionStatus(
                .grantedExplicitly,
                for: matchPattern,
                expirationDate: expirationDate
            )
            if persistPolicy, let extensionId, let profileId {
                setConfiguredSiteAccess(
                    .allow,
                    extensionId: extensionId,
                    profileId: profileId,
                    matchPatternString: patternString,
                    expiresAt: expirationDate
                )
            }
        }
        extensionContext.setPermissionStatus(
            .grantedExplicitly,
            for: url,
            expirationDate: expirationDate
        )
    }

    func denySiteAccess(
        to url: URL,
        in extensionContext: WKWebExtensionContext,
        extensionId: String?,
        profileId: UUID?,
        persistPolicy: Bool = true
    ) {
        if let patternString = hostMatchPatternString(for: url),
           let matchPattern = SafariExtensionMatchPatternDiagnostics.make(
               patternString,
               purpose: "denySiteAccess.hostPattern"
           ) {
            extensionContext.setPermissionStatus(
                .deniedExplicitly,
                for: matchPattern,
                expirationDate: nil
            )
            if persistPolicy, let extensionId, let profileId {
                setConfiguredSiteAccess(
                    .deny,
                    extensionId: extensionId,
                    profileId: profileId,
                    matchPatternString: patternString,
                    expiresAt: nil
                )
            }
        }
        extensionContext.setPermissionStatus(
            .deniedExplicitly,
            for: url,
            expirationDate: nil
        )
    }

    private func updateSiteAccessPolicy(
        extensionId: String,
        profileId: UUID,
        update: (inout SafariExtensionSiteAccessPolicy) -> Void
    ) {
        let didPersist = dependencies.siteAccessPolicyStore.updatePolicy(
            extensionId: extensionId,
            profileId: profileId,
            update: update
        )
        notifySiteAccessPoliciesDidChangeIfNeeded(didPersist)
    }

    private func applySiteAccessPolicyToLoadedContext(
        extensionId: String,
        profileId: UUID
    ) {
        guard let extensionContext = dependencies.getExtensionContext(
            extensionId,
            profileId
        ) else {
            return
        }
        applyConfiguredSiteAccessPolicy(
            to: extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            webExtension: extensionContext.webExtension,
            manifest: dependencies.loadedExtensionManifests()[extensionId]
                ?? dependencies.installedExtensions()
                .first { $0.id == extensionId }?.manifest
        )
        SafariExtensionPermissionLifecycleDiagnostics.logReloadRebuild(
            SafariExtensionReloadRebuildSnapshot(
                triggerReason: "ExtensionManager.siteAccessPolicyChanged",
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(profileId),
                tabBucket: nil,
                host: nil,
                userActionCaused: false,
                action: .rebindOnly
            )
        )
        dependencies.reconcileOpenTabsAfterExtensionContextLoad(
            "ExtensionManager.siteAccessPolicyChanged",
            profileId
        )
    }

    private func notifySiteAccessPoliciesDidChangeIfNeeded(_ shouldNotify: Bool) {
        guard shouldNotify else { return }
        dependencies.postSiteAccessPoliciesDidChange()
    }
}

@available(macOS 15.5, *)
extension ExtensionSiteAccessPolicyCoordinator.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            siteAccessPolicyStore: manager.siteAccessPolicyStore,
            installCapabilityOwner: manager.installCapabilityOwner,
            installedExtensions: { [weak manager] in manager?.installedExtensions ?? [] },
            loadedExtensionManifests: { [weak manager] in
                manager?.loadedExtensionManifests ?? [:]
            },
            getExtensionContext: { [weak manager] extensionId, profileId in
                manager?.getExtensionContext(for: extensionId, profileId: profileId)
            },
            reconcileOpenTabsAfterExtensionContextLoad: { [weak manager] reason, profileId in
                manager?.reconcileOpenTabsAfterExtensionContextLoad(
                    reason: reason,
                    profileId: profileId
                )
            },
            postSiteAccessPoliciesDidChange: { [weak manager] in
                guard let manager else { return }
                NotificationCenter.default.post(
                    name: .sumiExtensionSiteAccessPoliciesDidChange,
                    object: manager
                )
            }
        )
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func siteAccessPolicy(
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessPolicy {
        siteAccessPolicyCoordinator.siteAccessPolicy(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func siteAccessPolicySnapshot(
        extensionIds: [String],
        profileId: UUID
    ) -> [String: SafariExtensionSiteAccessPolicy] {
        siteAccessPolicyCoordinator.siteAccessPolicySnapshot(
            extensionIds: extensionIds,
            profileId: profileId
        )
    }

    func siteAccessPolicySnapshot(
        profileId: UUID
    ) -> [String: SafariExtensionSiteAccessPolicy] {
        siteAccessPolicyCoordinator.siteAccessPolicySnapshot(profileId: profileId)
    }

    func setDefaultSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID
    ) {
        siteAccessPolicyCoordinator.setDefaultSiteAccess(
            access,
            extensionId: extensionId,
            profileId: profileId
        )
    }

    @discardableResult
    func seedSafariAppExtensionDefaultAccessIfNeeded(
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessPolicy {
        siteAccessPolicyCoordinator.seedSafariAppExtensionDefaultAccessIfNeeded(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func setPrivateBrowsingAccess(
        _ isAllowed: Bool,
        extensionId: String,
        profileId: UUID
    ) {
        siteAccessPolicyCoordinator.setPrivateBrowsingAccess(
            isAllowed,
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func setConfiguredSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID,
        matchPatternString: String,
        expiresAt: Date? = nil
    ) {
        siteAccessPolicyCoordinator.setConfiguredSiteAccess(
            access,
            extensionId: extensionId,
            profileId: profileId,
            matchPatternString: matchPatternString,
            expiresAt: expiresAt
        )
    }

    func setCurrentSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID,
        url: URL
    ) {
        siteAccessPolicyCoordinator.setCurrentSiteAccess(
            access,
            extensionId: extensionId,
            profileId: profileId,
            url: url
        )
    }

    func configuredSiteAccessLevel(
        for url: URL,
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessLevel {
        siteAccessPolicyCoordinator.configuredSiteAccessLevel(
            for: url,
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func configuredSiteAccessLevel(
        for matchPattern: WKWebExtension.MatchPattern,
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessLevel {
        siteAccessPolicyCoordinator.configuredSiteAccessLevel(
            for: matchPattern,
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func applyConfiguredSiteAccessPolicy(
        to extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        webExtension: WKWebExtension,
        manifest: [String: Any]? = nil
    ) {
        siteAccessPolicyCoordinator.applyConfiguredSiteAccessPolicy(
            to: extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            webExtension: webExtension,
            manifest: manifest
        )
    }

    func declaredSiteAccessMatchPatterns(
        for webExtension: WKWebExtension,
        manifest: [String: Any]? = nil
    ) -> Set<WKWebExtension.MatchPattern> {
        installCapabilityOwner.declaredSiteAccessMatchPatterns(
            for: webExtension,
            manifest: manifest
        )
    }

    func hostMatchPatternString(for url: URL) -> String? {
        siteAccessPolicyCoordinator.hostMatchPatternString(for: url)
    }

    func grantSiteAccess(
        to url: URL,
        in extensionContext: WKWebExtensionContext,
        extensionId: String?,
        profileId: UUID?,
        expirationDate: Date? = nil,
        persistPolicy: Bool = true
    ) {
        siteAccessPolicyCoordinator.grantSiteAccess(
            to: url,
            in: extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            expirationDate: expirationDate,
            persistPolicy: persistPolicy
        )
    }

    func denySiteAccess(
        to url: URL,
        in extensionContext: WKWebExtensionContext,
        extensionId: String?,
        profileId: UUID?,
        persistPolicy: Bool = true
    ) {
        siteAccessPolicyCoordinator.denySiteAccess(
            to: url,
            in: extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            persistPolicy: persistPolicy
        )
    }
}
