import Foundation
import WebKit

/// Resolves and persists the page-access decision required by one action click.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPageAccessAuthorizer {
    struct Environment {
        let capabilities: SafariExtensionInstallCapabilityOwner
        let siteAccess: ExtensionSiteAccessPolicyCoordinator
        let decisions: ExtensionPermissionDecisionStore
        let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
        let extensionID: @MainActor (WKWebExtensionContext) -> String?
        let resolvedProfileID: @MainActor (Tab) -> UUID?
        let currentProfileID: @MainActor () -> UUID?
        let prompt: @MainActor (
            WKWebExtensionContext, [String], String, String
        ) async -> ExtensionManager.ExtensionPermissionPromptDecision
    }

    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    func authorize(
        context: WKWebExtensionContext,
        installedExtension: InstalledExtension,
        tab: Tab
    ) async -> Bool {
        let currentURL = tab.url
        guard Self.isWebURL(currentURL) else { return true }

        let adapter = environment.stableAdapter(tab)
        let manifest = installedExtension.manifest
        let permissions = Self.stringArray(from: manifest["permissions"])
        let optionalPermissions = Self.stringArray(from: manifest["optional_permissions"])
        if (permissions + optionalPermissions).contains("activeTab") {
            environment.capabilities.grantActiveTabURLAccess(
                for: context,
                tab: tab,
                manifest: manifest,
                extensionId: nil,
                profileId: nil
            )
            return true
        }

        let status = environment.capabilities.effectivePermissionStatus(
            for: currentURL,
            in: context,
            tab: adapter
        )
        if environment.capabilities.isGrantedPermissionStatus(status) {
            return true
        }
        if status == .deniedExplicitly {
            return false
        }
        if environment.capabilities.explicitlyGrantURLIfCoveredByGrantedMatchPattern(
            currentURL,
            in: context,
            tab: adapter
        ) {
            return true
        }

        let decisionProfileID = tab.profileId
            ?? environment.resolvedProfileID(tab)
            ?? environment.currentProfileID()
        if let extensionID = environment.extensionID(context),
           let decisionProfileID {
            switch environment.siteAccess.configuredSiteAccessLevel(
                for: currentURL,
                extensionId: extensionID,
                profileId: decisionProfileID
            ) {
            case .allow:
                environment.siteAccess.grantSiteAccess(
                    to: currentURL,
                    in: context,
                    extensionId: extensionID,
                    profileId: decisionProfileID,
                    expirationDate: nil,
                    persistPolicy: false
                )
                return true
            case .deny:
                environment.siteAccess.denySiteAccess(
                    to: currentURL,
                    in: context,
                    extensionId: extensionID,
                    profileId: decisionProfileID,
                    persistPolicy: false
                )
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: false,
                    extensionId: installedExtension.id,
                    reason: "actionClickSiteAccessDenied"
                )
                return false
            case .ask:
                break
            }
        }

        guard Self.requiresCurrentPagePermission(
            installedExtension,
            currentURL: currentURL
        ) else {
            return true
        }

        let host = currentURL.host ?? currentURL.scheme ?? "this site"
        let pattern = environment.siteAccess.hostMatchPatternString(for: currentURL)
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

        switch decision {
        case .allow(let expirationDate):
            environment.siteAccess.grantSiteAccess(
                to: currentURL,
                in: context,
                extensionId: installedExtension.id,
                profileId: decisionProfileID,
                expirationDate: expirationDate,
                persistPolicy: true
            )
            if let pattern, let decisionProfileID {
                environment.decisions.persistExtensionPermissionDecision(
                    extensionId: installedExtension.id,
                    profileId: decisionProfileID,
                    targetKind: .matchPattern,
                    target: pattern,
                    state: .allowed,
                    expiresAt: expirationDate
                )
            }
            SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                granted: true,
                extensionId: installedExtension.id,
                reason: "actionClickPromptAllowed"
            )
            return true
        case .deny:
            environment.siteAccess.denySiteAccess(
                to: currentURL,
                in: context,
                extensionId: installedExtension.id,
                profileId: decisionProfileID,
                persistPolicy: true
            )
            if let pattern, let decisionProfileID {
                environment.decisions.persistExtensionPermissionDecision(
                    extensionId: installedExtension.id,
                    profileId: decisionProfileID,
                    targetKind: .matchPattern,
                    target: pattern,
                    state: .denied,
                    expiresAt: nil
                )
            }
            SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                granted: false,
                extensionId: installedExtension.id,
                reason: "actionClickPromptDenied"
            )
            return false
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
            siteAccess: manager.runtimeBundle.siteAccessPolicyCoordinator,
            decisions: manager.permissionDecisionStore,
            stableAdapter: { [weak manager] in
                manager?.adapterResolutionOwner.stableAdapter(for: $0)
            },
            extensionID: { [weak manager] in
                manager?.profileRuntime.extensionId(for: $0)
            },
            resolvedProfileID: { [weak manager] in manager?.resolvedProfileId(for: $0) },
            currentProfileID: { [weak manager] in manager?.profileRuntime.currentProfileId },
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
