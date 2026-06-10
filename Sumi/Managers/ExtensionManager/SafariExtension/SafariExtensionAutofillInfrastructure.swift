//
//  SafariExtensionAutofillInfrastructure.swift
//  Sumi
//
//  Generic autofill infrastructure probes and blocker classification buckets.
//  Never logs credentials, message bodies, or storage payloads.
//

import Foundation
import WebKit

/// Precise autofill failure buckets for Safari Web Extension password managers.
enum SafariExtensionAutofillBlocker: String, Codable, CaseIterable, Sendable {
    case none
    case extensionsModuleDisabled
    case extensionsRuntimeNotReady
    case contextNotLoaded
    case contentScriptsNotDeclared
    case contentScriptNotInjected
    case privateTabBlocked
    case tabMappingMissing
    case frameMappingMissing
    case targetWebViewMissingExtensionController
    case targetWebViewWrongProfileController
    case scriptingExecuteScriptTargetMissing
    case hostPermissionDenied
    case activeTabPermissionMissing
    case nativeMessagingRequired
    case companionAppProtocolUnknown
    case siteSpecificFormUnsupported
    /// Reserved for real production sites after controlled local form + iframe verification.
    /// Extensions own form detection and site-specific behavior; URLs are not preemptively blocked.
    case realSiteSpecificComplexity
}

struct SafariExtensionAutofillClassification: Codable, Equatable, Sendable {
    let primaryBlocker: SafariExtensionAutofillBlocker
    let secondaryBlockers: [SafariExtensionAutofillBlocker]
    let detail: String

    var isReady: Bool { primaryBlocker == .none }
}

@MainActor
enum SafariExtensionAutofillInfrastructureClassifier {
    static func classifyInfrastructure(
        extensionsModuleEnabled: Bool
    ) -> SafariExtensionAutofillClassification {
        guard extensionsModuleEnabled else {
            return classification(
                .extensionsModuleDisabled,
                detail: "Extensions module is disabled"
            )
        }

        var secondary: [SafariExtensionAutofillBlocker] = []

        let tabFrameProbe = SafariExtensionTabFrameMappingProbe.evaluate()
        if tabFrameProbe.passed == false {
            secondary.append(.frameMappingMissing)
        }

        if SafariExtensionContentScriptProbe.isTabReconcilePathWiredInSources() == false {
            secondary.append(.contentScriptNotInjected)
        }

        let fixtureProbe = SafariExtensionPasswordManagerFormFixtureProbe.evaluate()
        if fixtureProbe.passed == false {
            secondary.append(.siteSpecificFormUnsupported)
        }

        if secondary.isEmpty {
            return classification(
                .none,
                detail: "Generic autofill infrastructure probes passed"
            )
        }

        return SafariExtensionAutofillClassification(
            primaryBlocker: secondary[0],
            secondaryBlockers: Array(secondary.dropFirst()),
            detail: secondary.map(\.rawValue).joined(separator: ", ")
        )
    }

