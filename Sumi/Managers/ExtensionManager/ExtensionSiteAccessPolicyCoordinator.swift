import Foundation
import WebKit

/// Owns per-profile site access policy for extensions: reads and updates the
/// policy store, applies policy to loaded contexts, and grants or denies
/// per-site access with optional persistence.
@available(macOS 15.5, *)
@MainActor
final class ExtensionSiteAccessPolicyCoordinator {
    private let siteAccessPolicyStore: SafariExtensionSiteAccessPolicyStore
    private let policyApplicator: ExtensionSiteAccessPolicyApplicator
    private let installedExtensions: @MainActor () -> [InstalledExtension]
    private let loadedExtensionManifest:
        @MainActor (String) -> [String: Any]?
    private let getExtensionContext: @MainActor (String, UUID) -> WKWebExtensionContext?
    private let reconcileOpenTabsAfterExtensionContextLoad: @MainActor (String, UUID) -> Void
    private let postSiteAccessPoliciesDidChange: @MainActor () -> Void

    init(
        siteAccessPolicyStore: SafariExtensionSiteAccessPolicyStore,
        policyApplicator: ExtensionSiteAccessPolicyApplicator = .init(),
        installedExtensions: @escaping @MainActor () -> [InstalledExtension],
        loadedExtensionManifest:
            @escaping @MainActor (String) -> [String: Any]?,
        getExtensionContext: @escaping @MainActor (String, UUID) -> WKWebExtensionContext?,
        reconcileOpenTabsAfterExtensionContextLoad: @escaping @MainActor (String, UUID) -> Void,
        postSiteAccessPoliciesDidChange: @escaping @MainActor () -> Void
    ) {
        self.siteAccessPolicyStore = siteAccessPolicyStore
        self.policyApplicator = policyApplicator
        self.installedExtensions = installedExtensions
        self.loadedExtensionManifest = loadedExtensionManifest
        self.getExtensionContext = getExtensionContext
        self.reconcileOpenTabsAfterExtensionContextLoad = reconcileOpenTabsAfterExtensionContextLoad
        self.postSiteAccessPoliciesDidChange = postSiteAccessPoliciesDidChange
    }

    func siteAccessPolicy(
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessPolicy {
        let result = siteAccessPolicyStore.policy(
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
        let result = siteAccessPolicyStore.snapshot(
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
            extensionIds: installedExtensions().map(\.id),
            profileId: profileId
        )
    }

    @discardableResult
    func seedSafariAppExtensionDefaultAccessIfNeeded(
        extensionId: String,
        profileId: UUID
    ) -> SafariExtensionSiteAccessPolicy {
        let result = siteAccessPolicyStore
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
        let policyResult = siteAccessPolicyStore.policy(
            extensionId: extensionId,
            profileId: profileId
        )
        policyApplicator.apply(
            to: extensionContext,
            webExtension: webExtension,
            input: ExtensionSiteAccessPolicyApplicator.Input(
                extensionID: extensionId,
                profileID: profileId,
                policy: policyResult.policy,
                installedExtension: installedExtensions()
                    .first { $0.id == extensionId },
                manifest: manifest
            )
        )
        // Policy normalization may publish synchronously and replace the
        // caller's context binding. Mutate the captured context first; the
        // caller can then revalidate authority after this notification.
        notifySiteAccessPoliciesDidChangeIfNeeded(
            policyResult.didPersistChanges
        )
    }

    func declaredSiteAccessMatchPatterns(
        for webExtension: WKWebExtension,
        manifest: [String: Any]? = nil
    ) -> Set<WKWebExtension.MatchPattern> {
        policyApplicator.declaredMatchPatterns(
            for: webExtension,
            manifest: manifest
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
        let didPersist = siteAccessPolicyStore.updatePolicy(
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
        guard let extensionContext = getExtensionContext(
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
            manifest: loadedExtensionManifest(extensionId)
                ?? installedExtensions()
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
        reconcileOpenTabsAfterExtensionContextLoad(
            "ExtensionManager.siteAccessPolicyChanged",
            profileId
        )
    }

    private func notifySiteAccessPoliciesDidChangeIfNeeded(_ shouldNotify: Bool) {
        guard shouldNotify else { return }
        postSiteAccessPoliciesDidChange()
    }
}
