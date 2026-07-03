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
        let installedExtensions: @MainActor () -> [InstalledExtension]
        let runtimeState: @MainActor () -> ExtensionManager.ExtensionRuntimeState
        let currentProfileId: @MainActor () -> UUID?
        let fallbackProfileId: @MainActor () -> UUID?
        let resolvedProfileIdForTab: @MainActor (Tab) -> UUID?
        let getExtensionContext: @MainActor (String, UUID?) -> WKWebExtensionContext?
        let loadedContextCount: @MainActor (UUID) -> Int
        let activeExtensionWindowId: @MainActor () -> UUID?
        let captureActionPopupAnchor: @MainActor (String, UUID, UUID?) -> Void
        let switchProfile: @MainActor (UUID) -> Void
        let ensureExtensionController: @MainActor (UUID) -> Void
        let ensureExtensionLoaded: @MainActor (String, UUID) async throws -> WKWebExtensionContext?
        let classifyFailure: @MainActor (String, UUID, InstalledExtension?) -> ExtensionActionPopupRuntimeFailureBucket
        let diagnosticLines:
            @MainActor (String, UUID, InstalledExtension, ExtensionActionPopupRuntimeFailureBucket, Error?) -> [String]
        let lastExtensionLoadError: @MainActor (String, UUID) -> Error?
        let registerTabWithExtensionRuntime: @MainActor (Tab, String) -> Void
        let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
        let grantRequestedPermissions: @MainActor (WKWebExtensionContext, WKWebExtension, [String: Any]) -> Void
        let grantRequestedMatchPatterns: @MainActor (WKWebExtensionContext, WKWebExtension) -> Void
        let grantActiveTabURLAccess: @MainActor (WKWebExtensionContext, Tab, [String: Any]) -> Void
        let effectivePermissionStatus:
            @MainActor (URL, WKWebExtensionContext, ExtensionTabAdapter?) -> WKWebExtensionContext.PermissionStatus
        let isGrantedPermissionStatus: @MainActor (WKWebExtensionContext.PermissionStatus) -> Bool
        let explicitlyGrantURLIfCoveredByGrantedMatchPattern:
            @MainActor (URL, WKWebExtensionContext, ExtensionTabAdapter?) -> Bool
        let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?
        let configuredSiteAccessLevel:
            @MainActor (URL, String, UUID) -> SafariExtensionSiteAccessLevel
        let grantSiteAccess: @MainActor (URL, WKWebExtensionContext, String, UUID?, Date?, Bool) -> Void
        let denySiteAccess: @MainActor (URL, WKWebExtensionContext, String, UUID?, Bool) -> Void
        let promptForExtensionPermissionDecision:
            @MainActor (WKWebExtensionContext, [String], String, String) async -> ExtensionManager.ExtensionPermissionPromptDecision
        let permissionPromptDedupeKey: @MainActor (WKWebExtensionContext, [String]) -> String
        let persistExtensionPermissionDecision:
            @MainActor (String, UUID, ExtensionManager.ExtensionPermissionTargetKind, String, ExtensionManager.ExtensionStoredPermissionState, Date?) -> Void
        let hostMatchPatternString: @MainActor (URL) -> String?
        let updateActionSurfaceState: @MainActor (WKWebExtension.Action, WKWebExtensionContext) -> Void
        let recordRuntimeMetric:
            @MainActor (String, (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void) -> Void
        let trace: @MainActor (() -> String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func openActionPopupFromURLHub(
        extensionId: String,
        currentTab: Tab?
    ) async -> BrowserExtensionActionPopupRequestResult {
        guard let installedExtension = dependencies.installedExtensions().first(where: {
            $0.id == extensionId
        }) else {
            return .blocked(
                .extensionNotInstalled,
                message: "The extension is not installed in Sumi's local extension store."
            )
        }
        dependencies.trace {
            "urlHubAction click extensionId=\(extensionId) manifestHash=\(installedExtension.manifestRootFingerprint) resourcesPath=\(installedExtension.packagePath) sourceBundlePath=\(installedExtension.sourceBundlePath) extensionEnabled=\(installedExtension.isEnabled) runtimeState=\(self.dependencies.runtimeState().rawValue) contextLoaded=\(self.dependencies.getExtensionContext(extensionId, nil) != nil) currentProfile=\(self.dependencies.currentProfileId()?.uuidString ?? "nil") tabProfile=\(currentTab?.profileId?.uuidString ?? "nil") tabOffRecord=\(currentTab?.isEphemeral ?? false) currentURLShape=\(Self.sanitizedURLHubTraceURL(currentTab?.url))"
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
        dependencies.trace {
            "urlHubAction preflight passed extensionId=\(extensionId) localExperimentalRecordEnabled=true currentTabEligible=\(currentTab != nil) currentPagePermission=true moduleWorkerUnsupported=false"
        }

        guard let actionProfileId =
                currentTab.flatMap({ dependencies.resolvedProfileIdForTab($0) })
                ?? dependencies.fallbackProfileId()
        else {
            return .blocked(
                .noEligibleTab,
                message: "No profile is available for the extension action."
            )
        }
        if dependencies.actionPopupAnchorStore.latestSessionToken(for: extensionId) == nil {
            let windowId =
                currentTab?.primaryWindowId
                ?? dependencies.activeExtensionWindowId()
            if let windowId {
                dependencies.captureActionPopupAnchor(
                    extensionId,
                    windowId,
                    actionProfileId
                )
            }
        }
        dependencies.switchProfile(actionProfileId)
        dependencies.ensureExtensionController(actionProfileId)

        let extensionContext: WKWebExtensionContext
        do {
            dependencies.trace {
                "urlHubAction loading selected context extensionId=\(installedExtension.id) profileId=\(actionProfileId.uuidString) runtimeState=\(self.dependencies.runtimeState().rawValue) packagePath=\(installedExtension.packagePath)"
            }
            guard let loadedContext = try await dependencies.ensureExtensionLoaded(
                installedExtension.id,
                actionProfileId
            ) else {
                let failureBucket = dependencies.classifyFailure(
                    extensionId,
                    actionProfileId,
                    installedExtension
                )
                let diagnostics = dependencies.diagnosticLines(
                    extensionId,
                    actionProfileId,
                    installedExtension,
                    failureBucket,
                    dependencies.lastExtensionLoadError(extensionId, actionProfileId)
                )
                return .blocked(
                    .contextUnavailable,
                    message: "\(installedExtension.name) has no enabled WebKit extension context for this profile.",
                    diagnostics: diagnostics
                )
            }
            extensionContext = loadedContext
        } catch {
            let failureBucket = dependencies.classifyFailure(
                extensionId,
                actionProfileId,
                installedExtension
            )
            let diagnostics = dependencies.diagnosticLines(
                extensionId,
                actionProfileId,
                installedExtension,
                failureBucket,
                error
            )
            dependencies.trace {
                "urlHubAction selected context load failed extensionId=\(extensionId) bucket=\(failureBucket.rawValue) error=\(error.localizedDescription) \(diagnostics.joined(separator: " "))"
            }
            return .blocked(
                .runtimeLoadFailed,
                message: "\(installedExtension.name) WebKit context load failed: \(error.localizedDescription)",
                diagnostics: diagnostics
            )
        }

        guard extensionContext.isLoaded else {
            let failureBucket = dependencies.classifyFailure(
                extensionId,
                actionProfileId,
                installedExtension
            )
            let diagnostics = dependencies.diagnosticLines(
                extensionId,
                actionProfileId,
                installedExtension,
                failureBucket,
                dependencies.lastExtensionLoadError(extensionId, actionProfileId)
            )
            dependencies.trace {
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
        dependencies.trace {
            "urlHubAction runtime ready extensionId=\(extensionId) profileId=\(actionProfileId.uuidString) loadedContexts=\(self.dependencies.loadedContextCount(actionProfileId)) selectedContextLoaded=true currentTabEligible=\(currentTab != nil)"
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
        dependencies.grantRequestedPermissions(
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

        dependencies.updateActionSurfaceState(action, extensionContext)

        guard action.isEnabled else {
            return .blocked(
                .actionDisabled,
                message: "\(action.label) is disabled for the current page."
            )
        }

        dependencies.trace {
            "urlHubAction performAction extensionId=\(extensionId) actionLabel=\(action.label) actionEnabled=\(action.isEnabled) presentsPopup=\(action.presentsPopup)"
        }
        extensionContext.performAction(for: adapter)
        dependencies.recordRuntimeMetric(extensionId) { metrics in
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
            dependencies.grantActiveTabURLAccess(
                extensionContext,
                tab,
                manifest
            )
            return true
        }

        let status = dependencies.effectivePermissionStatus(
            currentURL,
            extensionContext,
            adapter
        )
        if dependencies.isGrantedPermissionStatus(status) {
            return true
        }
        if status == .deniedExplicitly {
            return false
        }
        if dependencies.explicitlyGrantURLIfCoveredByGrantedMatchPattern(
            currentURL,
            extensionContext,
            adapter
        ) {
            return true
        }

        let decisionProfileId = tab.profileId
            ?? dependencies.resolvedProfileIdForTab(tab)
            ?? dependencies.currentProfileId()
        if let extensionId = dependencies.extensionIDForContext(extensionContext),
           let decisionProfileId {
            switch dependencies.configuredSiteAccessLevel(
                currentURL,
                extensionId,
                decisionProfileId
            ) {
            case .allow:
                dependencies.grantSiteAccess(
                    currentURL,
                    extensionContext,
                    extensionId,
                    decisionProfileId,
                    nil,
                    false
                )
                return true
            case .deny:
                dependencies.denySiteAccess(
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
        let patternString = dependencies.hostMatchPatternString(currentURL)
        let decision = await dependencies.promptForExtensionPermissionDecision(
            extensionContext,
            [host],
            "actionClickCurrentPageAccess",
            dependencies.permissionPromptDedupeKey(
                extensionContext,
                patternString.map { [$0] } ?? [host]
            )
        )

        switch decision {
        case .allow(let expirationDate):
            dependencies.grantSiteAccess(
                currentURL,
                extensionContext,
                installedExtension.id,
                decisionProfileId,
                expirationDate,
                true
            )
            if let patternString, let decisionProfileId {
                dependencies.persistExtensionPermissionDecision(
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
            dependencies.denySiteAccess(
                currentURL,
                extensionContext,
                installedExtension.id,
                decisionProfileId,
                true
            )
            if let patternString, let decisionProfileId {
                dependencies.persistExtensionPermissionDecision(
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
            installedExtensions: { [weak manager] in
                manager?.installedExtensions ?? []
            },
            runtimeState: { [weak manager] in
                manager?.runtimeState ?? .unavailable
            },
            currentProfileId: { [weak manager] in
                manager?.currentProfileId
            },
            fallbackProfileId: { [weak manager] in
                manager?.fallbackProfileId
            },
            resolvedProfileIdForTab: { [weak manager] tab in
                manager?.resolvedProfileId(for: tab)
            },
            getExtensionContext: { [weak manager] extensionId, profileId in
                manager?.getExtensionContext(for: extensionId, profileId: profileId)
            },
            loadedContextCount: { [weak manager] profileId in
                manager?.extensionContexts(for: profileId).count ?? 0
            },
            activeExtensionWindowId: { [weak manager] in
                manager?.browserBridgeContext?.activeExtensionWindowState?.id
            },
            captureActionPopupAnchor: { [weak manager] extensionId, windowId, profileId in
                _ = manager?.actionPopupAnchorResolutionOwner.captureActionPopupAnchor(
                    extensionId: extensionId,
                    windowId: windowId,
                    profileId: profileId
                )
            },
            switchProfile: { [weak manager] profileId in
                manager?.switchProfile(profileId: profileId)
            },
            ensureExtensionController: { [weak manager] profileId in
                _ = manager?.ensureExtensionController(for: profileId)
            },
            ensureExtensionLoaded: { [weak manager] extensionId, profileId in
                try await manager?.ensureExtensionLoaded(
                    extensionId: extensionId,
                    profileId: profileId
                )
            },
            classifyFailure: { [weak manager] extensionId, profileId, installedExtension in
                manager?.classifyActionPopupRuntimeFailure(
                    extensionId: extensionId,
                    profileId: profileId,
                    installedExtension: installedExtension
                ) ?? .profileRuntimeNotFound
            },
            diagnosticLines: { [weak manager] extensionId, profileId, installedExtension, bucket, error in
                manager?.actionPopupRuntimeDiagnosticLines(
                    extensionId: extensionId,
                    profileId: profileId,
                    installedExtension: installedExtension,
                    failureBucket: bucket,
                    lastLoadError: error
                ) ?? []
            },
            lastExtensionLoadError: { [weak manager] extensionId, profileId in
                manager?.lastExtensionLoadError(
                    extensionId: extensionId,
                    profileId: profileId
                )
            },
            registerTabWithExtensionRuntime: { [weak manager] tab, reason in
                manager?.registerTabWithExtensionRuntime(tab, reason: reason)
            },
            stableAdapter: { [weak manager] tab in
                manager?.adapterResolutionOwner.stableAdapter(for: tab)
            },
            grantRequestedPermissions: { [weak manager] context, webExtension, manifest in
                manager?.grantRequestedPermissions(
                    to: context,
                    webExtension: webExtension,
                    manifest: manifest
                )
            },
            grantRequestedMatchPatterns: { [weak manager] context, webExtension in
                manager?.grantRequestedMatchPatterns(
                    to: context,
                    webExtension: webExtension
                )
            },
            grantActiveTabURLAccess: { [weak manager] context, tab, manifest in
                manager?.grantActiveTabURLAccess(
                    for: context,
                    tab: tab,
                    manifest: manifest
                )
            },
            effectivePermissionStatus: { [weak manager] url, context, adapter in
                manager?.effectivePermissionStatus(
                    for: url,
                    in: context,
                    tab: adapter
                ) ?? .unknown
            },
            isGrantedPermissionStatus: { [weak manager] status in
                manager?.isGrantedPermissionStatus(status) ?? false
            },
            explicitlyGrantURLIfCoveredByGrantedMatchPattern: { [weak manager] url, context, adapter in
                manager?.explicitlyGrantURLIfCoveredByGrantedMatchPattern(
                    url,
                    in: context,
                    tab: adapter
                ) ?? false
            },
            extensionIDForContext: { [weak manager] context in
                manager?.extensionID(for: context)
            },
            configuredSiteAccessLevel: { [weak manager] url, extensionId, profileId in
                manager?.configuredSiteAccessLevel(
                    for: url,
                    extensionId: extensionId,
                    profileId: profileId
                ) ?? .ask
            },
            grantSiteAccess: { [weak manager] url, context, extensionId, profileId, expirationDate, persistPolicy in
                if persistPolicy {
                    manager?.grantSiteAccess(
                        to: url,
                        in: context,
                        extensionId: extensionId,
                        profileId: profileId,
                        expirationDate: expirationDate
                    )
                } else {
                    manager?.grantSiteAccess(
                        to: url,
                        in: context,
                        extensionId: extensionId,
                        profileId: profileId,
                        persistPolicy: false
                    )
                }
            },
            denySiteAccess: { [weak manager] url, context, extensionId, profileId, persistPolicy in
                if persistPolicy {
                    manager?.denySiteAccess(
                        to: url,
                        in: context,
                        extensionId: extensionId,
                        profileId: profileId
                    )
                } else {
                    manager?.denySiteAccess(
                        to: url,
                        in: context,
                        extensionId: extensionId,
                        profileId: profileId,
                        persistPolicy: false
                    )
                }
            },
            promptForExtensionPermissionDecision: { [weak manager] context, targets, reason, dedupeKey in
                await manager?.promptForExtensionPermissionDecision(
                    extensionContext: context,
                    targets: targets,
                    reason: reason,
                    dedupeKey: dedupeKey
                ) ?? .deny
            },
            permissionPromptDedupeKey: { [weak manager] context, targets in
                manager?.permissionPromptDedupeKey(
                    extensionContext: context,
                    targets: targets
                ) ?? targets.joined(separator: "|")
            },
            persistExtensionPermissionDecision: { [weak manager] extensionId, profileId, targetKind, target, state, expiresAt in
                manager?.persistExtensionPermissionDecision(
                    extensionId: extensionId,
                    profileId: profileId,
                    targetKind: targetKind,
                    target: target,
                    state: state,
                    expiresAt: expiresAt
                )
            },
            hostMatchPatternString: { [weak manager] url in
                manager?.hostMatchPatternString(for: url)
            },
            updateActionSurfaceState: { [weak manager] action, context in
                manager?.updateActionSurfaceState(
                    for: action,
                    extensionContext: context
                )
            },
            recordRuntimeMetric: { [weak manager] extensionId, update in
                manager?.runtimeSessionOwner.recordRuntimeMetric(for: extensionId, update: update)
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message())
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