    static func classifyTab(
        tab: Tab,
        installedExtension: InstalledExtension,
        extensionContext: WKWebExtensionContext?,
        extensionManager: ExtensionManager,
        extensionsModuleEnabled: Bool
    ) -> SafariExtensionAutofillClassification {
        let infrastructure = classifyInfrastructure(
            extensionsModuleEnabled: extensionsModuleEnabled
        )
        guard infrastructure.isReady else { return infrastructure }

        if tab.isEphemeral {
            return classification(
                .privateTabBlocked,
                detail: "Private/ephemeral tabs are excluded from extension runtime"
            )
        }

        guard extensionManager.extensionsLoaded else {
            return classification(
                .extensionsRuntimeNotReady,
                detail: "Extension runtime has not finished loading installed extensions"
            )
        }

        guard installedExtension.hasContentScripts else {
            return classification(
                .contentScriptsNotDeclared,
                detail: "Extension manifest declares no content_scripts"
            )
        }

        guard let extensionContext else {
            return classification(
                .contextNotLoaded,
                detail: "Extension context is not loaded for the tab profile"
            )
        }

        if extensionManager.tabMatchesExtensionContext(tab, extensionContext: extensionContext) == false {
            return classification(
                .targetWebViewWrongProfileController,
                detail: "Tab profile does not match extension context profile"
            )
        }

        guard extensionManager.isTabEligibleForCurrentExtensionRuntime(tab) else {
            return classification(
                .tabMappingMissing,
                detail: "Tab is not eligible for the current extension runtime generation"
            )
        }

        guard extensionManager.stableAdapter(for: tab) != nil else {
            return classification(
                .tabMappingMissing,
                detail: "No stable WKWebExtensionTab adapter is registered for this tab"
            )
        }

        let pageURL = tab.url
        if let siteBlocker = classifySiteSpecificURL(pageURL) {
            return classification(
                siteBlocker,
                detail: "Site-specific classification for \(sanitizedURLShape(pageURL))"
            )
        }

        if let permissionBlocker = hostPermissionBlocker(
            for: pageURL,
            installedExtension: installedExtension,
            extensionContext: extensionContext
        ) {
            return classification(
                permissionBlocker,
                detail: "Page URL lacks granted host permission: \(sanitizedURLShape(pageURL))"
            )
        }

        guard let webView = extensionManager.resolvedLiveWebView(for: tab) else {
            return classification(
                .targetWebViewMissingExtensionController,
                detail: "Tab has no live WKWebView for extension targeting"
            )
        }

        let profileId = extensionManager.resolvedProfileId(for: tab)
        let expectedController = profileId.flatMap {
            extensionManager.extensionControllersByProfile[$0]
        }

        if let expectedController {
            let actualController = webView.configuration.webExtensionController
            if let actualController, actualController !== expectedController {
                return classification(
                    .targetWebViewWrongProfileController,
                    detail: "WKWebView carries a different profile WKWebExtensionController"
                )
            }
        }

        if webView.configuration.webExtensionController == nil {
            if extensionManager.canLateBindExtensionController(to: webView) == false {
                return classification(
                    .targetWebViewMissingExtensionController,
                    detail: "WKWebView on a loaded page cannot late-bind WKWebExtensionController"
                )
            }
            return classification(
                .targetWebViewMissingExtensionController,
                detail: "WKWebView is not configured with WKWebExtensionController"
            )
        }

        if extensionManager.extensionWebView(for: tab, extensionContext: extensionContext) == nil {
            return classification(
                .scriptingExecuteScriptTargetMissing,
                secondary: [.frameMappingMissing],
                detail: "extensionWebView preflight failed; scripting.executeScript and getAllFrames will fail"
            )
        }

        if installedExtension.manifestDeclaresScriptingPermission,
           extensionContext.webExtension.requestedPermissions
               .contains(where: { $0.rawValue == WKWebExtension.Permission.scripting.rawValue }) == false
        {
            return classification(
                .scriptingExecuteScriptTargetMissing,
                detail: "Extension declares scripting permission but WebKit has not granted it"
            )
        }

        return classification(
            .none,
            detail: "Tab WebView, adapter, and host permissions are wired for autofill content scripts"
        )
    }

    /// Production login pages are verification targets only after controlled local form + iframe pass.
    static func classifySiteSpecificURL(_: URL?) -> SafariExtensionAutofillBlocker? {
        nil
    }

    static func hostPermissionBlocker(
        for url: URL?,
        installedExtension: InstalledExtension,
        extensionContext: WKWebExtensionContext
    ) -> SafariExtensionAutofillBlocker? {
        guard let url else { return .hostPermissionDenied }

        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" || scheme == "file" else {
            return .hostPermissionDenied
        }

        if extensionContext.hasGrantedHostAccess(for: url) {
            return nil
        }

        if scheme == "file" {
            return .hostPermissionDenied
        }

        let manifest = installedExtension.manifest
        let permissions = (manifest["permissions"] as? [String] ?? [])
            + (manifest["optional_permissions"] as? [String] ?? [])
        if permissions.contains("activeTab") {
            return .activeTabPermissionMissing
        }

        return .hostPermissionDenied
    }

    private static func classification(
        _ primary: SafariExtensionAutofillBlocker,
        secondary: [SafariExtensionAutofillBlocker] = [],
        detail: String
    ) -> SafariExtensionAutofillClassification {
        SafariExtensionAutofillClassification(
            primaryBlocker: primary,
            secondaryBlockers: secondary,
            detail: detail
        )
    }

    private static func sanitizedURLShape(_ url: URL?) -> String {
        guard let url else { return "<nil>" }
        let scheme = url.scheme ?? "unknown"
        if scheme == "http" || scheme == "https" {
            return "\(scheme)://<host><redacted-path>"
        }
        return "\(scheme)://<redacted>"
    }
}

private extension InstalledExtension {
    var manifestDeclaresScriptingPermission: Bool {
        let permissions = (manifest["permissions"] as? [String] ?? [])
            + (manifest["optional_permissions"] as? [String] ?? [])
        return permissions.contains("scripting")
    }
}

private extension WKWebExtensionContext {
    func hasGrantedHostAccess(for url: URL) -> Bool {
        let status = permissionStatus(for: url)
        if status == .grantedExplicitly || status == .grantedImplicitly {
            return true
        }

        var grantedPatterns = Set(grantedPermissionMatchPatterns.keys)
        let declaredPatterns = webExtension
            .allRequestedMatchPatterns
            .union(webExtension.optionalPermissionMatchPatterns)
        for pattern in declaredPatterns {
            let patternStatus = permissionStatus(for: pattern)
            if patternStatus == .grantedExplicitly || patternStatus == .grantedImplicitly {
                grantedPatterns.insert(pattern)
            }
        }
        return grantedPatterns.contains { $0.matches(url) }
    }
}
