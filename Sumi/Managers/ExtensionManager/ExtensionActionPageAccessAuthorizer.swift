import Foundation
import WebKit

/// Terminal state of one action click's page-access authorization.
@available(macOS 15.5, *)
enum ExtensionActionPageAccessOutcome {
    case authorized
    case denied
    /// The invocation authority was superseded; nothing further was mutated,
    /// persisted or recorded, and the action must not run.
    case stale
}

/// Resolves and persists the page-access decision required by one action
/// click. It accepts only typed invocation evidence: identity comes from the
/// evidence, effects act only on the captured page URL, and every WebKit
/// mutation, durable persistence step and diagnostic is separated by an
/// exact admission barrier so a stale prompt settles without effects.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPageAccessAuthorizer {
    struct Environment {
        let capabilities: SafariExtensionInstallCapabilityOwner
        /// Deferred so constructing the invocation boundary for a rejected
        /// click cannot materialize the runtime bundle's lazy systems.
        let siteAccess: @MainActor () -> ExtensionSiteAccessPolicyCoordinator?
        let decisions: ExtensionPermissionDecisionStore
        let prompt: @MainActor (
            WKWebExtensionContext, [String], String, String
        ) async -> ExtensionManager.ExtensionPermissionPromptDecision
    }

    private let environment: Environment
    private let admission: ExtensionActionInvocationAdmission

    init(
        environment: Environment,
        admission: ExtensionActionInvocationAdmission
    ) {
        self.environment = environment
        self.admission = admission
    }

    /// Applies the configured host policy using only captured identity. This
    /// replaces the manager facade that recomputed extension/profile identity
    /// from mutable context state during the invocation.
    func applyConfiguredPolicy(
        evidence: ExtensionActionInvocationEvidence
    ) -> Bool {
        guard admission.isCurrent(evidence),
              let siteAccess = environment.siteAccess(),
              admission.isCurrent(evidence)
        else {
            return false
        }
        siteAccess.applyConfiguredSiteAccessPolicy(
            to: evidence.context,
            extensionId: evidence.extensionID,
            profileId: evidence.profileID,
            webExtension: evidence.context.webExtension,
            manifest: evidence.installedRecord.manifest
        )
        return admission.isCurrent(evidence)
    }

    func authorize(
        evidence: ExtensionActionInvocationEvidence
    ) async -> ExtensionActionPageAccessOutcome {
        guard let page = evidence.page else { return .authorized }
        let pageURL = page.pageURL
        guard Self.isWebURL(pageURL) else { return .authorized }

        let context = evidence.context
        let manifest = evidence.installedRecord.manifest
        let permissions = Self.stringArray(from: manifest["permissions"])
        let optionalPermissions = Self.stringArray(from: manifest["optional_permissions"])
        if (permissions + optionalPermissions).contains("activeTab") {
            // grantActiveTabURLAccess reads the live Tab URL; it may only run
            // while that URL is still exactly the captured, authorized page.
            guard admission.isCurrent(evidence),
                  page.tab.url == pageURL
            else { return .stale }
            environment.capabilities.grantActiveTabURLAccess(
                for: context,
                tab: page.tab,
                manifest: manifest,
                extensionId: evidence.extensionID,
                profileId: evidence.profileID
            )
            return .authorized
        }

        let status = environment.capabilities.effectivePermissionStatus(
            for: pageURL,
            in: context,
            tab: evidence.adapter
        )
        if environment.capabilities.isGrantedPermissionStatus(status) {
            return .authorized
        }
        if status == .deniedExplicitly {
            return .denied
        }
        guard admission.isCurrent(evidence) else { return .stale }
        if environment.capabilities.explicitlyGrantURLIfCoveredByGrantedMatchPattern(
            pageURL,
            in: context,
            tab: evidence.adapter
        ) {
            return .authorized
        }

        guard let siteAccess = environment.siteAccess() else { return .stale }
        switch siteAccess.configuredSiteAccessLevel(
            for: pageURL,
            extensionId: evidence.extensionID,
            profileId: evidence.profileID
        ) {
        case .allow:
            guard admission.isCurrent(evidence) else { return .stale }
            siteAccess.grantSiteAccess(
                to: pageURL,
                in: context,
                extensionId: evidence.extensionID,
                profileId: evidence.profileID,
                expirationDate: nil,
                persistPolicy: false
            )
            return .authorized
        case .deny:
            guard admission.isCurrent(evidence) else { return .stale }
            siteAccess.denySiteAccess(
                to: pageURL,
                in: context,
                extensionId: evidence.extensionID,
                profileId: evidence.profileID,
                persistPolicy: false
            )
            guard admission.isCurrent(evidence) else { return .stale }
            SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                granted: false,
                extensionId: evidence.extensionID,
                reason: "actionClickSiteAccessDenied"
            )
            return .denied
        case .ask:
            break
        }

        guard Self.requiresCurrentPagePermission(
            evidence.installedRecord,
            currentURL: pageURL
        ) else {
            return .authorized
        }

        let host = pageURL.host ?? pageURL.scheme ?? "this site"
        let pattern = siteAccess.hostMatchPatternString(for: pageURL)
        let dedupeTargets = pattern.map { [$0] } ?? [host]
        let dedupeKey = environment.decisions.permissionPromptDedupeKey(
            extensionContext: context,
            targets: dedupeTargets
        )
        let decision = await environment.prompt(
            context,
            [host],
            "actionClickCurrentPageAccess",
            dedupeKey
        )

        // The prompt awaited; nothing below may act on superseded authority.
        switch decision {
        case .allow(let expirationDate):
            guard admission.isCurrent(evidence) else { return .stale }
            siteAccess.grantSiteAccess(
                to: pageURL,
                in: context,
                extensionId: evidence.extensionID,
                profileId: evidence.profileID,
                expirationDate: expirationDate,
                persistPolicy: false
            )
            if let pattern {
                guard admission.isCurrent(evidence) else { return .stale }
                siteAccess.setConfiguredSiteAccess(
                    .allow,
                    extensionId: evidence.extensionID,
                    profileId: evidence.profileID,
                    matchPatternString: pattern,
                    expiresAt: expirationDate
                )
                guard admission.isCurrent(evidence) else { return .stale }
                environment.decisions.persistExtensionPermissionDecision(
                    extensionId: evidence.extensionID,
                    profileId: evidence.profileID,
                    targetKind: .matchPattern,
                    target: pattern,
                    state: .allowed,
                    expiresAt: expirationDate
                )
            }
            guard admission.isCurrent(evidence) else { return .stale }
            SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                granted: true,
                extensionId: evidence.extensionID,
                reason: "actionClickPromptAllowed"
            )
            return .authorized
        case .deny:
            guard admission.isCurrent(evidence) else { return .stale }
            siteAccess.denySiteAccess(
                to: pageURL,
                in: context,
                extensionId: evidence.extensionID,
                profileId: evidence.profileID,
                persistPolicy: false
            )
            if let pattern {
                guard admission.isCurrent(evidence) else { return .stale }
                siteAccess.setConfiguredSiteAccess(
                    .deny,
                    extensionId: evidence.extensionID,
                    profileId: evidence.profileID,
                    matchPatternString: pattern,
                    expiresAt: nil
                )
                guard admission.isCurrent(evidence) else { return .stale }
                environment.decisions.persistExtensionPermissionDecision(
                    extensionId: evidence.extensionID,
                    profileId: evidence.profileID,
                    targetKind: .matchPattern,
                    target: pattern,
                    state: .denied,
                    expiresAt: nil
                )
            }
            guard admission.isCurrent(evidence) else { return .stale }
            SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                granted: false,
                extensionId: evidence.extensionID,
                reason: "actionClickPromptDenied"
            )
            return .denied
        }
    }

    private static func requiresCurrentPagePermission(
        _ extensionRecord: InstalledExtension,
        currentURL: URL
    ) -> Bool {
        guard isWebURL(currentURL) else { return false }
        let manifest = extensionRecord.manifest
        let permissions = stringArray(from: manifest["permissions"])
        let optionalPermissions = stringArray(from: manifest["optional_permissions"])
        if (permissions + optionalPermissions).contains("activeTab") {
            return true
        }
        let contentScriptMatches =
            (manifest["content_scripts"] as? [[String: Any]] ?? [])
            .flatMap { stringArray(from: $0["matches"]) }
        let hostPatterns = stringArray(from: manifest["host_permissions"])
            + permissions.filter(isHostPermissionPattern)
            + contentScriptMatches
        return hostPatterns.contains {
            ExtensionUtils.hostPatternMatchesURL($0, url: currentURL)
        }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    private static func isHostPermissionPattern(_ value: String) -> Bool {
        value == "<all_urls>"
            || value.hasPrefix("http://")
            || value.hasPrefix("https://")
            || value.hasPrefix("*://")
    }

    private static func stringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }
}

@available(macOS 15.5, *)
extension ExtensionActionPageAccessAuthorizer.Environment {
    @MainActor
    static func makeLive(manager: ExtensionManager) -> Self {
        Self(
            capabilities: manager.installCapabilityOwner,
            siteAccess: { [weak manager] in
                manager?.runtimeBundle.siteAccessPolicyCoordinator
            },
            decisions: manager.permissionDecisionStore,
            prompt: { [weak manager] context, targets, reason, dedupeKey in
                await manager?.promptForExtensionPermissionDecision(
                    extensionContext: context,
                    targets: targets,
                    reason: reason,
                    dedupeKey: dedupeKey
                ) ?? .deny
            }
        )
    }
}
