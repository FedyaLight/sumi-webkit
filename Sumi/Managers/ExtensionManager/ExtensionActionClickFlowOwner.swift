//
//  ExtensionActionClickFlowOwner.swift
//  Sumi
//
//  Owns the URL-hub extension action click flow: preflight checks, context
//  loading, page access grants, and action invocation.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionClickFlowOwner {
    struct Dependencies {
        let actionPopupAnchorStore: ExtensionActionPopupAnchorStore
        let installedRecordsOwner: ExtensionInstalledRecordsOwner
        let runtimeAccess: ExtensionFlowOwnerRuntimeAccess
        let actionPopupAnchorResolutionOwner: ExtensionActionPopupAnchorResolutionOwner
        let runtimeLifecycleOwner: ExtensionRuntimeLifecycleOwner
        let contextResidencyOwner: ExtensionContextResidencyOwner
        let actionPopupFailureDiagnosticsOwner: ExtensionActionPopupFailureDiagnosticsOwner
        let installCapabilityOwner: SafariExtensionInstallCapabilityOwner
        let siteAccessPolicyCoordinator: ExtensionSiteAccessPolicyCoordinator
        let permissionDecisionStoreOwner: ExtensionPermissionDecisionStoreOwner
        let actionSurfacePublicationOwner: ExtensionActionSurfacePublicationOwner
        let runtimeDiagnosticsOwner: ExtensionRuntimeDiagnosticsOwner
        // Browser/Tab domain seam: these four cross into BrowserManager/TabManager
        // territory (window/tab resolution, runtime tab registration, WebKit tab
        // adapter identity). Routing them through a stored ExtensionManager owner
        // would still need the same browser-side lookups, so they stay closures
        // rather than inverting the extension → browser layering.
        let resolvedProfileIdForTab: @MainActor (Tab) -> UUID?
        let activeExtensionWindowId: @MainActor () -> UUID?
        let registerTabWithExtensionRuntime: @MainActor (Tab, String) -> Void
        let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
        // Real manager-level orchestration (context/profile resolution from a
        // WKWebExtensionContext, DEBUG test-hook interception, dedupe-key
        // defaulting) that no single sibling owner can absorb without manager
        // access itself.
        let grantRequestedMatchPatterns: @MainActor (WKWebExtensionContext, WKWebExtension) -> Void
        let promptForExtensionPermissionDecision:
            @MainActor (WKWebExtensionContext, [String], String, String) async -> ExtensionManager.ExtensionPermissionPromptDecision
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Sibling-owner call shims
    //
    // Translate the pre-refactor closure call shape onto the owner
    // references now held in `Dependencies`.

    private func installedExtensions() -> [InstalledExtension] {
        dependencies.installedRecordsOwner.records
    }

    private func runtimeState() -> ExtensionManager.ExtensionRuntimeState {
        dependencies.runtimeAccess.runtimeSessionOwner.runtimeState
    }

    private func currentProfileId() -> UUID? {
        dependencies.runtimeAccess.profileRuntimeOwner.currentProfileId
    }

    private func fallbackProfileId() -> UUID? {
        dependencies.runtimeAccess.fallbackProfileId()
    }

    private func getExtensionContext(_ extensionId: String, _ profileId: UUID?) -> WKWebExtensionContext? {
        dependencies.runtimeAccess.getExtensionContext(extensionId, profileId)
    }

    private func loadedContextCount(_ profileId: UUID) -> Int {
        dependencies.runtimeAccess.profileRuntimeOwner.contexts(for: profileId).count
    }

    private func captureActionPopupAnchor(_ extensionId: String, _ windowId: UUID, _ profileId: UUID?) {
        _ = dependencies.actionPopupAnchorResolutionOwner.captureActionPopupAnchor(
            extensionId: extensionId,
            windowId: windowId,
            profileId: profileId
        )
    }

    private func switchProfile(_ profileId: UUID) {
        dependencies.runtimeLifecycleOwner.switchProfile(profileId: profileId)
    }

    private func ensureExtensionController(_ profileId: UUID) {
        dependencies.runtimeAccess.ensureExtensionController(profileId)
    }

    private func ensureExtensionLoaded(
        _ extensionId: String,
        _ profileId: UUID
    ) async throws -> WKWebExtensionContext? {
        try await dependencies.contextResidencyOwner.ensureExtensionLoaded(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    private func classifyFailure(
        _ extensionId: String,
        _ profileId: UUID,
        _ installedExtension: InstalledExtension?
    ) -> ExtensionActionPopupRuntimeFailureBucket {
        dependencies.actionPopupFailureDiagnosticsOwner.classifyActionPopupRuntimeFailure(
            extensionId: extensionId,
            profileId: profileId,
            installedExtension: installedExtension
        )
    }

    private func diagnosticLines(
        _ extensionId: String,
        _ profileId: UUID,
        _ installedExtension: InstalledExtension,
        _ failureBucket: ExtensionActionPopupRuntimeFailureBucket,
        _ lastLoadError: Error?
    ) -> [String] {
        dependencies.actionPopupFailureDiagnosticsOwner.actionPopupRuntimeDiagnosticLines(
            extensionId: extensionId,
            profileId: profileId,
            installedExtension: installedExtension,
            failureBucket: failureBucket,
            lastLoadError: lastLoadError
        )
    }

    private func lastExtensionLoadError(_ extensionId: String, _ profileId: UUID) -> Error? {
        dependencies.runtimeAccess.lastExtensionLoadError(extensionId, profileId)
    }

    private func grantRequestedPermissions(
        _ context: WKWebExtensionContext,
        _ webExtension: WKWebExtension,
        _ manifest: [String: Any]
    ) {
        dependencies.installCapabilityOwner.grantRequestedPermissions(
            to: context,
            webExtension: webExtension,
            manifest: manifest
        )
    }

    private func grantActiveTabURLAccess(
        _ context: WKWebExtensionContext,
        _ tab: Tab,
        _ manifest: [String: Any]
    ) {
        dependencies.installCapabilityOwner.grantActiveTabURLAccess(
            for: context,
            tab: tab,
            manifest: manifest,
            extensionId: nil,
            profileId: nil
        )
    }

    private func effectivePermissionStatus(
        _ url: URL,
        _ context: WKWebExtensionContext,
        _ adapter: ExtensionTabAdapter?
    ) -> WKWebExtensionContext.PermissionStatus {
        dependencies.installCapabilityOwner.effectivePermissionStatus(for: url, in: context, tab: adapter)
    }

    private func isGrantedPermissionStatus(_ status: WKWebExtensionContext.PermissionStatus) -> Bool {
        dependencies.installCapabilityOwner.isGrantedPermissionStatus(status)
    }

    private func explicitlyGrantURLIfCoveredByGrantedMatchPattern(
        _ url: URL,
        _ context: WKWebExtensionContext,
        _ adapter: ExtensionTabAdapter?
    ) -> Bool {
        dependencies.installCapabilityOwner.explicitlyGrantURLIfCoveredByGrantedMatchPattern(
            url,
            in: context,
            tab: adapter
        )
    }

    private func extensionIDForContext(_ context: WKWebExtensionContext) -> String? {
        dependencies.runtimeAccess.profileRuntimeOwner.extensionId(for: context)
    }

    private func configuredSiteAccessLevel(
        _ url: URL,
        _ extensionId: String,
        _ profileId: UUID
    ) -> SafariExtensionSiteAccessLevel {
        dependencies.siteAccessPolicyCoordinator.configuredSiteAccessLevel(
            for: url,
            extensionId: extensionId,
            profileId: profileId
        )
    }

    private func grantSiteAccess(
        _ url: URL,
        _ context: WKWebExtensionContext,
        _ extensionId: String,
        _ profileId: UUID?,
        _ expirationDate: Date?,
        _ persistPolicy: Bool
    ) {
        dependencies.siteAccessPolicyCoordinator.grantSiteAccess(
            to: url,
            in: context,
            extensionId: extensionId,
            profileId: profileId,
            expirationDate: expirationDate,
            persistPolicy: persistPolicy
        )
    }

    private func denySiteAccess(
        _ url: URL,
        _ context: WKWebExtensionContext,
        _ extensionId: String,
        _ profileId: UUID?,
        _ persistPolicy: Bool
    ) {
        dependencies.siteAccessPolicyCoordinator.denySiteAccess(
            to: url,
            in: context,
            extensionId: extensionId,
            profileId: profileId,
            persistPolicy: persistPolicy
        )
    }

    private func permissionPromptDedupeKey(_ context: WKWebExtensionContext, _ targets: [String]) -> String {
        dependencies.permissionDecisionStoreOwner.permissionPromptDedupeKey(
            extensionContext: context,
            targets: targets
        )
    }

    private func persistExtensionPermissionDecision(
        _ extensionId: String,
        _ profileId: UUID,
        _ targetKind: ExtensionManager.ExtensionPermissionTargetKind,
        _ target: String,
        _ state: ExtensionManager.ExtensionStoredPermissionState,
        _ expiresAt: Date?
    ) {
        dependencies.permissionDecisionStoreOwner.persistExtensionPermissionDecision(
            extensionId: extensionId,
            profileId: profileId,
            targetKind: targetKind,
            target: target,
            state: state,
            expiresAt: expiresAt
        )
    }

    private func hostMatchPatternString(_ url: URL) -> String? {
        dependencies.siteAccessPolicyCoordinator.hostMatchPatternString(for: url)
    }

    private func updateActionSurfaceState(_ action: WKWebExtension.Action, _ context: WKWebExtensionContext) {
        dependencies.actionSurfacePublicationOwner.updateActionSurfaceState(
            for: action,
            extensionContext: context
        )
    }

    private func recordRuntimeMetric(
        _ extensionId: String,
        _ update: (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void
    ) {
        dependencies.runtimeAccess.runtimeSessionOwner.recordRuntimeMetric(
            for: extensionId,
            update: update
        )
    }

    private func trace(_ message: () -> String) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        dependencies.runtimeDiagnosticsOwner.trace(message())
    }

    func openActionPopupFromURLHub(
        extensionId: String,
        currentTab: Tab?
    ) async -> BrowserExtensionActionPopupRequestResult {
        guard let installedExtension = installedExtensions().first(where: {
            $0.id == extensionId
        }) else {
            return .blocked(
                .extensionNotInstalled,
                message: "The extension is not installed in Sumi's local extension store."
            )
        }
        trace {
            "urlHubAction click extensionId=\(extensionId) manifestHash=\(installedExtension.manifestRootFingerprint) resourcesPath=\(installedExtension.packagePath) sourceBundlePath=\(installedExtension.sourceBundlePath) extensionEnabled=\(installedExtension.isEnabled) runtimeState=\(self.runtimeState().rawValue) contextLoaded=\(self.getExtensionContext(extensionId, nil) != nil) currentProfile=\(self.currentProfileId()?.uuidString ?? "nil") tabProfile=\(currentTab?.profileId?.uuidString ?? "nil") tabOffRecord=\(currentTab?.isEphemeral ?? false) currentURLShape=\(Self.sanitizedURLHubTraceURL(currentTab?.url))"
        }
        guard installedExtension.isEnabled else {
            return .blocked(
                .extensionDisabled,
                message: "\(installedExtension.name) is disabled."
            )
        }
        guard installedExtension.hasAction else {
            return .blocked(
                .actionMissing,
                message: "\(installedExtension.name) does not declare a Chrome action."
            )
        }
        if let currentTab {
            guard currentTab.isEphemeral == false else {
                return .blocked(
                    .noEligibleTab,
                    message: "Private tabs are not eligible for extension action popups."
                )
            }
        }
        guard Self.isModuleWorkerUnsupported(installedExtension) == false else {
            return .blocked(
                .moduleWorkerUnsupported,
                message: "\(installedExtension.name) declares a module service worker, which remains unsupported in this popup path."
            )
        }
        trace {
            "urlHubAction preflight passed extensionId=\(extensionId) localExperimentalRecordEnabled=true currentTabEligible=\(currentTab != nil) currentPagePermission=true moduleWorkerUnsupported=false"
        }

        guard let actionProfileId =
                currentTab.flatMap({ dependencies.resolvedProfileIdForTab($0) })
                ?? fallbackProfileId()
        else {
            return .blocked(
                .noEligibleTab,
                message: "No profile is available for the extension action."
            )
        }
        if dependencies.actionPopupAnchorStore.latestSessionToken(for: extensionId) == nil {
            let windowId =
                currentTab.flatMap { tab in
                    dependencies.runtimeAccess.runtime().primaryTrackedWindowId(tab.id)
                }
                ?? dependencies.activeExtensionWindowId()
            if let windowId {
                captureActionPopupAnchor(
                    extensionId,
                    windowId,
                    actionProfileId
                )
            }
        }
        switchProfile(actionProfileId)
        ensureExtensionController(actionProfileId)

        let extensionContext: WKWebExtensionContext
        do {
            trace {
                "urlHubAction loading selected context extensionId=\(installedExtension.id) profileId=\(actionProfileId.uuidString) runtimeState=\(self.runtimeState().rawValue) packagePath=\(installedExtension.packagePath)"
            }
            guard let loadedContext = try await ensureExtensionLoaded(
                installedExtension.id,
                actionProfileId
            ) else {
                let failureBucket = classifyFailure(
                    extensionId,
                    actionProfileId,
                    installedExtension
                )
                let diagnostics = diagnosticLines(
                    extensionId,
                    actionProfileId,
                    installedExtension,
                    failureBucket,
                    lastExtensionLoadError(extensionId, actionProfileId)
                )
                return .blocked(
                    .contextUnavailable,
                    message: "\(installedExtension.name) has no enabled WebKit extension context for this profile.",
                    diagnostics: diagnostics
                )
            }
            extensionContext = loadedContext
        } catch {
            let failureBucket = classifyFailure(
                extensionId,
                actionProfileId,
                installedExtension
            )
            let diagnostics = diagnosticLines(
                extensionId,
                actionProfileId,
                installedExtension,
                failureBucket,
                error
            )
            trace {
                "urlHubAction selected context load failed extensionId=\(extensionId) bucket=\(failureBucket.rawValue) error=\(error.localizedDescription) \(diagnostics.joined(separator: " "))"
            }
            return .blocked(
                .runtimeLoadFailed,
                message: "\(installedExtension.name) WebKit context load failed: \(error.localizedDescription)",
                diagnostics: diagnostics
            )
        }

        guard extensionContext.isLoaded else {
            let failureBucket = classifyFailure(
                extensionId,
                actionProfileId,
                installedExtension
            )
            let diagnostics = diagnosticLines(
                extensionId,
                actionProfileId,
                installedExtension,
                failureBucket,
                lastExtensionLoadError(extensionId, actionProfileId)
            )
            trace {
                "urlHubAction runtime gate failed extensionId=\(extensionId) profileId=\(actionProfileId.uuidString) bucket=\(failureBucket.rawValue) \(diagnostics.joined(separator: " "))"
            }
            let blocker: BrowserExtensionActionPopupBlocker =
                failureBucket == .globalRuntimeLoadFailed
                    || failureBucket == .webExtensionCreationFailed
                    || failureBucket == .profileContextNotLoaded
                ? .runtimeLoadFailed
                : .runtimeUnavailable
            return .blocked(
                blocker,
                message: "\(installedExtension.name) could not load WebKit extension runtime for the action popup.",
                diagnostics: diagnostics
            )
        }
        trace {
            "urlHubAction runtime ready extensionId=\(extensionId) profileId=\(actionProfileId.uuidString) loadedContexts=\(self.loadedContextCount(actionProfileId)) selectedContextLoaded=true currentTabEligible=\(currentTab != nil)"
        }

        let adapter: ExtensionTabAdapter?
        if let currentTab {
            dependencies.registerTabWithExtensionRuntime(
                currentTab,
                "ExtensionManager.openActionPopupFromURLHub"
            )
            adapter = dependencies.stableAdapter(currentTab)
        } else {
            adapter = nil
        }
        grantRequestedPermissions(
            extensionContext,
            extensionContext.webExtension,
            installedExtension.manifest
        )
        dependencies.grantRequestedMatchPatterns(
            extensionContext,
            extensionContext.webExtension
        )
        if let currentTab {
            let hasActionPageAccess = await prepareActionClickPageAccess(
                for: extensionContext,
                installedExtension: installedExtension,
                tab: currentTab
            )
            guard hasActionPageAccess else {
                return .blocked(
                    .currentPagePermissionMissing,
                    message: "\(installedExtension.name) was not granted access to the current page."
                )
            }
        }

        guard let action = extensionContext.action(for: adapter) else {
            return .blocked(
                .actionMissing,
                message: "WebKit did not expose an action for \(installedExtension.name)."
            )
        }

        updateActionSurfaceState(action, extensionContext)

        guard action.isEnabled else {
            return .blocked(
                .actionDisabled,
                message: "\(action.label) is disabled for the current page."
            )
        }

        trace {
            "urlHubAction performAction extensionId=\(extensionId) actionLabel=\(action.label) actionEnabled=\(action.isEnabled) presentsPopup=\(action.presentsPopup)"
        }
        extensionContext.performAction(for: adapter)
        recordRuntimeMetric(extensionId) { metrics in
            metrics.lastBackgroundWakeReason = .actionPopup
            metrics.backgroundWakeCount += 1
        }
        return action.presentsPopup ? .openedPopup : .performedAction
    }

    private func prepareActionClickPageAccess(
        for extensionContext: WKWebExtensionContext,
        installedExtension: InstalledExtension,
        tab: Tab
    ) async -> Bool {
        let currentURL = tab.url
        guard ["http", "https"].contains(currentURL.scheme?.lowercased() ?? "") else {
            return true
        }

        let adapter = dependencies.stableAdapter(tab)
        let manifest = installedExtension.manifest
        let permissions = Self.stringArray(from: manifest["permissions"])
        let optionalPermissions = Self.stringArray(from: manifest["optional_permissions"])
        if (permissions + optionalPermissions).contains("activeTab") {
            grantActiveTabURLAccess(
                extensionContext,
                tab,
                manifest
            )
            return true
        }

        let status = effectivePermissionStatus(
            currentURL,
            extensionContext,
            adapter
        )
        if isGrantedPermissionStatus(status) {
            return true
        }
        if status == .deniedExplicitly {
            return false
        }
        if explicitlyGrantURLIfCoveredByGrantedMatchPattern(
            currentURL,
            extensionContext,
            adapter
        ) {
            return true
        }

        let decisionProfileId = tab.profileId
            ?? dependencies.resolvedProfileIdForTab(tab)
            ?? currentProfileId()
        if let extensionId = extensionIDForContext(extensionContext),
           let decisionProfileId {
            switch configuredSiteAccessLevel(
                currentURL,
                extensionId,
                decisionProfileId
            ) {
            case .allow:
                grantSiteAccess(
                    currentURL,
                    extensionContext,
                    extensionId,
                    decisionProfileId,
                    nil,
                    false
                )
                return true
            case .deny:
                denySiteAccess(
                    currentURL,
                    extensionContext,
                    extensionId,
                    decisionProfileId,
                    false
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

        guard Self.hasActionCurrentPagePermission(
            installedExtension,
            currentURL: currentURL
        ) else {
            return true
        }

        let host = currentURL.host ?? currentURL.scheme ?? "this site"
        let patternString = hostMatchPatternString(currentURL)
        let decision = await dependencies.promptForExtensionPermissionDecision(
            extensionContext,
            [host],
            "actionClickCurrentPageAccess",
            permissionPromptDedupeKey(
                extensionContext,
                patternString.map { [$0] } ?? [host]
            )
        )

        switch decision {
        case .allow(let expirationDate):
            grantSiteAccess(
                currentURL,
                extensionContext,
                installedExtension.id,
                decisionProfileId,
                expirationDate,
                true
            )
            if let patternString, let decisionProfileId {
                persistExtensionPermissionDecision(
                    installedExtension.id,
                    decisionProfileId,
                    .matchPattern,
                    patternString,
                    .allowed,
                    expirationDate
                )
            }
            SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                granted: true,
                extensionId: installedExtension.id,
                reason: "actionClickPromptAllowed"
            )
            return true
        case .deny:
            denySiteAccess(
                currentURL,
                extensionContext,
                installedExtension.id,
                decisionProfileId,
                true
            )
            if let patternString, let decisionProfileId {
                persistExtensionPermissionDecision(
                    installedExtension.id,
                    decisionProfileId,
                    .matchPattern,
                    patternString,
                    .denied,
                    nil
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

    private static func hasActionCurrentPagePermission(
        _ installedExtension: InstalledExtension,
        currentURL: URL
    ) -> Bool {
        guard ["http", "https"].contains(currentURL.scheme?.lowercased() ?? "") else {
            return false
        }

        let manifest = installedExtension.manifest
        let permissions = stringArray(from: manifest["permissions"])
        let optionalPermissions = stringArray(from: manifest["optional_permissions"])
        if (permissions + optionalPermissions).contains("activeTab") {
            return true
        }

        let contentScriptMatches =
            (manifest["content_scripts"] as? [[String: Any]] ?? [])
                .flatMap { stringArray(from: $0["matches"]) }
        let hostPatterns =
            stringArray(from: manifest["host_permissions"])
            + permissions.filter(isHostPermissionPattern)
            + contentScriptMatches

        return hostPatterns.contains {
            ExtensionUtils.hostPatternMatchesURL($0, url: currentURL)
        }
    }

    private static func isModuleWorkerUnsupported(
        _ installedExtension: InstalledExtension
    ) -> Bool {
        guard let background = installedExtension.manifest["background"]
                as? [String: Any],
              let type = background["type"] as? String
        else {
            return false
        }
        return type.caseInsensitiveCompare("module") == .orderedSame
    }

    private static func sanitizedURLHubTraceURL(_ url: URL?) -> String {
        guard let url, let scheme = url.scheme?.lowercased() else {
            return "nil"
        }
        if ExtensionUtils.isExtensionOwnedURL(url) {
            return "\(scheme)://<extension>/\(url.lastPathComponent.isEmpty ? "<resource>" : url.lastPathComponent)"
        }
        if scheme == "http" || scheme == "https" {
            return "\(scheme)://<host>/<redacted-path>"
        }
        return "\(scheme)://<redacted>"
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
extension ExtensionActionClickFlowOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            actionPopupAnchorStore: manager.actionPopupAnchorStore,
            installedRecordsOwner: manager.installedRecordsOwner,
            runtimeAccess: ExtensionFlowOwnerRuntimeAccess(
                profileRuntimeOwner: manager.profileRuntimeOwner,
                controllerProvisioningOwner: manager.controllerProvisioningOwner,
                runtimeSessionOwner: manager.runtimeSessionOwner,
                runtime: { [weak manager] in manager?.runtime ?? .inactive }
            ),
            actionPopupAnchorResolutionOwner: manager.actionPopupAnchorResolutionOwner,
            runtimeLifecycleOwner: manager.runtimeLifecycleOwner,
            contextResidencyOwner: manager.contextResidencyOwner,
            actionPopupFailureDiagnosticsOwner: manager.actionPopupFailureDiagnosticsOwner,
            installCapabilityOwner: manager.installCapabilityOwner,
            siteAccessPolicyCoordinator: manager.siteAccessPolicyCoordinator,
            permissionDecisionStoreOwner: manager.permissionDecisionStoreOwner,
            actionSurfacePublicationOwner: manager.actionSurfacePublicationOwner,
            runtimeDiagnosticsOwner: manager.runtimeDiagnosticsOwner,
            resolvedProfileIdForTab: { [weak manager] tab in
                manager?.resolvedProfileId(for: tab)
            },
            activeExtensionWindowId: { [weak manager] in
                manager?.browserBridgeContext?.activeExtensionWindowState?.id
            },
            registerTabWithExtensionRuntime: { [weak manager] tab, reason in
                manager?.registerTabWithExtensionRuntime(tab, reason: reason)
            },
            stableAdapter: { [weak manager] tab in
                manager?.adapterResolutionOwner.stableAdapter(for: tab)
            },
            grantRequestedMatchPatterns: { [weak manager] context, webExtension in
                manager?.grantRequestedMatchPatterns(
                    to: context,
                    webExtension: webExtension
                )
            },
            promptForExtensionPermissionDecision: { [weak manager] context, targets, reason, dedupeKey in
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

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func openActionPopupFromURLHub(
        extensionId: String,
        currentTab: Tab?
    ) async -> BrowserExtensionActionPopupRequestResult {
        await actionClickFlowOwner.openActionPopupFromURLHub(
            extensionId: extensionId,
            currentTab: currentTab
        )
    }
}
