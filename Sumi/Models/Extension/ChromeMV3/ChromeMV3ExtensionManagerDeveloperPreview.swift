//
//  ChromeMV3ExtensionManagerDeveloperPreview.swift
//  Sumi
//
//  Developer-preview Chrome MV3 manager surface. This file is a control and
//  diagnostics layer only: it does not create WebKit extension runtime objects,
//  attach normal tabs, inject bridges, wake service workers, launch native
//  hosts, or enable product network enforcement.
//

import Foundation
import SwiftUI

enum ChromeMV3ExtensionManagerProductPreflightStatus:
    String,
    Codable,
    CaseIterable,
    Comparable
{
    case blocked
    case internalOnly
    case productEligible
    case productTestEnabled
    case unavailable

    static func < (
        lhs: ChromeMV3ExtensionManagerProductPreflightStatus,
        rhs: ChromeMV3ExtensionManagerProductPreflightStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ExtensionManagerActionKind:
    String,
    Codable,
    CaseIterable,
    Comparable
{
    case installUnpacked
    case importZipArchive
    case importCRXArchive
    case updateFromUnpacked
    case enableInternal
    case disableInternal
    case rebuild
    case retryDiagnostics
    case runDiagnostics
    case recover
    case uninstall
    case reset
    case openActionPopup
    case openOptions
    case closePopupOptions
    case exportDiagnosticsJSON
    case chromeWebStoreInstall

    static func < (
        lhs: ChromeMV3ExtensionManagerActionKind,
        rhs: ChromeMV3ExtensionManagerActionKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ExtensionManagerActionStatus:
    String,
    Codable,
    CaseIterable,
    Comparable
{
    case succeeded
    case failed
    case blocked
    case deferred

    static func < (
        lhs: ChromeMV3ExtensionManagerActionStatus,
        rhs: ChromeMV3ExtensionManagerActionStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ExtensionManagerBlockedDiagnosticCode:
    String,
    Codable,
    CaseIterable,
    Comparable
{
    case managerDeveloperPreviewUnavailable
    case moduleDisabled
    case installActionsUnavailable
    case runtimeActionsUnavailable
    case recordMissing
    case zipImportDeferred
    case crxImportDeferred
    case crxSignatureVerificationRequired
    case packageTrustBoundaryUnresolved
    case archiveExtractionPolicyMissing
    case chromeWebStoreInstallDeferred
    case chromeWebStoreInstallNotSupportedInThisBuild
    case chromeWebStoreInterceptionForbidden
    case remoteCRXDownloadForbidden
    case webStorePageInjectionForbidden
    case actionPopupUnavailable
    case optionsUIUnavailable
    case popupOptionsProductGateBlocked
    case popupOptionsExtensionDisabled
    case popupOptionsResourceBlocked
    case toolbarActionUIDeferred

    static func < (
        lhs: ChromeMV3ExtensionManagerBlockedDiagnosticCode,
        rhs: ChromeMV3ExtensionManagerBlockedDiagnosticCode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ExtensionManagerBlockedDiagnostic:
    Identifiable,
    Codable,
    Equatable
{
    var id: String { code.rawValue }
    var code: ChromeMV3ExtensionManagerBlockedDiagnosticCode
    var severity: ChromeMV3APIBlockerSeverity
    var message: String
    var remediation: String
    var documentationURL: String?

    static func make(
        _ code: ChromeMV3ExtensionManagerBlockedDiagnosticCode,
        severity: ChromeMV3APIBlockerSeverity,
        message: String,
        remediation: String,
        documentationURL: String? = nil
    ) -> ChromeMV3ExtensionManagerBlockedDiagnostic {
        ChromeMV3ExtensionManagerBlockedDiagnostic(
            code: code,
            severity: severity,
            message: message,
            remediation: remediation,
            documentationURL: documentationURL
        )
    }
}

struct ChromeMV3ExtensionManagerDocumentationSource:
    Identifiable,
    Codable,
    Equatable
{
    var id: String { url }
    var title: String
    var url: String
    var boundary: String
    var finding: String

    static let checkedSources: [ChromeMV3ExtensionManagerDocumentationSource] = [
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome load unpacked extension",
            url: "https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world#load-unpacked",
            boundary: "unpacked MV3 install",
            finding: "Chrome developer-mode load unpacked selects an extension directory; Sumi maps only this local directory flow to the internal lifecycle registry."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome manifest file format",
            url: "https://developer.chrome.com/docs/extensions/reference/manifest",
            boundary: "manifest validation",
            finding: "The manifest must be manifest.json in the root directory and manifest_version must be 3 for this product phase."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chromium CRX file component",
            url: "https://chromium.googlesource.com/chromium/src/+/HEAD/components/crx_file/README.md",
            boundary: "CRX trust boundary",
            finding: "A CRX is a ZIP archive with a prepended header and Chromium exposes verifier code for integrity checks; Sumi blocks CRX import until equivalent verification policy exists."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chromium CRX3 package format",
            url: "https://chromium.googlesource.com/chromium/src/+/HEAD/components/crx_file/crx3.proto",
            boundary: "CRX signature validation",
            finding: "CRX3 includes magic/version/header/archive fields and signatures over signed header data plus archive; Sumi parses the header/payload preflight and still blocks import until verifier and trust policy exist."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome alternative installation methods",
            url: "https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions",
            boundary: "Chrome Web Store and local CRX install",
            finding: "Chrome documents Chrome Web Store install as the normal user path and explicitly constrains local CRX installs on macOS; Sumi does not implement Web Store install here."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome inline installation deprecation FAQ",
            url: "https://developer.chrome.com/docs/extensions/mv2/inline-faq",
            boundary: "Web Store interception",
            finding: "Inline installation redirects/fails instead of installing directly; Sumi records Chrome Web Store install as deferred and does not inject or spoof Web Store pages."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome manifest content scripts",
            url: "https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts",
            boundary: "static content-script attachment",
            finding: "Static MV3 content_scripts define matches, CSS/JS order, run_at, all_frames, match_about_blank, match_origin_as_fallback, and execution world; Sumi supports only product-gated main-frame isolated-world JS in Prompt 61R."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome tabs API",
            url: "https://developer.chrome.com/docs/extensions/reference/api/tabs",
            boundary: "popup/options to content-script messaging",
            finding: "tabs.sendMessage and tabs.connect target content scripts by tab, optional frameId, and optional documentId; Sumi models these only against registered developer-preview endpoints."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome runtime API",
            url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
            boundary: "content-script MessageSender and Port metadata",
            finding: "runtime.MessageSender and Port metadata include extension, tab/frame/document context and URL/origin details; Sumi redacts URL/origin unless host access is present."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome scripting API",
            url: "https://developer.chrome.com/docs/extensions/reference/api/scripting",
            boundary: "dynamic scripting distinction",
            finding: "scripting.executeScript is a runtime injection API distinct from manifest static content scripts; Sumi keeps arbitrary product executeScript blocked."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Apple WKWebExtensionController header",
            url: "xcode://MacOSX.sdk/System/Library/Frameworks/WebKit.framework/Headers/WKWebExtensionController.h",
            boundary: "WebKit runtime attachment",
            finding: "The SDK header states the controller manages loaded extension contexts, load starts background content and injects content, and WKWebViewConfiguration.webExtensionController associates controllers with web views."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Apple WKWebExtensionContext header",
            url: "xcode://MacOSX.sdk/System/Library/Frameworks/WebKit.framework/Headers/WKWebExtensionContext.h",
            boundary: "WebKit runtime context",
            finding: "The SDK header models extension runtime environment and loaded state; manager viewing avoids context creation and loading."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Apple WKUserScript/WKContentWorld/WKUserContentController headers",
            url: "xcode://MacOSX.sdk/System/Library/Frameworks/WebKit.framework/Headers/",
            boundary: "WebKit user-script and content-world attachment",
            finding: "Local SDK headers expose WKUserScript injection times and named WKContentWorlds plus script message handlers, but no public per-extension user stylesheet removal API."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Apple WKNavigationDelegate/WKFrameInfo headers",
            url: "xcode://MacOSX.sdk/System/Library/Frameworks/WebKit.framework/Headers/",
            boundary: "normal-tab lifecycle and frame metadata",
            finding: "Local SDK headers expose navigation start/commit/finish/fail callbacks and WKFrameInfo main-frame/request/security-origin metadata; Sumi wires lifecycle entrypoints conservatively and blocks unsupported subframe attachment."
        ),
    ]
}

struct ChromeMV3ExtensionManagerGate: Codable, Equatable {
    var managerAvailableInDeveloperPreview: Bool
    var managerAvailableInPublicProduct: Bool
    var installActionsAvailable: Bool
    var runtimeActionsAvailable: Bool
    var webStoreInstallAvailable: Bool
    var localArchiveImportAvailable: Bool
    var developerPreviewOnly: Bool
    var diagnostics: [ChromeMV3ExtensionManagerBlockedDiagnostic]
    var documentationSources: [ChromeMV3ExtensionManagerDocumentationSource]

    static func evaluate(
        moduleEnabled: Bool
    ) -> ChromeMV3ExtensionManagerGate {
        #if DEBUG
            let developerPreviewAvailable =
                moduleEnabled && ChromeMV3InternalDiagnosticsGate.uiAvailable
        #else
            let developerPreviewAvailable = false
        #endif

        var diagnostics: [ChromeMV3ExtensionManagerBlockedDiagnostic] = []
        if moduleEnabled == false {
            diagnostics.append(.moduleDisabled)
        }
        if developerPreviewAvailable == false {
        diagnostics.append(.developerPreviewUnavailable)
        }
        diagnostics.append(.crxImportBlocked)
        diagnostics.append(
            contentsOf: ChromeMV3ExtensionManagerBlockedDiagnostic
                .chromeWebStoreDeferred
        )
        diagnostics.append(.runtimeActionsUnavailable)

        return ChromeMV3ExtensionManagerGate(
            managerAvailableInDeveloperPreview: developerPreviewAvailable,
            managerAvailableInPublicProduct: false,
            installActionsAvailable: developerPreviewAvailable,
            runtimeActionsAvailable: false,
            webStoreInstallAvailable: false,
            localArchiveImportAvailable: developerPreviewAvailable,
            developerPreviewOnly: true,
            diagnostics: uniqueDiagnostics(diagnostics),
            documentationSources:
                ChromeMV3ExtensionManagerDocumentationSource.checkedSources
        )
    }

    private static func uniqueDiagnostics(
        _ diagnostics: [ChromeMV3ExtensionManagerBlockedDiagnostic]
    ) -> [ChromeMV3ExtensionManagerBlockedDiagnostic] {
        var seen: Set<ChromeMV3ExtensionManagerBlockedDiagnosticCode> = []
        return diagnostics.filter {
            if seen.contains($0.code) { return false }
            seen.insert($0.code)
            return true
        }
        .sorted { $0.code < $1.code }
    }
}

extension ChromeMV3ExtensionManagerBlockedDiagnostic {
    static let moduleDisabled = make(
        .moduleDisabled,
        severity: .productBlocked,
        message: "The extensions module is disabled; developer-preview manager actions are blocked.",
        remediation: "Enable the internal extensions module before using the developer-preview manager."
    )

    static let developerPreviewUnavailable = make(
        .managerDeveloperPreviewUnavailable,
        severity: .deferred,
        message: "The Extension Manager is available only through DEBUG/internal developer-preview gating.",
        remediation: "Use an internal DEBUG build and keep public product availability false."
    )

    static let installActionsUnavailable = make(
        .installActionsUnavailable,
        severity: .productBlocked,
        message: "Install actions are blocked by the developer-preview manager gate.",
        remediation: "Keep install/import unavailable outside the explicit internal gate."
    )

    static let runtimeActionsUnavailable = make(
        .runtimeActionsUnavailable,
        severity: .productBlocked,
        message: "Runtime actions are unavailable; the manager cannot attach extensions to normal tabs.",
        remediation: "Use product runtime preflight diagnostics only. A separate runtime prompt is required before attachment."
    )

    static let recordMissing = make(
        .recordMissing,
        severity: .warning,
        message: "The requested internal MV3 lifecycle record was not found.",
        remediation: "Refresh the manager list or load an unpacked MV3 extension first."
    )

    static let archiveImportDeferred: [ChromeMV3ExtensionManagerBlockedDiagnostic] = [
        make(
            .zipImportDeferred,
            severity: .deferred,
            message: "Local .zip import is available only through controlled package intake in the internal developer-preview manager.",
            remediation: "Use Import ZIP so Sumi can preflight entries, reject unsafe archives, extract under the staging root, and validate MV3 before lifecycle promotion.",
            documentationURL:
                "https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world#load-unpacked"
        ),
        make(
            .archiveExtractionPolicyMissing,
            severity: .deferred,
            message: "Archive extraction must validate every entry before registry promotion.",
            remediation: "Implement extraction under a controlled staging root with no absolute paths, parent traversal, unsafe names, or symlinks."
        ),
        make(
            .crxImportDeferred,
            severity: .deferred,
            message: "Local .crx import is deferred because Sumi does not parse CRX headers or extract the embedded archive in this prompt.",
            remediation: "Implement CRX parsing and validation before promoting any archive contents.",
            documentationURL:
                "https://chromium.googlesource.com/chromium/src/+/HEAD/components/crx_file/README.md"
        ),
        make(
            .crxSignatureVerificationRequired,
            severity: .fatalInstall,
            message: "CRX signature verification is required before local CRX import can be trusted.",
            remediation: "Verify CRX3 signed header data and archive signatures before extraction or registry promotion.",
            documentationURL:
                "https://chromium.googlesource.com/chromium/src/+/HEAD/components/crx_file/crx3.proto"
        ),
        make(
            .packageTrustBoundaryUnresolved,
            severity: .productBlocked,
            message: "The local archive package trust boundary is unresolved for product use.",
            remediation: "Keep archives blocked until provenance, signing, extraction, and user-consent policy are explicit."
        ),
    ]

    static let crxImportBlocked = make(
        .crxImportDeferred,
        severity: .deferred,
        message: "Local .crx import is parser/preflight-only because CRX3 signature verification and package trust policy are not implemented.",
        remediation: "Use the CRX preflight diagnostic for metadata only; do not extract or install CRX payloads until verifier policy exists.",
        documentationURL:
            "https://chromium.googlesource.com/chromium/src/+/HEAD/components/crx_file/crx3.proto"
    )

    static let chromeWebStoreDeferred: [ChromeMV3ExtensionManagerBlockedDiagnostic] = [
        make(
            .chromeWebStoreInstallDeferred,
            severity: .deferred,
            message: "Chrome Web Store install is not implemented in this build.",
            remediation: "Use Load Unpacked for internal developer-preview testing. A separate future prompt is required for Web Store install.",
            documentationURL:
                "https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions"
        ),
        make(
            .chromeWebStoreInstallNotSupportedInThisBuild,
            severity: .deferred,
            message: "This build does not support Add to Chrome, update URL, or Web Store purchase/install flows.",
            remediation: "Do not claim Chrome Web Store support from this manager."
        ),
        make(
            .chromeWebStoreInterceptionForbidden,
            severity: .fatalRuntime,
            message: "Chrome Web Store interception or spoofing is forbidden.",
            remediation: "Do not inject into Chrome Web Store pages or intercept Add to Chrome."
        ),
        make(
            .remoteCRXDownloadForbidden,
            severity: .fatalInstall,
            message: "Remote CRX download from Google servers is forbidden in this prompt.",
            remediation: "Do not add automatic CRX download, update URL handling, or background update checks."
        ),
        make(
            .webStorePageInjectionForbidden,
            severity: .fatalRuntime,
            message: "Chrome Web Store page injection is forbidden.",
            remediation: "Keep Web Store diagnostics report-only and avoid page scripts."
        ),
    ]

    static let actionPopupUnavailable = make(
        .actionPopupUnavailable,
        severity: .productBlocked,
        message: "The action popup cannot open through the developer-preview product UI gate.",
        remediation: "Check action.default_popup, generated bundle availability, extension enabled state, and popup resource validation."
    )

    static let optionsUIUnavailable = make(
        .optionsUIUnavailable,
        severity: .productBlocked,
        message: "The options page cannot open through the developer-preview product UI gate.",
        remediation: "Check options_page/options_ui.page, generated bundle availability, extension enabled state, and options resource validation."
    )

    static let popupOptionsProductGateBlocked = make(
        .popupOptionsProductGateBlocked,
        severity: .productBlocked,
        message: "Popup/options product UI is gated to explicit internal developer preview.",
        remediation: "Keep public product availability false and open only from the developer-preview manager."
    )

    static let popupOptionsExtensionDisabled = make(
        .popupOptionsExtensionDisabled,
        severity: .productBlocked,
        message: "The internal extension record is disabled; popup/options UI will not create a WebView.",
        remediation: "Enable the internal extension record before opening popup/options pages."
    )

    static let popupOptionsResourceBlocked = make(
        .popupOptionsResourceBlocked,
        severity: .fatalRuntime,
        message: "Popup/options resource validation failed.",
        remediation: "Fix missing, unsafe, remote, or dynamic popup/options resources before opening the UI."
    )

    static let toolbarActionUIDeferred = make(
        .toolbarActionUIDeferred,
        severity: .deferred,
        message: "The extension toolbar action placeholder is deferred in this build.",
        remediation: "Use the Extension Manager detail controls; do not expose a public extension toolbar claim."
    )
}

enum ChromeMV3ExtensionManagerStoreLocation {
    static func defaultRootURL(
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent(
                SumiAppIdentity.runtimeBundleIdentifier,
                isDirectory: true
            )
            .appendingPathComponent(
                "ChromeMV3DeveloperPreview",
                isDirectory: true
            )
    }

    static func ensureDefaultRootURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = defaultRootURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }
}

struct ChromeMV3ExtensionManagerSeverityCount:
    Identifiable,
    Codable,
    Equatable
{
    var id: ChromeMV3APIBlockerSeverity { severity }
    var severity: ChromeMV3APIBlockerSeverity
    var count: Int
}

struct ChromeMV3ExtensionManagerGeneratedBundleSummary:
    Codable,
    Equatable
{
    var activeVersionID: String?
    var previousWorkingVersionID: String?
    var candidateVersionID: String?
    var versionCount: Int
    var failedCandidateCount: Int
    var generatedBundleAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3ExtensionManagerActionDescriptor:
    Identifiable,
    Codable,
    Equatable
{
    var id: ChromeMV3ExtensionManagerActionKind { action }
    var action: ChromeMV3ExtensionManagerActionKind
    var title: String
    var available: Bool
    var mutatesLifecycle: Bool
    var runtimeAction: Bool
    var unavailableDiagnostics: [ChromeMV3ExtensionManagerBlockedDiagnostic]
}

struct ChromeMV3ExtensionManagerListItem:
    Identifiable,
    Codable,
    Equatable
{
    var id: String { "\(profileID):\(extensionID)" }
    var profileID: String
    var extensionID: String
    var name: String
    var version: String
    var lifecycleState: ChromeMV3LifecycleState
    var internalEnabled: Bool
    var sourceKind: ChromeMV3PackageSourceKind
    var sourcePath: String
    var generatedBundleSummary: ChromeMV3ExtensionManagerGeneratedBundleSummary
    var compatibilitySeveritySummary: [ChromeMV3ExtensionManagerSeverityCount]
    var productPreflightStatus:
        ChromeMV3ExtensionManagerProductPreflightStatus
    var lastDiagnosticsGeneratedAt: Date?
    var lastDiagnosticsSequence: Int
    var blockerCountBySeverity: [ChromeMV3ExtensionManagerSeverityCount]
}

struct ChromeMV3ExtensionManagerListViewModel:
    Codable,
    Equatable
{
    static let schemaVersion = 1

    var schemaVersion: Int
    var generatedAt: Date
    var gate: ChromeMV3ExtensionManagerGate
    var items: [ChromeMV3ExtensionManagerListItem]
    var unsupportedArchiveDiagnostics:
        [ChromeMV3ExtensionManagerBlockedDiagnostic]
    var chromeWebStoreDiagnostics:
        [ChromeMV3ExtensionManagerBlockedDiagnostic]
    var packageIntakeReport: ChromeMV3PackageIntakeReport?
    var documentationSources: [ChromeMV3ExtensionManagerDocumentationSource]
}

struct ChromeMV3ExtensionManagerManifestSummaryViewState:
    Codable,
    Equatable
{
    var manifestVersion: Int?
    var name: String
    var version: String
    var description: String?
    var backgroundServiceWorker: String?
    var permissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var contentScriptCount: Int
    var hasAction: Bool
    var hasOptionsPage: Bool
    var hasDeclarativeNetRequest: Bool
    var hasSidePanel: Bool

    static func make(
        summary: ChromeMV3ManifestSummary?,
        record: ChromeMV3ExtensionLifecycleRecord?
    ) -> ChromeMV3ExtensionManagerManifestSummaryViewState {
        ChromeMV3ExtensionManagerManifestSummaryViewState(
            manifestVersion: summary?.manifestVersion,
            name: summary?.name ?? record?.displayName
                ?? "Unknown internal MV3 extension",
            version: summary?.version ?? record?.displayVersion ?? "unknown",
            description: summary?.description,
            backgroundServiceWorker: summary?.backgroundServiceWorker,
            permissions: summary?.permissions ?? [],
            optionalPermissions: summary?.optionalPermissions ?? [],
            hostPermissions: summary?.hostPermissions ?? [],
            optionalHostPermissions: summary?.optionalHostPermissions ?? [],
            contentScriptCount: summary?.contentScriptCount ?? 0,
            hasAction: summary?.hasAction ?? false,
            hasOptionsPage: summary?.hasOptionsPage ?? false,
            hasDeclarativeNetRequest:
                summary?.hasDeclarativeNetRequest ?? false,
            hasSidePanel: summary?.hasSidePanel ?? false
        )
    }
}

struct ChromeMV3ExtensionManagerPermissionStatePanel:
    Codable,
    Equatable,
    Sendable
{
    var requiredPermissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var grantedOptionalPermissions: [String]
    var grantedOptionalHostPermissions: [String]
    var deniedPermissions: [String]
    var revokedPermissions: [String]
    var dismissedPromptRequestIDs: [String]
    var activeTabCurrentGrants: [String]
    var promptGate:
        ChromeMV3PermissionPromptGateRecord
    var blockedPromptReasons: [String]
    var diagnostics: [String]

    static func make(
        rootURL: URL,
        record: ChromeMV3ExtensionLifecycleRecord,
        manifestSummary:
            ChromeMV3ExtensionManagerManifestSummaryViewState,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerPermissionStatePanel {
        let promptGate = ChromeMV3PermissionPromptGateRecord.evaluate(
            moduleEnabled: gate.managerAvailableInDeveloperPreview,
            extensionEnabled: record.runtimeState.internalRuntimeEnabled,
            developerPreviewGate: gate.managerAvailableInDeveloperPreview,
            publicProductGate: false
        )
        let store = ChromeMV3DeveloperPreviewPermissionStateStore(
            rootURL: rootURL
        )
        let persisted = store.loadRecord(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let summary = persisted?.permissionRuntimeSnapshot.permissionStore
            .summary
        let activeTab = persisted?.permissionRuntimeSnapshot.activeTabStore
            .summary
        let deniedFromPrompts =
            persisted?.promptResults
            .filter { $0.disposition == .denied }
            .flatMap {
                $0.requestedAPIPermissions + $0.requestedHostPermissions
                    + $0.requestedOptionalOrigins
            } ?? []
        let dismissedPromptIDs =
            persisted?.promptResults
            .filter { $0.disposition == .dismissed }
            .map(\.requestID) ?? []
        let blockedPromptReasons = promptGate.blockers.map(\.diagnostic)
        return ChromeMV3ExtensionManagerPermissionStatePanel(
            requiredPermissions: manifestSummary.permissions,
            optionalPermissions: manifestSummary.optionalPermissions,
            hostPermissions: manifestSummary.hostPermissions,
            optionalHostPermissions: manifestSummary.optionalHostPermissions,
            grantedOptionalPermissions:
                summary?.grantedOptionalAPIPermissions ?? [],
            grantedOptionalHostPermissions:
                summary?.grantedOptionalHostPermissions ?? [],
            deniedPermissions:
                uniqueSortedExtensionManager(
                    (summary?.deniedPermissions ?? []) + deniedFromPrompts
                ),
            revokedPermissions: summary?.revokedPermissions ?? [],
            dismissedPromptRequestIDs:
                uniqueSortedExtensionManager(dismissedPromptIDs),
            activeTabCurrentGrants: activeTab?.activeGrantScopes ?? [],
            promptGate: persisted?.promptGateRecord ?? promptGate,
            blockedPromptReasons:
                uniqueSortedExtensionManager(blockedPromptReasons),
            diagnostics:
                uniqueSortedExtensionManager(
                    (persisted?.diagnostics ?? [])
                        + promptGate.diagnostics
                        + [
                            persisted == nil
                                ? "No persisted developer-preview permission decisions are recorded for this extension."
                                : "Developer-preview permission decisions were loaded from the internal sidecar store.",
                            "Permission state panel does not construct ExtensionManager runtime controllers.",
                            "silentGrantAllowed is false.",
                        ]
                )
        )
    }
}

struct ChromeMV3ExtensionManagerDetailViewModel:
    Identifiable,
    Codable,
    Equatable
{
    var id: String { listItem.id }
    var gate: ChromeMV3ExtensionManagerGate
    var listItem: ChromeMV3ExtensionManagerListItem
    var manifestSummary:
        ChromeMV3ExtensionManagerManifestSummaryViewState
    var lifecycleRecord: ChromeMV3ExtensionLifecycleRecord
    var generatedBundleState: ChromeMV3GeneratedBundleViewState
    var compatibilityReport: ChromeMV3CompatibilityReportViewModel?
    var productEnablementPreflight:
        ChromeMV3ProductEnablementPreflightSection
    var apiSupportMatrix: [ChromeMV3CompatibilityAPIMatrixRow]
    var blockersBySeverity: [ChromeMV3CompatibilityBlockerGroup]
    var blockersBySource: [ChromeMV3CompatibilityBlockerGroup]
    var blockersByAPI: [ChromeMV3CompatibilityBlockerGroup]
    var exactCompatibilityBlockers: [ChromeMV3APIBlockerRecord]
    var exactProductPreflightBlockers:
        [ChromeMV3ProductRuntimePreflightBlocker]
    var packageIntakeReport: ChromeMV3PackageIntakeReport?
    var popupOptionsLaunchState: ChromeMV3ProductPopupOptionsLaunchState
    var permissionStatePanel:
        ChromeMV3ExtensionManagerPermissionStatePanel
    var actions: [ChromeMV3ExtensionManagerActionDescriptor]
    var diagnosticsReportPath: String?
    var diagnosticsJSONAvailable: Bool
    var documentationSources: [ChromeMV3ExtensionManagerDocumentationSource]
}

struct ChromeMV3ExtensionManagerActionResult:
    Codable,
    Equatable
{
    var action: ChromeMV3ExtensionManagerActionKind
    var status: ChromeMV3ExtensionManagerActionStatus
    var lifecycleOperationResult: ChromeMV3LifecycleOperationResult?
    var report: ChromeMV3EndToEndInstallDiagnosticsReport?
    var packageIntakeReport: ChromeMV3PackageIntakeReport?
    var popupOptionsRunResult: ChromeMV3ProductPopupOptionsRunResult?
    var diagnosticsJSON: String?
    var blockedDiagnostics: [ChromeMV3ExtensionManagerBlockedDiagnostic]
    var diagnostics: [String]
    var productFlags: ChromeMV3LifecycleProductFlags
    var mutatedLifecycle: Bool
    var runtimeAttachmentAttempted: Bool
    var runtimeObjectsCreated: Bool
    var serviceWorkerWakeAttempted: Bool
    var nativeHostLaunchAttempted: Bool

    var succeeded: Bool {
        status == .succeeded
    }

    static func fromLifecycle(
        action: ChromeMV3ExtensionManagerActionKind,
        result: ChromeMV3LifecycleOperationResult,
        packageIntakeReport: ChromeMV3PackageIntakeReport? = nil
    ) -> ChromeMV3ExtensionManagerActionResult {
        ChromeMV3ExtensionManagerActionResult(
            action: action,
            status: result.succeeded ? .succeeded : .failed,
            lifecycleOperationResult: result,
            report: result.report,
            packageIntakeReport: packageIntakeReport,
            popupOptionsRunResult: nil,
            diagnosticsJSON: nil,
            blockedDiagnostics: [],
            diagnostics: result.diagnostics,
            productFlags: result.productFlags,
            mutatedLifecycle: true,
            runtimeAttachmentAttempted: false,
            runtimeObjectsCreated: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false
        )
    }

    static func blocked(
        action: ChromeMV3ExtensionManagerActionKind,
        diagnostics: [ChromeMV3ExtensionManagerBlockedDiagnostic],
        status: ChromeMV3ExtensionManagerActionStatus = .blocked
    ) -> ChromeMV3ExtensionManagerActionResult {
        ChromeMV3ExtensionManagerActionResult(
            action: action,
            status: status,
            lifecycleOperationResult: nil,
            report: nil,
            packageIntakeReport: nil,
            popupOptionsRunResult: nil,
            diagnosticsJSON: nil,
            blockedDiagnostics: diagnostics.sorted { $0.code < $1.code },
            diagnostics: diagnostics.map(\.message).sorted(),
            productFlags: .unavailable,
            mutatedLifecycle: false,
            runtimeAttachmentAttempted: false,
            runtimeObjectsCreated: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false
        )
    }

    static func diagnostics(
        action: ChromeMV3ExtensionManagerActionKind,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?
    ) -> ChromeMV3ExtensionManagerActionResult {
        ChromeMV3ExtensionManagerActionResult(
            action: action,
            status: report == nil ? .failed : .succeeded,
            lifecycleOperationResult: nil,
            report: report,
            packageIntakeReport: nil,
            popupOptionsRunResult: nil,
            diagnosticsJSON: nil,
            blockedDiagnostics: [],
            diagnostics: [
                report == nil
                    ? "No diagnostics report was available."
                    : "End-to-end internal MV3 diagnostics refreshed.",
            ],
            productFlags: .unavailable,
            mutatedLifecycle: report != nil,
            runtimeAttachmentAttempted: false,
            runtimeObjectsCreated: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false
        )
    }

    static func exportedJSON(
        _ json: String?
    ) -> ChromeMV3ExtensionManagerActionResult {
        ChromeMV3ExtensionManagerActionResult(
            action: .exportDiagnosticsJSON,
            status: json == nil ? .failed : .succeeded,
            lifecycleOperationResult: nil,
            report: nil,
            packageIntakeReport: nil,
            popupOptionsRunResult: nil,
            diagnosticsJSON: json,
            blockedDiagnostics: [],
            diagnostics: [
                json == nil
                    ? "No diagnostics JSON was available to export."
                    : "Diagnostics JSON is available for copy/export.",
            ],
            productFlags: .unavailable,
            mutatedLifecycle: false,
            runtimeAttachmentAttempted: false,
            runtimeObjectsCreated: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false
        )
    }

    static func packageIntake(
        action: ChromeMV3ExtensionManagerActionKind,
        status: ChromeMV3ExtensionManagerActionStatus,
        report: ChromeMV3PackageIntakeReport
    ) -> ChromeMV3ExtensionManagerActionResult {
        ChromeMV3ExtensionManagerActionResult(
            action: action,
            status: status,
            lifecycleOperationResult: nil,
            report: nil,
            packageIntakeReport: report,
            popupOptionsRunResult: nil,
            diagnosticsJSON: nil,
            blockedDiagnostics: [],
            diagnostics: (
                report.blockers.isEmpty
                    ? [report.preflightResult.message]
                    : report.blockers
            ).sorted(),
            productFlags: .unavailable,
            mutatedLifecycle: false,
            runtimeAttachmentAttempted: false,
            runtimeObjectsCreated: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false
        )
    }

    static func popupOptions(
        action: ChromeMV3ExtensionManagerActionKind,
        result: ChromeMV3ProductPopupOptionsRunResult
    ) -> ChromeMV3ExtensionManagerActionResult {
        ChromeMV3ExtensionManagerActionResult(
            action: action,
            status: {
                switch result.status {
                case .succeeded:
                    return .succeeded
                case .blocked:
                    return .blocked
                case .failed:
                    return .failed
                }
            }(),
            lifecycleOperationResult: nil,
            report: nil,
            packageIntakeReport: nil,
            popupOptionsRunResult: result,
            diagnosticsJSON: nil,
            blockedDiagnostics: popupOptionsDiagnostics(
                action: action,
                result: result
            ),
            diagnostics: result.diagnostics,
            productFlags: .unavailable,
            mutatedLifecycle: false,
            runtimeAttachmentAttempted: false,
            runtimeObjectsCreated: false,
            serviceWorkerWakeAttempted: result.serviceWorkerWakeAttempted,
            nativeHostLaunchAttempted: result.nativeHostLaunchAttempted
        )
    }

    private static func popupOptionsDiagnostics(
        action: ChromeMV3ExtensionManagerActionKind,
        result: ChromeMV3ProductPopupOptionsRunResult
    ) -> [ChromeMV3ExtensionManagerBlockedDiagnostic] {
        guard result.status != .succeeded else { return [] }
        var diagnostics: [ChromeMV3ExtensionManagerBlockedDiagnostic] = []
        switch action {
        case .openActionPopup:
            diagnostics.append(.actionPopupUnavailable)
        case .openOptions:
            diagnostics.append(.optionsUIUnavailable)
        case .closePopupOptions:
            break
        default:
            break
        }
        let blockers = result.launchRecord?.blockers ?? []
        if blockers.contains(.extensionDisabled) {
            diagnostics.append(.popupOptionsExtensionDisabled)
        }
        if blockers.contains(.productGateBlocked)
            || blockers.contains(.developerPreviewGateBlocked)
        {
            diagnostics.append(.popupOptionsProductGateBlocked)
        }
        if blockers.contains(.unsafePagePath)
            || blockers.contains(.missingPageResource)
            || blockers.contains(.unsafePageHTML)
        {
            diagnostics.append(.popupOptionsResourceBlocked)
        }
        return diagnostics.sorted { $0.code < $1.code }
    }
}

enum ChromeMV3ExtensionManagerViewModelBuilder {
    static func makeListViewModel(
        rootURL: URL,
        gate: ChromeMV3ExtensionManagerGate,
        now: Date = Date()
    ) -> ChromeMV3ExtensionManagerListViewModel {
        let registry = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
        let items = registry.listLifecycleRecords().map { record in
            let report = registry.latestEndToEndDiagnosticsReport(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
            return makeListItem(
                record: record,
                report: report,
                gate: gate
            )
        }
        return ChromeMV3ExtensionManagerListViewModel(
            schemaVersion: ChromeMV3ExtensionManagerListViewModel.schemaVersion,
            generatedAt: now,
            gate: gate,
            items: items.sorted {
                if $0.profileID != $1.profileID {
                    return $0.profileID < $1.profileID
                }
                if $0.name != $1.name {
                    return $0.name < $1.name
                }
                return $0.extensionID < $1.extensionID
            },
            unsupportedArchiveDiagnostics:
                [
                    ChromeMV3ExtensionManagerBlockedDiagnostic.crxImportBlocked,
                ],
            chromeWebStoreDiagnostics:
                ChromeMV3ExtensionManagerBlockedDiagnostic.chromeWebStoreDeferred,
            packageIntakeReport:
                ChromeMV3PackageIntakeService.latestReport(rootURL: rootURL),
            documentationSources: gate.documentationSources
        )
    }

    static func makeDetailViewModel(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerDetailViewModel? {
        let registry = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
        guard
            let record = registry.loadLifecycleRecord(
                profileID: profileID,
                extensionID: extensionID
            )
        else {
            return nil
        }

        let report = registry.latestEndToEndDiagnosticsReport(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let compatibility = report.map {
            ChromeMV3CompatibilityReportViewModel(
                report: $0,
                lifecycleRecord: record
            )
        }
        let preflight = ChromeMV3ProductEnablementPreflightSection.make(
            report: report,
            lifecycleRecord: record
        )
        let listItem = makeListItem(
            record: record,
            report: report,
            gate: gate
        )
        let popupOptions = ChromeMV3ProductPopupOptionsLaunchPlanner
            .makeLaunchState(
                rootURL: rootURL,
                profileID: record.profileID,
                extensionID: record.extensionID,
                managerGate: gate,
                moduleEnabled: gate.managerAvailableInDeveloperPreview
                    || gate.installActionsAvailable
            )
        let manifestSummary = ChromeMV3ExtensionManagerManifestSummaryViewState
            .make(
                summary: report?.managerActiveManifestSummary,
                record: record
            )

        return ChromeMV3ExtensionManagerDetailViewModel(
            gate: gate,
            listItem: listItem,
            manifestSummary: manifestSummary,
            lifecycleRecord: record,
            generatedBundleState:
                compatibility?.generatedBundleState
                    ?? generatedBundleState(record: record),
            compatibilityReport: compatibility,
            productEnablementPreflight: preflight,
            apiSupportMatrix: compatibility?.apiSupportMatrix ?? [],
            blockersBySeverity: compatibility?.blockersBySeverity ?? [],
            blockersBySource: compatibility?.blockersBySource ?? [],
            blockersByAPI: compatibility?.blockersByAPI ?? [],
            exactCompatibilityBlockers: report?.blockerTaxonomy ?? [],
            exactProductPreflightBlockers:
                preflight.normalTabPreflight.blockers,
            packageIntakeReport:
                ChromeMV3PackageIntakeService.latestReport(rootURL: rootURL),
            popupOptionsLaunchState: popupOptions,
            permissionStatePanel:
                ChromeMV3ExtensionManagerPermissionStatePanel.make(
                    rootURL: rootURL,
                    record: record,
                    manifestSummary: manifestSummary,
                    gate: gate
                ),
            actions: actionDescriptors(
                gate: gate,
                record: record,
                report: report,
                popupOptionsLaunchState: popupOptions
            ),
            diagnosticsReportPath: record.reportPaths.compatibilityReportPath,
            diagnosticsJSONAvailable:
                registry.exportLatestEndToEndDiagnosticsJSON(
                    profileID: record.profileID,
                    extensionID: record.extensionID
                ) != nil,
            documentationSources: gate.documentationSources
        )
    }

    private static func makeListItem(
        record: ChromeMV3ExtensionLifecycleRecord,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerListItem {
        let preflight = ChromeMV3ProductEnablementPreflightSection.make(
            report: report,
            lifecycleRecord: record
        )
        let counts = severityCounts(report?.blockerTaxonomy ?? [])
        return ChromeMV3ExtensionManagerListItem(
            profileID: record.profileID,
            extensionID: record.extensionID,
            name: record.displayName,
            version: record.displayVersion,
            lifecycleState: record.lifecycleState,
            internalEnabled: record.runtimeState.internalRuntimeEnabled,
            sourceKind: record.sourceKind,
            sourcePath: record.sourcePath,
            generatedBundleSummary: generatedBundleSummary(record: record),
            compatibilitySeveritySummary: counts,
            productPreflightStatus: productStatus(
                gate: gate,
                preflight: preflight
            ),
            lastDiagnosticsGeneratedAt: report?.generatedAt,
            lastDiagnosticsSequence: record.sequence,
            blockerCountBySeverity: counts
        )
    }

    private static func productStatus(
        gate: ChromeMV3ExtensionManagerGate,
        preflight: ChromeMV3ProductEnablementPreflightSection
    ) -> ChromeMV3ExtensionManagerProductPreflightStatus {
        guard gate.managerAvailableInDeveloperPreview else {
            return .unavailable
        }
        if preflight.normalTabPreflight.canAttachToNormalTabNow {
            return preflight.extensionProductEnablement.state
                == .productTestEnabled ? .productTestEnabled : .productEligible
        }
        if preflight.extensionProductEnablement.state == .internalOnly {
            return .internalOnly
        }
        return .blocked
    }

    private static func generatedBundleSummary(
        record: ChromeMV3ExtensionLifecycleRecord
    ) -> ChromeMV3ExtensionManagerGeneratedBundleSummary {
        let failedCandidateCount = record.generatedBundleVersions.filter {
            $0.state == .failed || $0.state == .candidate
        }.count
        let active = record.activeGeneratedVersionID.flatMap { activeID in
            record.generatedBundleVersions.first { $0.id == activeID }
        }
        return ChromeMV3ExtensionManagerGeneratedBundleSummary(
            activeVersionID: record.activeGeneratedVersionID,
            previousWorkingVersionID: record.previousWorkingGeneratedVersionID,
            candidateVersionID: record.candidateGeneratedVersionID,
            versionCount: record.generatedBundleVersions.count,
            failedCandidateCount: failedCandidateCount,
            generatedBundleAvailable: active != nil,
            runtimeLoadable: active?.runtimeLoadable ?? false
        )
    }

    private static func generatedBundleState(
        record: ChromeMV3ExtensionLifecycleRecord
    ) -> ChromeMV3GeneratedBundleViewState {
        let versions = record.generatedBundleVersions.map {
            ChromeMV3GeneratedBundleVersionViewState(
                id: $0.id,
                sequence: $0.sequence,
                state: $0.state,
                versionRootPath: $0.versionRootPath,
                generatedBundleRootPath: $0.generatedBundleRootPath,
                rewrittenVariantRootPath: $0.rewrittenVariantRootPath,
                runtimeLoadabilityReportPath: $0.runtimeLoadabilityReportPath,
                runtimeLoadable: $0.runtimeLoadable,
                isActive: $0.id == record.activeGeneratedVersionID,
                isPreviousWorking:
                    $0.id == record.previousWorkingGeneratedVersionID,
                isCandidate: $0.id == record.candidateGeneratedVersionID
            )
        }
        return ChromeMV3GeneratedBundleViewState(
            activeVersionID: record.activeGeneratedVersionID,
            previousWorkingVersionID: record.previousWorkingGeneratedVersionID,
            candidateVersionID: record.candidateGeneratedVersionID,
            versions: versions.sorted { $0.sequence < $1.sequence },
            generatedBundleAvailable: record.activeGeneratedVersionID != nil,
            failedCandidateCount: versions.filter {
                $0.state == .failed || $0.state == .candidate
            }.count
        )
    }

    private static func severityCounts(
        _ blockers: [ChromeMV3APIBlockerRecord]
    ) -> [ChromeMV3ExtensionManagerSeverityCount] {
        let grouped = Dictionary(grouping: blockers, by: \.severity)
        return grouped.map {
            ChromeMV3ExtensionManagerSeverityCount(
                severity: $0.key,
                count: $0.value.count
            )
        }
        .sorted { $0.severity < $1.severity }
    }

    static func actionDescriptors(
        gate: ChromeMV3ExtensionManagerGate,
        record: ChromeMV3ExtensionLifecycleRecord?,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        popupOptionsLaunchState:
            ChromeMV3ProductPopupOptionsLaunchState? = nil
    ) -> [ChromeMV3ExtensionManagerActionDescriptor] {
        let installed = record != nil && record?.lifecycleState != .uninstalled
        let enabled = record?.runtimeState.internalRuntimeEnabled == true
        return ChromeMV3ExtensionManagerActionKind.allCases.sorted().map {
            action in
            descriptor(
                action: action,
                gate: gate,
                installed: installed,
                enabled: enabled,
                reportAvailable: report != nil,
                popupOptionsLaunchState: popupOptionsLaunchState
            )
        }
    }

    private static func descriptor(
        action: ChromeMV3ExtensionManagerActionKind,
        gate: ChromeMV3ExtensionManagerGate,
        installed: Bool,
        enabled: Bool,
        reportAvailable: Bool,
        popupOptionsLaunchState:
            ChromeMV3ProductPopupOptionsLaunchState?
    ) -> ChromeMV3ExtensionManagerActionDescriptor {
        let runtimeAction = action == .chromeWebStoreInstall
        let mutates = mutatesLifecycle(action)
        let archiveDiagnostics:
            [ChromeMV3ExtensionManagerBlockedDiagnostic]
        if action == .importCRXArchive {
            archiveDiagnostics =
                [
                    ChromeMV3ExtensionManagerBlockedDiagnostic.crxImportBlocked,
                    ChromeMV3ExtensionManagerBlockedDiagnostic
                        .archiveImportDeferred[3],
                    ChromeMV3ExtensionManagerBlockedDiagnostic
                        .archiveImportDeferred[4],
                ]
        } else if action == .chromeWebStoreInstall {
            archiveDiagnostics =
                ChromeMV3ExtensionManagerBlockedDiagnostic.chromeWebStoreDeferred
        } else {
            archiveDiagnostics = []
        }

        var unavailable: [ChromeMV3ExtensionManagerBlockedDiagnostic] = []
        if gate.managerAvailableInDeveloperPreview == false {
            unavailable.append(.developerPreviewUnavailable)
        }
        if mutates && gate.installActionsAvailable == false {
            unavailable.append(.installActionsUnavailable)
        }
        if action == .importZipArchive && gate.localArchiveImportAvailable == false {
            unavailable.append(
                ChromeMV3ExtensionManagerBlockedDiagnostic
                    .archiveImportDeferred[0]
            )
        }
        if runtimeAction && gate.runtimeActionsAvailable == false {
            unavailable.append(.runtimeActionsUnavailable)
        }
        unavailable.append(contentsOf: archiveDiagnostics)
        if requiresInstalledRecord(action) && installed == false {
            unavailable.append(.recordMissing)
        }
        if action == .enableInternal && enabled {
            unavailable.append(
                .make(
                    .recordMissing,
                    severity: .info,
                    message: "The internal extension record is already enabled.",
                    remediation: "Use Disable if you need to change the registry state."
                )
            )
        }
        if action == .disableInternal && !enabled && installed {
            unavailable.append(
                .make(
                    .recordMissing,
                    severity: .info,
                    message: "The internal extension record is already disabled.",
                    remediation: "Use Enable if you need to change the registry state."
                )
            )
        }
        if action == .exportDiagnosticsJSON && reportAvailable == false {
            unavailable.append(.recordMissing)
        }
        if action == .openActionPopup {
            if enabled == false && installed {
                unavailable.append(.popupOptionsExtensionDisabled)
            }
            if popupOptionsLaunchState?.actionPopup.canOpen != true {
                unavailable.append(.actionPopupUnavailable)
                appendPopupOptionsResourceDiagnostic(
                    popupOptionsLaunchState?.actionPopup,
                    to: &unavailable
                )
            }
        }
        if action == .openOptions {
            if enabled == false && installed {
                unavailable.append(.popupOptionsExtensionDisabled)
            }
            if popupOptionsLaunchState?.primaryOptions?.canOpen != true {
                unavailable.append(.optionsUIUnavailable)
                appendPopupOptionsResourceDiagnostic(
                    popupOptionsLaunchState?.primaryOptions,
                    to: &unavailable
                )
            }
        }
        if action == .closePopupOptions && installed == false {
            unavailable.append(.recordMissing)
        }

        return ChromeMV3ExtensionManagerActionDescriptor(
            action: action,
            title: title(for: action),
            available: unavailable.isEmpty,
            mutatesLifecycle: mutates,
            runtimeAction: runtimeAction,
            unavailableDiagnostics: unavailable.sorted { $0.code < $1.code }
        )
    }

    private static func appendPopupOptionsResourceDiagnostic(
        _ record: ChromeMV3ProductPopupOptionsLaunchRecord?,
        to diagnostics: inout [ChromeMV3ExtensionManagerBlockedDiagnostic]
    ) {
        guard let blockers = record?.blockers else {
            diagnostics.append(.popupOptionsProductGateBlocked)
            return
        }
        if blockers.contains(.productGateBlocked)
            || blockers.contains(.developerPreviewGateBlocked)
        {
            diagnostics.append(.popupOptionsProductGateBlocked)
        }
        if blockers.contains(.unsafePagePath)
            || blockers.contains(.missingPageResource)
            || blockers.contains(.unsafePageHTML)
            || blockers.contains(.bridgeUnavailableForPageAPI)
        {
            diagnostics.append(.popupOptionsResourceBlocked)
        }
    }

    private static func mutatesLifecycle(
        _ action: ChromeMV3ExtensionManagerActionKind
    ) -> Bool {
        switch action {
        case .installUnpacked, .updateFromUnpacked, .enableInternal,
             .disableInternal, .rebuild, .retryDiagnostics,
             .runDiagnostics, .recover, .uninstall, .reset,
             .importZipArchive:
            return true
        case .importCRXArchive, .openActionPopup, .openOptions,
             .closePopupOptions, .exportDiagnosticsJSON,
             .chromeWebStoreInstall:
            return false
        }
    }

    private static func requiresInstalledRecord(
        _ action: ChromeMV3ExtensionManagerActionKind
    ) -> Bool {
        switch action {
        case .enableInternal, .disableInternal, .updateFromUnpacked,
             .rebuild, .retryDiagnostics, .runDiagnostics, .recover,
             .uninstall, .reset, .openActionPopup, .openOptions,
             .closePopupOptions, .exportDiagnosticsJSON:
            return true
        case .installUnpacked, .importZipArchive, .importCRXArchive,
             .chromeWebStoreInstall:
            return false
        }
    }

    private static func title(
        for action: ChromeMV3ExtensionManagerActionKind
    ) -> String {
        switch action {
        case .installUnpacked:
            return "Load Unpacked"
        case .importZipArchive:
            return "Import ZIP"
        case .importCRXArchive:
            return "Import CRX"
        case .updateFromUnpacked:
            return "Update From Local Source"
        case .enableInternal:
            return "Enable Internal Record"
        case .disableInternal:
            return "Disable Internal Record"
        case .rebuild:
            return "Rebuild Generated Bundle"
        case .retryDiagnostics:
            return "Retry Diagnostics"
        case .runDiagnostics:
            return "Run Diagnostics"
        case .recover:
            return "Recover"
        case .uninstall:
            return "Uninstall"
        case .reset:
            return "Reset Internal State"
        case .openActionPopup:
            return "Open Action Popup"
        case .openOptions:
            return "Open Options"
        case .closePopupOptions:
            return "Close Popup/Options"
        case .exportDiagnosticsJSON:
            return "Copy Diagnostics JSON"
        case .chromeWebStoreInstall:
            return "Chrome Web Store Install"
        }
    }
}

enum ChromeMV3ExtensionManagerActionRunner {
    static func installUnpacked(
        rootURL: URL,
        sourceURL: URL,
        profileID: String,
        enableInternal: Bool,
        gate: ChromeMV3ExtensionManagerGate,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard gate.installActionsAvailable else {
            return .blocked(
                action: .installUnpacked,
                diagnostics: [.installActionsUnavailable]
            )
        }
        let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            .installUnpackedExtension(
                at: sourceURL,
                profileID: profileID,
                enableInternal: enableInternal,
                runtimeDiagnostics: runtimeDiagnostics
            )
        let packageReport = ChromeMV3PackageIntakeService(rootURL: rootURL)
            .writeLocalUnpackedReport(
                sourceURL: sourceURL,
                lifecycleResult: result
            )
        return .fromLifecycle(
            action: .installUnpacked,
            result: result,
            packageIntakeReport: packageReport
        )
    }

    static func importLocalArchive(
        rootURL: URL,
        sourceURL: URL,
        profileID: String,
        enableInternal: Bool,
        gate: ChromeMV3ExtensionManagerGate,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard gate.installActionsAvailable else {
            return .blocked(
                action: sourceURL.pathExtension.lowercased() == "crx"
                    ? .importCRXArchive
                    : .importZipArchive,
                diagnostics: [.installActionsUnavailable]
            )
        }
        let ext = sourceURL.pathExtension.lowercased()
        let service = ChromeMV3PackageIntakeService(rootURL: rootURL)
        if ext == "zip" {
            let importResult = service.importLocalZIPArchive(
                sourceURL: sourceURL,
                profileID: profileID,
                enableInternal: enableInternal,
                runtimeDiagnostics: runtimeDiagnostics
            )
            if let lifecycleResult = importResult.lifecycleResult {
                return .fromLifecycle(
                    action: .importZipArchive,
                    result: lifecycleResult,
                    packageIntakeReport: importResult.report
                )
            }
            return .packageIntake(
                action: .importZipArchive,
                status: importResult.actionStatus,
                report: importResult.report
            )
        }
        if ext == "crx" {
            let importResult = service.importLocalCRXArchive(
                sourceURL: sourceURL
            )
            return .packageIntake(
                action: .importCRXArchive,
                status: importResult.actionStatus,
                report: importResult.report
            )
        }
        return .blocked(
            action: .importZipArchive,
            diagnostics: [
                .make(
                    .zipImportDeferred,
                    severity: .fatalInstall,
                    message: "Only local .zip and .crx package files are accepted by package intake.",
                    remediation: "Choose a local ZIP archive for import or a CRX file for parser diagnostics."
                ),
            ],
            status: .failed
        )
    }

    static func updateFromUnpacked(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        sourceURL: URL,
        gate: ChromeMV3ExtensionManagerGate,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard gate.installActionsAvailable else {
            return .blocked(
                action: .updateFromUnpacked,
                diagnostics: [.installActionsUnavailable]
            )
        }
        let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            .updateExtension(
                profileID: profileID,
                extensionID: extensionID,
                from: sourceURL,
                runtimeDiagnostics: runtimeDiagnostics
            )
        return .fromLifecycle(action: .updateFromUnpacked, result: result)
    }

    static func setInternalEnabled(
        _ enabled: Bool,
        rootURL: URL,
        profileID: String,
        extensionID: String,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard gate.installActionsAvailable else {
            return .blocked(
                action: enabled ? .enableInternal : .disableInternal,
                diagnostics: [.installActionsUnavailable]
            )
        }
        let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            .setInternalEnabled(
                enabled,
                profileID: profileID,
                extensionID: extensionID
            )
        return .fromLifecycle(
            action: enabled ? .enableInternal : .disableInternal,
            result: result
        )
    }

    static func rebuild(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        action: ChromeMV3ExtensionManagerActionKind = .rebuild,
        gate: ChromeMV3ExtensionManagerGate,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard gate.installActionsAvailable else {
            return .blocked(
                action: action,
                diagnostics: [.installActionsUnavailable]
            )
        }
        let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            .rebuildExtension(
                profileID: profileID,
                extensionID: extensionID,
                runtimeDiagnostics: runtimeDiagnostics
            )
        return .fromLifecycle(action: action, result: result)
    }

    static func runDiagnostics(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        gate: ChromeMV3ExtensionManagerGate,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard gate.installActionsAvailable else {
            return .blocked(
                action: .runDiagnostics,
                diagnostics: [.installActionsUnavailable]
            )
        }
        let report = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            .writeEndToEndDiagnostics(
                profileID: profileID,
                extensionID: extensionID,
                runtimeDiagnostics: runtimeDiagnostics
            )
        return .diagnostics(action: .runDiagnostics, report: report)
    }

    static func recover(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard gate.installActionsAvailable else {
            return .blocked(
                action: .recover,
                diagnostics: [.installActionsUnavailable]
            )
        }
        let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            .runRecoveryScan(profileID: profileID, extensionID: extensionID)
        return .fromLifecycle(action: .recover, result: result)
    }

    static func uninstall(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard gate.installActionsAvailable else {
            return .blocked(
                action: .uninstall,
                diagnostics: [.installActionsUnavailable]
            )
        }
        let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            .uninstallExtension(profileID: profileID, extensionID: extensionID)
        return .fromLifecycle(action: .uninstall, result: result)
    }

    static func reset(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard gate.installActionsAvailable else {
            return .blocked(
                action: .reset,
                diagnostics: [.installActionsUnavailable]
            )
        }
        let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            .resetExtensionState(profileID: profileID, extensionID: extensionID)
        return .fromLifecycle(action: .reset, result: result)
    }

    static func exportDiagnosticsJSON(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let json = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            .exportLatestEndToEndDiagnosticsJSON(
                profileID: profileID,
                extensionID: extensionID
            )
        return .exportedJSON(json)
    }

    static func chromeWebStoreInstallDeferred()
        -> ChromeMV3ExtensionManagerActionResult
    {
        .blocked(
            action: .chromeWebStoreInstall,
            diagnostics:
                ChromeMV3ExtensionManagerBlockedDiagnostic
                .chromeWebStoreDeferred,
            status: .deferred
        )
    }

    static func chromeWebStoreDiagnostic(
        rootURL: URL,
        input: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let report = ChromeMV3PackageIntakeService(rootURL: rootURL)
            .diagnoseChromeWebStoreInput(input)
        return .packageIntake(
            action: .chromeWebStoreInstall,
            status: .deferred,
            report: report
        )
    }
}

private extension ChromeMV3EndToEndInstallDiagnosticsReport {
    var managerActiveManifestSummary: ChromeMV3ManifestSummary? {
        let active = generatedBundleVersionState.last {
            $0.state == .active || $0.state == .rollbackActive
        } ?? generatedBundleVersionState.last
        return active?.generatedBundleRecord.installReportSummary
            .manifestSummary
    }
}

struct ChromeMV3ExtensionManagerView: View {
        let listViewModel: ChromeMV3ExtensionManagerListViewModel
        let selectedDetail: ChromeMV3ExtensionManagerDetailViewModel?
        var onLoadUnpacked: (() -> Void)?
        var onImportArchive: (() -> Void)?
        var onSelectExtension: ((String, String) -> Void)?
        var onRunAction:
            ((ChromeMV3ExtensionManagerActionKind, String, String) -> Void)?
        var onCopyDiagnosticsJSON: ((String, String) -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                gateSection
                actionsHeader
                packageIntakeSection
                HStack(alignment: .top, spacing: 16) {
                    listSection
                    detailSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var gateSection: some View {
            SettingsSectionCard(
                title: "MV3 Developer Preview",
                subtitle: listViewModel.gate.managerAvailableInDeveloperPreview
                    ? "Internal manager is available; product runtime remains off."
                    : "Internal manager is blocked by the current gate."
            ) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    gateFlag(
                        "developerPreviewManager",
                        listViewModel.gate.managerAvailableInDeveloperPreview
                    )
                    gateFlag(
                        "publicProductManager",
                        listViewModel.gate.managerAvailableInPublicProduct
                    )
                    gateFlag(
                        "installActions",
                        listViewModel.gate.installActionsAvailable
                    )
                    gateFlag(
                        "runtimeActions",
                        listViewModel.gate.runtimeActionsAvailable
                    )
                    gateFlag(
                        "webStoreInstall",
                        listViewModel.gate.webStoreInstallAvailable
                    )
                    gateFlag(
                        "localArchiveImport",
                        listViewModel.gate.localArchiveImportAvailable
                    )
                }
            }
        }

        @ViewBuilder
        private var packageIntakeSection: some View {
            if let report = selectedDetail?.packageIntakeReport
                ?? listViewModel.packageIntakeReport
            {
                SettingsSectionCard(
                    title: "Package Intake",
                    subtitle:
                        "\(report.sourceKind.rawValue) - \(report.preflightResult.status.rawValue)"
                ) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        fact("ZIP", report.productFlags.zipImportAvailable ? "available" : "unavailable")
                        fact("CRX", report.trustResult.importAllowed ? "allowed" : "blocked")
                        fact("Web Store", report.productFlags.chromeWebStoreInstallAvailable ? "available" : "deferred")
                        fact("Runtime", report.productFlags.runtimeLoadable ? "loadable" : "off")
                    }
                    if let blocker = report.blockers.first {
                        Text(blocker)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        private var actionsHeader: some View {
            SettingsSectionCard(
                title: "Manager Actions",
                subtitle: "Actions call the internal lifecycle registry and diagnostics writers only."
            ) {
                HStack(spacing: 8) {
                    Button {
                        onLoadUnpacked?()
                    } label: {
                        Label("Load Unpacked", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !listViewModel.gate.installActionsAvailable
                            || onLoadUnpacked == nil
                    )

                    Button {
                        onImportArchive?()
                    } label: {
                        Label("Import Archive", systemImage: "archivebox")
                    }
                    .buttonStyle(.bordered)
                    .disabled(onImportArchive == nil)

                    Button {
                        onRunAction?(
                            .chromeWebStoreInstall,
                            selectedDetail?.listItem.profileID ?? "",
                            selectedDetail?.listItem.extensionID ?? ""
                        )
                    } label: {
                        Label("Web Store", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .disabled(onRunAction == nil)
                }
            }
        }

        private var listSection: some View {
            SettingsSectionCard(
                title: "Installed Internal MV3",
                subtitle: listViewModel.items.isEmpty
                    ? "No internal MV3 lifecycle records."
                    : "\(listViewModel.items.count) internal lifecycle record(s)."
            ) {
                if listViewModel.items.isEmpty {
                    Text("Load an unpacked Manifest V3 folder to create an internal record.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(listViewModel.items) { item in
                            Button {
                                onSelectExtension?(
                                    item.profileID,
                                    item.extensionID
                                )
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "puzzlepiece.extension")
                                        .frame(width: 18)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Text(
                                            "\(item.version) - \(item.lifecycleState.rawValue) - \(item.productPreflightStatus.rawValue)"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(
                                        item.internalEnabled
                                            ? "Enabled"
                                            : "Disabled"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        item.internalEnabled
                                            ? .green
                                            : .secondary
                                    )
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(minWidth: 280, maxWidth: 360, alignment: .topLeading)
        }

        @ViewBuilder
        private var detailSection: some View {
            if let selectedDetail {
                SettingsSectionCard(
                    title: selectedDetail.listItem.name,
                    subtitle:
                        "\(selectedDetail.listItem.extensionID) - \(selectedDetail.listItem.version)"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        detailSummary(selectedDetail)
                        preflightSummary(selectedDetail)
                        popupOptionsSummary(selectedDetail)
                        permissionStateSummary(selectedDetail)
                        blockerSummary(selectedDetail)
                        detailActions(selectedDetail)
                    }
                }
            } else {
                SettingsSectionCard(
                    title: "Compatibility Report",
                    subtitle: "Select an internal MV3 extension to inspect blockers."
                ) {
                    Text("No extension selected.")
                        .foregroundStyle(.secondary)
                }
            }
        }

        private func detailSummary(
            _ detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> some View {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                fact("Manifest", "\(detail.manifestSummary.manifestVersion ?? 0)")
                fact("Lifecycle", detail.listItem.lifecycleState.rawValue)
                fact(
                    "Active Bundle",
                    detail.generatedBundleState.activeVersionID ?? "none"
                )
                fact(
                    "Blockers",
                    "\(detail.exactCompatibilityBlockers.count)"
                )
            }
        }

        private func preflightSummary(
            _ detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("Product Preflight")
                    .font(.callout.weight(.semibold))
                Text(
                    detail.productEnablementPreflight
                        .normalTabPreflight
                        .diagnostics
                        .joined(separator: " ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func blockerSummary(
            _ detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Exact Blockers")
                    .font(.callout.weight(.semibold))
                ForEach(detail.blockersBySeverity.prefix(4)) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                        ForEach(group.blockers.prefix(3), id: \.id) {
                            blocker in
                            Text(blocker.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        private func popupOptionsSummary(
            _ detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> some View {
            let popup = detail.popupOptionsLaunchState.actionPopup
            let options = detail.popupOptionsLaunchState.primaryOptions
            return VStack(alignment: .leading, spacing: 8) {
                Text("Popup and Options")
                    .font(.callout.weight(.semibold))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    fact(
                        "Action Popup",
                        popup.canOpen ? "launchable" : popup.resourceValidationState.rawValue
                    )
                    fact(
                        "Options",
                        options?.canOpen == true
                            ? "launchable"
                            : (options?.resourceValidationState.rawValue
                                ?? "missingDeclaration")
                    )
                    fact(
                        "Bridge",
                        popup.gateRecord.popupOptionsBridgeAllowed
                            ? "limited" : "blocked"
                    )
                    fact(
                        "API Allowlist",
                        "\(popup.apiSurface.allowedMethods.count) methods"
                    )
                    fact(
                        "API Blockers",
                        "\(popup.apiSurface.blockedMethods.count) methods"
                    )
                    fact(
                        "Toolbar",
                        detail.popupOptionsLaunchState.toolbarActionUIDeferred
                            ? "deferred" : "available"
                    )
                }
                HStack(spacing: 8) {
                    Button {
                        onRunAction?(
                            .openActionPopup,
                            detail.listItem.profileID,
                            detail.listItem.extensionID
                        )
                    } label: {
                        Label("Open Popup", systemImage: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!popup.canOpen)

                    Button {
                        onRunAction?(
                            .openOptions,
                            detail.listItem.profileID,
                            detail.listItem.extensionID
                        )
                    } label: {
                        Label("Open Options", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .disabled(options?.canOpen != true)

                    Button {
                        onRunAction?(
                            .closePopupOptions,
                            detail.listItem.profileID,
                            detail.listItem.extensionID
                        )
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                if let reason = (popup.blockingReasons
                    + (options?.blockingReasons ?? [])).first
                {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let lastError = detail.popupOptionsLaunchState
                    .lastRunResult?.popupOptionsLastAPIErrorSummary
                {
                    Text("Last popup/options API error: \(lastError)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if popup.apiSurface.blockedMethods.isEmpty == false {
                    let blocked = popup.apiSurface.blockedMethods
                        .prefix(4)
                        .map { "\($0.namespace).\($0.methodName)" }
                        .joined(separator: ", ")
                    Text("Blocked popup/options APIs: \(blocked)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        private func permissionStateSummary(
            _ detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> some View {
            let panel = detail.permissionStatePanel
            return VStack(alignment: .leading, spacing: 8) {
                Text("Permissions")
                    .font(.callout.weight(.semibold))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    fact(
                        "Required APIs",
                        "\(panel.requiredPermissions.count)"
                    )
                    fact(
                        "Optional APIs",
                        "\(panel.optionalPermissions.count)"
                    )
                    fact(
                        "Required Hosts",
                        "\(panel.hostPermissions.count)"
                    )
                    fact(
                        "Optional Hosts",
                        "\(panel.optionalHostPermissions.count)"
                    )
                    fact(
                        "Granted Optional",
                        "\(panel.grantedOptionalPermissions.count + panel.grantedOptionalHostPermissions.count)"
                    )
                    fact(
                        "Denied/Revoked",
                        "\(panel.deniedPermissions.count + panel.revokedPermissions.count)"
                    )
                    fact(
                        "activeTab",
                        "\(panel.activeTabCurrentGrants.count)"
                    )
                    fact(
                        "Prompt Gate",
                        panel.promptGate
                            .permissionPromptAvailableInDeveloperPreview
                            ? "developer-preview" : "blocked"
                    )
                }
                if panel.grantedOptionalPermissions.isEmpty == false
                    || panel.grantedOptionalHostPermissions.isEmpty == false
                {
                    Text(
                        "Granted: "
                            + (panel.grantedOptionalPermissions
                                + panel.grantedOptionalHostPermissions)
                            .prefix(4)
                            .joined(separator: ", ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if panel.deniedPermissions.isEmpty == false
                    || panel.revokedPermissions.isEmpty == false
                {
                    Text(
                        "Blocked decisions: "
                            + (panel.deniedPermissions
                                + panel.revokedPermissions)
                            .prefix(4)
                            .joined(separator: ", ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let blocker = panel.blockedPromptReasons.first {
                    Text(blocker)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        private func detailActions(
            _ detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lifecycle Actions")
                    .font(.callout.weight(.semibold))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 138), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(detail.actions.filter {
                        $0.action != .installUnpacked
                            && $0.action != .importZipArchive
                            && $0.action != .importCRXArchive
                            && $0.action != .chromeWebStoreInstall
                            && $0.action != .openActionPopup
                            && $0.action != .openOptions
                            && $0.action != .closePopupOptions
                    }) { descriptor in
                        Button(descriptor.title) {
                            if descriptor.action == .exportDiagnosticsJSON {
                                onCopyDiagnosticsJSON?(
                                    detail.listItem.profileID,
                                    detail.listItem.extensionID
                                )
                            } else {
                                onRunAction?(
                                    descriptor.action,
                                    detail.listItem.profileID,
                                    detail.listItem.extensionID
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!descriptor.available)
                    }
                }
            }
        }

        private func gateFlag(_ title: String, _ value: Bool) -> some View {
            HStack(spacing: 8) {
                Image(systemName: value ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(value ? .green : .secondary)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }

        private func fact(_ title: String, _ value: String) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
}

private func uniqueSortedExtensionManager(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
