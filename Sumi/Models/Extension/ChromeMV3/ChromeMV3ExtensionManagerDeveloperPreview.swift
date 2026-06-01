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
    case runBitwardenManualSmoke
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
    case manualSmokeUnavailable
    case manualSmokeLocalExperimentalGateClosed
    case manualSmokeReviewedFileMissing
    case manualSmokeExtensionDisabled
    case manualSmokeNotProductSupport
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
            finding: "Static MV3 content_scripts define matches, CSS/JS order, run_at, all_frames, match_about_blank, match_origin_as_fallback, and execution world; Sumi supports only developer-preview gated main-frame isolated-world JS plus manifest CSS through scoped WebKit user stylesheets."
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
            finding: "scripting.executeScript is a runtime injection API distinct from manifest static content scripts; Sumi keeps arbitrary product executeScript blocked and models only the reviewed local Bitwarden generated-bundle bootstrap file on the scoped synthetic login surface."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome content scripts",
            url: "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
            boundary: "programmatic content-script permissions",
            finding: "Programmatic content-script injection requires host permissions or activeTab; Sumi requires one of those grants before the manual normal-tab smoke can pass."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome activeTab permission",
            url: "https://developer.chrome.com/docs/extensions/develop/concepts/activeTab",
            boundary: "temporary tab host access",
            finding: "activeTab grants temporary host access for the current tab after a user gesture and is revoked on navigation or tab close; Sumi requires host permission or an activeTab grant before any normal-tab readiness path can pass."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Chrome extension service-worker lifecycle",
            url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
            boundary: "event-driven runtime lifetime",
            finding: "MV3 extension service workers are event-driven and unloadable; Sumi keeps normal-tab readiness plan-only and does not create permanent background runtime, polling, or wake state from manager viewing."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Apple WKWebExtensionController header",
            url: "xcode://MacOSX.sdk/System/Library/Frameworks/WebKit.framework/Headers/WKWebExtensionController.h",
            boundary: "WebKit runtime attachment",
            finding: "The SDK header states the controller manages loaded extension contexts, load starts background content and injects content, and WKWebViewConfiguration.webExtensionController associates controllers with web views."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Apple WKWebView evaluateJavaScript header",
            url: "xcode://MacOSX.sdk/System/Library/Frameworks/WebKit.framework/Headers/WKWebView.h",
            boundary: "content world JavaScript evaluation",
            finding: "The local SDK header exposes evaluation in a WKFrameInfo and WKContentWorld and notes DOM changes are visible across worlds; Sumi records this risk and keeps product readiness plan-only."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Apple WKContentWorld documentation",
            url: "https://developer.apple.com/documentation/webkit/wkcontentworld",
            boundary: "isolated content-world execution",
            finding: "WKContentWorld separates JavaScript variable environments but DOM changes remain visible; Sumi therefore keeps manual smoke restricted to a synthetic HTTPS login page and dummy-only values."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Apple WKUserContentController documentation",
            url: "https://developer.apple.com/documentation/webkit/wkusercontentcontroller",
            boundary: "script and handler teardown",
            finding: "WKUserContentController manages injected scripts and script message handlers, including removal APIs; manual smoke records explicit handler/script teardown."
        ),
        ChromeMV3ExtensionManagerDocumentationSource(
            title: "Apple WKWebsiteDataStore nonPersistent documentation",
            url: "https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()",
            boundary: "synthetic smoke storage isolation",
            finding: "WKWebsiteDataStore exposes a nonpersistent data store; manual smoke uses it for the synthetic normal-tab WebKit object and keeps persistent browsing data disabled."
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

    static let manualSmokeUnavailable = make(
        .manualSmokeUnavailable,
        severity: .productBlocked,
        message: "The Bitwarden manual normal-tab smoke action is unavailable.",
        remediation: "Enable the internal extension record, keep the local experimental manager gate open, and ensure the reviewed generated-bundle bootstrap file is present."
    )

    static let manualSmokeLocalExperimentalGateClosed = make(
        .manualSmokeLocalExperimentalGateClosed,
        severity: .productBlocked,
        message: "The manual smoke local experimental gate is closed.",
        remediation: "Invoke the explicit local experimental manager action only from an internal DEBUG/developer-preview path."
    )

    static let manualSmokeReviewedFileMissing = make(
        .manualSmokeReviewedFileMissing,
        severity: .fatalRuntime,
        message: "The reviewed Bitwarden content/bootstrap-autofill.js generated-bundle file is missing or unhashed.",
        remediation: "Rebuild the generated bundle and rerun diagnostics before attempting the manual smoke."
    )

    static let manualSmokeExtensionDisabled = make(
        .manualSmokeExtensionDisabled,
        severity: .productBlocked,
        message: "The internal extension record is disabled; manual smoke will not create a synthetic normal-tab WebKit object.",
        remediation: "Enable the internal extension record in the local experimental manager before invoking the smoke."
    )

    static let manualSmokeNotProductSupport = make(
        .manualSmokeNotProductSupport,
        severity: .info,
        message: "Manual smoke is a local experimental diagnostic only and is not a Bitwarden product-support claim.",
        remediation: "Keep product/default runtime off and use the artifact as diagnostics only."
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

struct ChromeMV3ExtensionManagerManualSmokeDOMSummary:
    Codable,
    Equatable
{
    var phase: String
    var url: String
    var origin: String
    var documentID: String
    var navigationSequence: Int
    var usernameFieldExists: Bool
    var passwordFieldExists: Bool
    var submitButtonExists: Bool
    var initialValuesEmpty: Bool
    var finalValuesMatchDummyFill: Bool
    var usernameValueMarker: String
    var passwordValueMarker: String

    static func make(
        _ snapshot: ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot,
        dummyUsername: String,
        dummyPassword: String
    ) -> Self {
        ChromeMV3ExtensionManagerManualSmokeDOMSummary(
            phase: snapshot.phase,
            url: snapshot.url,
            origin: snapshot.origin,
            documentID: snapshot.documentID,
            navigationSequence: snapshot.navigationSequence,
            usernameFieldExists: snapshot.usernameFieldExists,
            passwordFieldExists: snapshot.passwordFieldExists,
            submitButtonExists: snapshot.submitButtonExists,
            initialValuesEmpty: snapshot.initialValuesEmpty,
            finalValuesMatchDummyFill: snapshot.finalValuesMatchDummyFill,
            usernameValueMarker:
                snapshot.usernameValue == dummyUsername
                    ? "synthetic-dummy-username-present"
                    : (snapshot.usernameValue.isEmpty ? "empty" : "redacted"),
            passwordValueMarker:
                snapshot.passwordValue == dummyPassword
                    ? "synthetic-dummy-password-present"
                    : (snapshot.passwordValue.isEmpty ? "empty" : "redacted")
        )
    }
}

struct ChromeMV3ExtensionManagerManualSmokeRuntimeBehavior:
    Codable,
    Equatable
{
    var productDefaultRuntimeAvailable: Bool
    var productRuntimeExposed: Bool
    var arbitraryScriptingEnabled: Bool
    var mainWorldEnabled: Bool
    var multiFrameEnabled: Bool
    var fileSchemeEnabled: Bool
    var auxiliaryWebViewEnabled: Bool
    var networkAuthNativeHostEnabled: Bool
    var webStoreOrRemoteCRXEnabled: Bool
    var timersOrPollingEnabled: Bool
}

struct ChromeMV3ExtensionManagerManualSmokeArtifact:
    Codable,
    Equatable
{
    static let schemaVersion = 1
    static let smokeKind = "bitwardenManualNormalTabSmoke"

    var schemaVersion: Int
    var generatedAt: Date
    var runID: String
    var profileID: String
    var extensionID: String
    var packageSource: ChromeMV3PackageSourceKind
    var packagePath: String
    var smokeKind: String
    var reviewedScriptPath: String
    var reviewedScriptHash: String?
    var syntheticURL: String
    var syntheticOrigin: String
    var gatePreflightEligible: Bool
    var gatePreflightBlockers: [String]
    var actionManualOnly: Bool
    var managerReadoutExecutedSmoke: Bool
    var domBefore: ChromeMV3ExtensionManagerManualSmokeDOMSummary
    var domAfter: ChromeMV3ExtensionManagerManualSmokeDOMSummary
    var fieldsTouched: [String]
    var dummyValueMarkers: [String]
    var teardownCompleted: Bool
    var teardownStatus: ChromeMV3LocalExperimentalNormalTabManualSmokeTeardown
    var retainedObjectCount: Int
    var runtimeBehaviorIntentionallyUnchanged:
        ChromeMV3ExtensionManagerManualSmokeRuntimeBehavior
    var blockers: [String]
    var noRealSecrets: Bool
    var noRawCredentials: Bool
    var noRealWebsiteData: Bool
    var notProductSupportWarning: String
    var diagnostics: [String]

    static func make(
        result: ChromeMV3LocalExperimentalNormalTabManualSmokeResult,
        record: ChromeMV3ExtensionLifecycleRecord,
        generatedAt: Date
    ) -> Self {
        let runID =
            "bitwarden-manual-smoke-\(record.profileID)-\(record.extensionID)-\(Int(generatedAt.timeIntervalSince1970))"
        return ChromeMV3ExtensionManagerManualSmokeArtifact(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            runID: runID,
            profileID: record.profileID,
            extensionID: record.extensionID,
            packageSource: record.sourceKind,
            packagePath: record.sourcePath,
            smokeKind: smokeKind,
            reviewedScriptPath: result.injectionPlan.reviewedScriptPath,
            reviewedScriptHash: result.injectionPlan.generatedResourceHash,
            syntheticURL: result.injectionPlan.syntheticURL,
            syntheticOrigin: result.injectionPlan.syntheticOrigin,
            gatePreflightEligible: result.eligibility.eligible,
            gatePreflightBlockers:
                result.eligibility.blockers.map(\.rawValue).sorted(),
            actionManualOnly: true,
            managerReadoutExecutedSmoke:
                result.injectionPlan.managerReadoutExecutes,
            domBefore:
                .make(
                    result.domObservationBefore,
                    dummyUsername: result.usernameDummyValue,
                    dummyPassword: result.passwordDummyValue
                ),
            domAfter:
                .make(
                    result.domObservationAfter,
                    dummyUsername: result.usernameDummyValue,
                    dummyPassword: result.passwordDummyValue
                ),
            fieldsTouched: result.fieldsTouched.sorted(),
            dummyValueMarkers: [
                result.domObservationAfter.usernameValue
                    == result.usernameDummyValue
                    ? "usernameSyntheticDummyMatched"
                    : "usernameSyntheticDummyNotPresent",
                result.domObservationAfter.passwordValue
                    == result.passwordDummyValue
                    ? "passwordSyntheticDummyMatched"
                    : "passwordSyntheticDummyNotPresent",
            ].sorted(),
            teardownCompleted: result.teardown.completed,
            teardownStatus: result.teardown,
            retainedObjectCount:
                result.teardown.retainedObjectCountAfterTeardown,
            runtimeBehaviorIntentionallyUnchanged:
                ChromeMV3ExtensionManagerManualSmokeRuntimeBehavior(
                    productDefaultRuntimeAvailable:
                        result.productDefaultRuntimeAvailable,
                    productRuntimeExposed: false,
                    arbitraryScriptingEnabled: false,
                    mainWorldEnabled: false,
                    multiFrameEnabled: false,
                    fileSchemeEnabled: false,
                    auxiliaryWebViewEnabled: result.auxiliarySurfaceAllowed,
                    networkAuthNativeHostEnabled: false,
                    webStoreOrRemoteCRXEnabled: false,
                    timersOrPollingEnabled: false
                ),
            blockers: result.blockers.map(\.rawValue).sorted(),
            noRealSecrets: true,
            noRawCredentials: true,
            noRealWebsiteData: true,
            notProductSupportWarning:
                "Local experimental diagnostic only; this is not a Bitwarden support claim and does not enable product/default runtime.",
            diagnostics:
                uniqueSortedExtensionManager(
                    result.diagnostics
                        + [
                            "Artifact redacts dummy values and records only synthetic dummy markers.",
                            "No real website data, credentials, vault state, account tokens, device identity, network auth, native host, Web Store, or remote CRX path was used.",
                        ]
                )
        )
    }
}

enum ChromeMV3ExtensionManagerManualSmokeArtifactWriter {
    static let diagnosticsDirectoryName =
        ".diagnostics/chrome-mv3-manual-smoke"
    static let reportFileName =
        "bitwarden-manual-normal-tab-smoke.json"

    static func reportURL(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> URL {
        rootURL.standardizedFileURL
            .appendingPathComponent(
                diagnosticsDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent(safePathComponent(profileID), isDirectory: true)
            .appendingPathComponent(safePathComponent(extensionID), isDirectory: true)
            .appendingPathComponent(reportFileName)
    }

    static func latestArtifact(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        fileManager: FileManager = .default
    ) -> ChromeMV3ExtensionManagerManualSmokeArtifact? {
        let url = reportURL(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID
        )
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            ChromeMV3ExtensionManagerManualSmokeArtifact.self,
            from: Data(contentsOf: url)
        )
    }

    @discardableResult
    static func write(
        _ artifact: ChromeMV3ExtensionManagerManualSmokeArtifact,
        rootURL: URL
    ) throws -> URL {
        let url = reportURL(
            rootURL: rootURL,
            profileID: artifact.profileID,
            extensionID: artifact.extensionID
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ChromeMV3DeterministicJSON.write(artifact, to: url)
        return url
    }

    private static func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "-"
        }
        let safe = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return safe.isEmpty ? "unknown" : safe
    }
}

struct ChromeMV3ExtensionManagerManualSmokeActionRecord:
    Codable,
    Equatable
{
    var actionID: ChromeMV3ExtensionManagerActionKind
    var extensionID: String
    var profileID: String
    var packageSource: ChromeMV3PackageSourceKind
    var packagePath: String
    var gateState: [String: Bool]
    var available: Bool
    var enabledReason: String?
    var disabledReason: String?
    var manualOnly: Bool
    var lastRunStatus: ChromeMV3ExtensionManagerActionStatus?
    var lastArtifactPath: String?
    var lastBlockers: [String]
    var lastTeardownStatus: String?
    var lastRetainedObjectCount: Int?
    var notProductSupportWarning: String
    var unavailableDiagnostics: [ChromeMV3ExtensionManagerBlockedDiagnostic]

    static func make(
        rootURL: URL,
        record: ChromeMV3ExtensionLifecycleRecord,
        gate: ChromeMV3ExtensionManagerGate,
        readiness: ChromeMV3ProductNormalTabReadinessReport,
        lastArtifact: ChromeMV3ExtensionManagerManualSmokeArtifact? = nil
    ) -> Self {
        var diagnostics: [ChromeMV3ExtensionManagerBlockedDiagnostic] = []
        let localExperimentalGateOpen = gate.managerAvailableInDeveloperPreview
        if localExperimentalGateOpen == false {
            diagnostics.append(.manualSmokeLocalExperimentalGateClosed)
        }
        if record.runtimeState.internalRuntimeEnabled == false {
            diagnostics.append(.manualSmokeExtensionDisabled)
        }
        if readiness.preflight.reviewedResource.present == false
            || readiness.preflight.reviewedResource.generatedResourceHash == nil
        {
            diagnostics.append(.manualSmokeReviewedFileMissing)
        }
        if diagnostics.isEmpty == false {
            diagnostics.append(.manualSmokeUnavailable)
        }
        diagnostics.append(.manualSmokeNotProductSupport)
        let blockingDiagnostics = diagnostics.filter {
            $0.severity != .info
        }
        let available = blockingDiagnostics.isEmpty
        let artifactPath = lastArtifact.map { _ in
            ChromeMV3ExtensionManagerManualSmokeArtifactWriter.reportURL(
                rootURL: rootURL,
                profileID: record.profileID,
                extensionID: record.extensionID
            ).path
        }
        return ChromeMV3ExtensionManagerManualSmokeActionRecord(
            actionID: .runBitwardenManualSmoke,
            extensionID: record.extensionID,
            profileID: record.profileID,
            packageSource: record.sourceKind,
            packagePath: record.sourcePath,
            gateState: [
                "localExperimentalManagerGateOpen": localExperimentalGateOpen,
                "extensionInternalRecordEnabled":
                    record.runtimeState.internalRuntimeEnabled,
                "reviewedBootstrapPresent":
                    readiness.preflight.reviewedResource.present,
                "reviewedBootstrapHashRecorded":
                    readiness.preflight.reviewedResource.generatedResourceHash != nil,
                "productDefaultRuntimeAvailable":
                    readiness.policy.productDefaultRuntimeAvailable,
                "managerReadoutExecutesSmoke": false,
            ],
            available: available,
            enabledReason:
                available
                    ? "All local experimental manual smoke prerequisites are satisfied for explicit invocation."
                    : nil,
            disabledReason:
                available
                    ? nil
                    : blockingDiagnostics.map(\.message).sorted()
                        .joined(separator: " "),
            manualOnly: true,
            lastRunStatus:
                lastArtifact.map {
                    $0.blockers.isEmpty && $0.teardownCompleted
                        ? .succeeded : .blocked
                },
            lastArtifactPath: artifactPath,
            lastBlockers:
                lastArtifact?.blockers
                    ?? readiness.preflight.blockers.map(\.rawValue).sorted(),
            lastTeardownStatus:
                lastArtifact.map {
                    $0.teardownCompleted
                        ? "completed"
                        : "incomplete"
                },
            lastRetainedObjectCount: lastArtifact?.retainedObjectCount,
            notProductSupportWarning:
                "Local experimental diagnostic only; stable product path and Bitwarden support remain unclaimed.",
            unavailableDiagnostics:
                Array(
                    Dictionary(grouping: diagnostics, by: \.code)
                        .compactMap { $0.value.first }
                ).sorted { $0.code < $1.code }
        )
    }
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
    var controls: [ChromeMV3ExtensionManagerPermissionControl]
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
            controls:
                ChromeMV3ExtensionManagerPermissionControl.makeControls(
                    promptGate: persisted?.promptGateRecord ?? promptGate,
                    requiredPermissions: manifestSummary.permissions,
                    optionalPermissions: manifestSummary.optionalPermissions,
                    optionalHostPermissions:
                        manifestSummary.optionalHostPermissions,
                    grantedOptionalPermissions:
                        summary?.grantedOptionalAPIPermissions ?? [],
                    grantedOptionalHostPermissions:
                        summary?.grantedOptionalHostPermissions ?? [],
                    activeTabCurrentGrants:
                        activeTab?.activeGrantScopes ?? []
                ),
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

enum ChromeMV3ExtensionManagerPermissionControlKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case requestOptionalAPIPermission
    case requestOptionalHostPermission
    case revokeOptionalAPIPermission
    case revokeOptionalHostPermission
    case clearActiveTabGrant

    static func < (
        lhs: ChromeMV3ExtensionManagerPermissionControlKind,
        rhs: ChromeMV3ExtensionManagerPermissionControlKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ExtensionManagerPermissionControl:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var kind: ChromeMV3ExtensionManagerPermissionControlKind
    var value: String
    var title: String
    var available: Bool
    var blockerReason: String?
    var diagnostics: [String]

    static func makeControls(
        promptGate: ChromeMV3PermissionPromptGateRecord,
        requiredPermissions: [String],
        optionalPermissions: [String],
        optionalHostPermissions: [String],
        grantedOptionalPermissions: [String],
        grantedOptionalHostPermissions: [String],
        activeTabCurrentGrants: [String]
    ) -> [ChromeMV3ExtensionManagerPermissionControl] {
        let grantedAPIs = Set(grantedOptionalPermissions)
        let grantedHosts = Set(grantedOptionalHostPermissions)
        let gateBlocked = promptGate.blockers.first?.diagnostic
        var controls: [ChromeMV3ExtensionManagerPermissionControl] = []
        for permission in uniqueSortedExtensionManager(optionalPermissions) {
            let granted = grantedAPIs.contains(permission)
            controls.append(
                control(
                    kind:
                        granted
                            ? .revokeOptionalAPIPermission
                            : .requestOptionalAPIPermission,
                    value: permission,
                    title: granted ? "Revoke \(permission)" : "Request \(permission)",
                    available:
                        granted
                            || promptGate.canPromptDeveloperPreview,
                    blockerReason: granted ? nil : gateBlocked,
                    diagnostics: [
                        granted
                            ? "Optional API permission is currently granted and can be revoked explicitly."
                            : "Optional API permission can be requested only through an explicit prompt.",
                    ]
                )
            )
        }
        for origin in uniqueSortedExtensionManager(optionalHostPermissions) {
            let granted = grantedHosts.contains(origin)
            controls.append(
                control(
                    kind:
                        granted
                            ? .revokeOptionalHostPermission
                            : .requestOptionalHostPermission,
                    value: origin,
                    title: granted ? "Revoke \(origin)" : "Request \(origin)",
                    available:
                        granted
                            || promptGate.canPromptDeveloperPreview,
                    blockerReason: granted ? nil : gateBlocked,
                    diagnostics: [
                        granted
                            ? "Optional host permission is currently granted and can be revoked explicitly."
                            : "Optional host permission can be requested only through an explicit prompt.",
                    ]
                )
            )
        }
        if activeTabCurrentGrants.isEmpty == false
            || requiredPermissions.contains("activeTab")
        {
            controls.append(
                control(
                    kind: .clearActiveTabGrant,
                    value: "activeTab",
                    title: "Clear activeTab",
                    available: activeTabCurrentGrants.isEmpty == false,
                    blockerReason:
                        activeTabCurrentGrants.isEmpty
                            ? "No activeTab grant is currently recorded."
                            : nil,
                    diagnostics: [
                        "activeTab grants are temporary and can be explicitly cleared from developer-preview manager state.",
                    ]
                )
            )
        }
        return controls.sorted {
            if $0.kind != $1.kind { return $0.kind < $1.kind }
            return $0.value < $1.value
        }
    }

    private static func control(
        kind: ChromeMV3ExtensionManagerPermissionControlKind,
        value: String,
        title: String,
        available: Bool,
        blockerReason: String?,
        diagnostics: [String]
    ) -> ChromeMV3ExtensionManagerPermissionControl {
        ChromeMV3ExtensionManagerPermissionControl(
            id: "\(kind.rawValue):\(value)",
            kind: kind,
            value: value,
            title: title,
            available: available,
            blockerReason: blockerReason,
            diagnostics:
                uniqueSortedExtensionManager(
                    diagnostics
                        + [
                            "Manager permission control requires explicit user action.",
                            "Manager permission control does not wake a service worker.",
                            "silentGrantAllowed is false.",
                        ]
                )
        )
    }
}

struct ChromeMV3ExtensionManagerPermissionActionResult:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3ExtensionManagerPermissionControlKind
    var value: String
    var succeeded: Bool
    var returnedBoolean: Bool
    var promptRequest: ChromeMV3PermissionPromptRequest?
    var promptResult: ChromeMV3PermissionPromptResultRecord?
    var promptLifecycleRecords:
        [ChromeMV3PermissionPromptLifecycleRecord]
    var runtimeSnapshot: ChromeMV3PermissionRuntimeStateOwnerSnapshot?
    var eventDispatchRecord: ChromeMV3PermissionEventDispatchRecord?
    var serviceWorkerWakeAttempted: Bool
    var hiddenExtensionPageCreated: Bool
    var diagnostics: [String]
}

struct ChromeMV3ExtensionManagerTrustedNativeHostControlDescriptor:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var kind: ChromeMV3NativeTrustedHostControlKind
    var hostName: String
    var title: String
    var available: Bool
    var warning: String
    var diagnostics: [String]
}

struct ChromeMV3ExtensionManagerTrustedNativeHostRequirement:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String { hostName }
    var fixturePackID: String?
    var fixtureRootPath: String?
    var fixturePackGeneratedState:
        ChromeMV3NativeMessagingFixturePackGeneratedState
    var fixturePackValidatedState:
        ChromeMV3NativeMessagingFixturePackValidatedState
    var hostNameSource: String
    var hostName: String
    var requiredBy: String
    var manifestStatus: ChromeMV3NativeHostLookupStatus
    var manifestPath: String?
    var executablePath: String?
    var resolvedExecutablePath: String?
    var allowedOrigins: [String]
    var allowedOriginsSource: String
    var allowedOriginsState:
        ChromeMV3PasswordManagerRealPackageAllowedOriginsState?
    var trustedHostState: ChromeMV3NativeTrustedHostTrustState
    var trustedForDeveloperPreview: Bool
    var canSendNativeMessageNow: Bool
    var canConnectNativeNow: Bool
    var processLaunchAllowedNow: Bool
    var fixtureExchangeState:
        ChromeMV3PasswordManagerRealPackageNativeHostExchangeState?
    var fixtureExchangeAttempted: Bool
    var realVendorHostDiscoveryBlocked: Bool
    var arbitraryHostLaunchAllowed: Bool
    var controls:
        [ChromeMV3ExtensionManagerTrustedNativeHostControlDescriptor]
    var blockers: [String]
    var diagnostics: [String]
}

struct ChromeMV3ExtensionManagerTrustedNativeHostPanel:
    Codable,
    Equatable,
    Sendable
{
    var nativeMessagingPermissionDeclared: Bool
    var nativeMessagingPermissionGranted: Bool
    var trustedHostPolicyAvailable: Bool
    var approvalRequired: Bool
    var arbitraryHostLaunchAllowed: Bool
    var nativeHostScanningAllowed: Bool
    var discoveryReport: ChromeMV3NativeHostDiscoveryPolicyReport
    var hostRequirements:
        [ChromeMV3ExtensionManagerTrustedNativeHostRequirement]
    var diagnostics: [String]

    static func make(
        rootURL: URL,
        record: ChromeMV3ExtensionLifecycleRecord,
        manifestSummary:
            ChromeMV3ExtensionManagerManifestSummaryViewState,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerTrustedNativeHostPanel {
        let nativeDeclared =
            manifestSummary.permissions.contains("nativeMessaging")
                || manifestSummary.optionalPermissions
                .contains("nativeMessaging")
        let store = ChromeMV3DeveloperPreviewPermissionStateStore(
            rootURL: rootURL
        )
        let persisted = store.loadRecord(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let grantedOptional =
            persisted?.permissionRuntimeSnapshot.permissionStore.summary
            .grantedOptionalAPIPermissions ?? []
        let nativeGranted =
            manifestSummary.permissions.contains("nativeMessaging")
                || grantedOptional.contains("nativeMessaging")
        let realPackageReport =
            ChromeMV3PasswordManagerRealPackageCompatibilityReportWriter
            .latestReport(rootURL: rootURL)
        let realPackageRow = realPackageReport?.rows.first {
            trustedNativeHostRealPackageRow(
                $0,
                matches: record,
                in: realPackageReport
            )
        }
        let fixtureRoot =
            realPackageRow?.nativeMessagingSmoke.trustedFixtureHostRootPath
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? rootURL.appendingPathComponent(
                    "NativeMessagingFixtureHosts",
                    isDirectory: true
                )
        let lookupPolicy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: fixtureRoot.path,
            extensionModuleEnabled: gate.managerAvailableInDeveloperPreview
        )
        let productPolicy = ChromeMV3NativeMessagingProductPolicy(
            extensionModuleEnabled: gate.managerAvailableInDeveloperPreview,
            nativeMessagingAllowedByProductPolicy: true,
            userConsentRequired: true,
            userConsentGranted: false
        )
        let policyStore = ChromeMV3NativeTrustedHostPolicyStore(
            rootURL: rootURL
        )
        let snapshot = policyStore.loadSnapshot(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let realPackageHostNames =
            realPackageRow?.nativeMessagingSmoke.hostNames ?? []
        let hostNames =
            nativeDeclared
                ? (
                    realPackageHostNames.isEmpty
                        ? [
                            ChromeMV3NativeMessagingFixtureHostBuilder
                                .passwordManagerFixtureHostName,
                        ]
                        : realPackageHostNames
                )
                : []
        let requirements = hostNames.map { hostName in
            requirement(
                hostName: hostName,
                record: record,
                nativeGranted: nativeGranted,
                lookupPolicy: lookupPolicy,
                productPolicy: productPolicy,
                trustedRecord:
                    snapshot.record(hostName: hostName)
                    ?? .unknown(
                        hostName: hostName,
                        extensionID: record.extensionID,
                        profileID: record.profileID
                    ),
                realPackageReadiness:
                    realPackageRow?.nativeMessagingSmoke.hostReadiness
                    .first { $0.hostName == hostName },
                gate: gate
            )
        }
        let discovery = ChromeMV3NativeHostDiscoveryPolicyReport.make(
            lookupPolicy: lookupPolicy,
            requestedHostNames: hostNames
        )
        return ChromeMV3ExtensionManagerTrustedNativeHostPanel(
            nativeMessagingPermissionDeclared: nativeDeclared,
            nativeMessagingPermissionGranted: nativeGranted,
            trustedHostPolicyAvailable:
                productPolicy.productGate.trustedHostPolicyAvailable,
            approvalRequired:
                productPolicy.productGate.trustedHostApprovalRequired,
            arbitraryHostLaunchAllowed: false,
            nativeHostScanningAllowed: false,
            discoveryReport: discovery,
            hostRequirements: requirements,
            diagnostics:
                uniqueSortedExtensionManager(
                    snapshot.diagnostics
                        + discovery.diagnostics
                        + [
                            nativeDeclared
                                ? "nativeMessaging permission is declared or optional in the extension manifest."
                                : "nativeMessaging permission is not declared.",
                            realPackageRow == nil
                                ? "Trusted native host panel uses the default developer-preview fixture root."
                                : "Trusted native host panel uses real-package fixture root diagnostics.",
                            "Trusted native host controls require explicit developer-preview user action.",
                            "Approval controls do not launch native hosts.",
                            "Arbitrary native host launch and arbitrary directory scanning remain disabled.",
                        ]
                )
        )
    }

    private static func trustedNativeHostRealPackageRow(
        _ row: ChromeMV3PasswordManagerRealPackageCompatibilityRow,
        matches record: ChromeMV3ExtensionLifecycleRecord,
        in report: ChromeMV3PasswordManagerRealPackageCompatibilityReport?
    ) -> Bool {
        if row.packagePath == record.sourcePath {
            return true
        }
        if let configuration = report?.targetConfigurations.first(where: {
            $0.targetID == row.targetID
        }) {
            if let unpacked = configuration.localUnpackedPath,
               record.sourcePath == unpacked
            {
                return true
            }
            if record.sourcePath.hasPrefix(
                configuration.explicitAllowedLocalRoot + "/"
            ) {
                return true
            }
        }
        let haystack = "\(record.displayName) \(record.sourcePath)"
            .lowercased()
        switch row.targetClass {
        case .bitwarden:
            return haystack.contains("bitwarden")
        case .onePassword:
            return haystack.contains("1password")
                || haystack.contains("onepassword")
        case .protonPass:
            return haystack.contains("proton")
        }
    }

    private static func requirement(
        hostName: String,
        record: ChromeMV3ExtensionLifecycleRecord,
        nativeGranted: Bool,
        lookupPolicy: ChromeMV3NativeHostLookupPolicy,
        productPolicy: ChromeMV3NativeMessagingProductPolicy,
        trustedRecord: ChromeMV3NativeTrustedHostApprovalRecord,
        realPackageReadiness:
            ChromeMV3PasswordManagerRealPackageNativeHostReadiness?,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerTrustedNativeHostRequirement {
        let lookup = lookupPolicy.lookupHost(named: hostName)
        let permissionState: ChromeMV3NativeMessagingPermissionState =
            nativeGranted ? .grantedByManifest : .missing
        let long = ChromeMV3NativeMessagingPreflightEvaluator.evaluate(
            input: ChromeMV3NativeMessagingPreflightInput(
                extensionID: record.extensionID,
                profileID: record.profileID,
                hostName: hostName,
                operationKind: .longLivedNativePort,
                sourceContext: .extensionPage,
                permissionState: permissionState,
                productPolicy: productPolicy,
                trustedHostPolicyRecord: trustedRecord
            ),
            lookupPolicy: lookupPolicy,
            lookupResult: lookup
        )
        let oneShot = ChromeMV3NativeMessagingPreflightEvaluator.evaluate(
            input: ChromeMV3NativeMessagingPreflightInput(
                extensionID: record.extensionID,
                profileID: record.profileID,
                hostName: hostName,
                operationKind: .oneShotNativeMessage,
                sourceContext: .extensionPage,
                permissionState: permissionState,
                productPolicy: productPolicy,
                trustedHostPolicyRecord: trustedRecord
            ),
            lookupPolicy: lookupPolicy,
            lookupResult: lookup
        )
        let canEvaluateManifest =
            lookup.status == .found
                && lookup.manifest?.isValid == true
                && gate.managerAvailableInDeveloperPreview
                && record.runtimeState.internalRuntimeEnabled
        let describedPack = ChromeMV3NativeMessagingFixturePackBuilder
            .describeExistingPack(
                targetID: "manager-\(record.extensionID)",
                fixtureRootPath:
                    lookupPolicy.locations.first {
                        $0.kind == .explicitTestRoot
                    }?.rootPath,
                hostNames: [hostName],
                extensionID: record.extensionID
            )
        let packRecord = describedPack.record(hostName: hostName)
        return ChromeMV3ExtensionManagerTrustedNativeHostRequirement(
            fixturePackID:
                realPackageReadiness?.fixturePackID
                    ?? describedPack.packID,
            fixtureRootPath:
                realPackageReadiness?.fixtureRootPath
                    ?? describedPack.fixtureRootPath,
            fixturePackGeneratedState:
                realPackageReadiness?.fixturePackGeneratedState
                    ?? packRecord?.generatedState
                    ?? describedPack.generatedState,
            fixturePackValidatedState:
                realPackageReadiness?.fixturePackValidatedState
                    ?? packRecord?.validatedState
                    ?? describedPack.validatedState,
            hostNameSource:
                realPackageReadiness?.hostNameSource
                    ?? "managerManifestSummary",
            hostName: hostName,
            requiredBy:
                "runtime.connect" + "Native/runtime.send"
                + "NativeMessage",
            manifestStatus: lookup.status,
            manifestPath: lookup.manifest?.sourceLocation.manifestPath,
            executablePath: lookup.manifest?.path,
            resolvedExecutablePath:
                lookup.manifest?.path.map {
                    URL(fileURLWithPath: $0)
                        .resolvingSymlinksInPath()
                        .standardizedFileURL
                        .path
                },
            allowedOrigins:
                lookup.manifest?.allowedOrigins.map(\.rawValue).sorted()
                    ?? [],
            allowedOriginsSource:
                realPackageReadiness?.allowedOriginsSource
                    ?? (lookup.manifest == nil
                        ? "notEvaluated"
                        : "fixtureManifest.allowed_origins"),
            allowedOriginsState: realPackageReadiness?.allowedOriginsState,
            trustedHostState: trustedRecord.trustState,
            trustedForDeveloperPreview:
                trustedRecord.trustedForDeveloperPreview,
            canSendNativeMessageNow: oneShot.canSendNativeMessageNow,
            canConnectNativeNow: long.canConnectNativeNow,
            processLaunchAllowedNow:
                long.processLaunchAllowedNow
                    || oneShot.processLaunchAllowedNow,
            fixtureExchangeState:
                realPackageReadiness?.exchangeResult.state,
            fixtureExchangeAttempted:
                realPackageReadiness?.exchangeResult.attempted ?? false,
            realVendorHostDiscoveryBlocked: true,
            arbitraryHostLaunchAllowed: false,
            controls:
                controls(
                    hostName: hostName,
                    canApprove: canEvaluateManifest,
                    trustedRecord: trustedRecord
                ),
            blockers:
                uniqueSortedExtensionManager(
                    long.blockers + oneShot.blockers
                ),
            diagnostics:
                uniqueSortedExtensionManager(
                    lookup.diagnostics
                        + trustedRecord.diagnostics
                        + long.diagnostics
                        + oneShot.diagnostics
                        + describedPack.diagnostics
                        + (packRecord?.diagnostics ?? [])
                        + (realPackageReadiness?.diagnostics ?? [])
                )
        )
    }

    private static func controls(
        hostName: String,
        canApprove: Bool,
        trustedRecord: ChromeMV3NativeTrustedHostApprovalRecord
    ) -> [ChromeMV3ExtensionManagerTrustedNativeHostControlDescriptor] {
        [
            control(
                kind: .approveForDeveloperPreview,
                hostName: hostName,
                title: "Approve trusted host",
                available: canApprove
                    && trustedRecord.trustedForDeveloperPreview == false,
                warning:
                    "Approving trusts this executable only for developer-preview fixture native messaging."
            ),
            control(
                kind: .deny,
                hostName: hostName,
                title: "Deny host",
                available: trustedRecord.trustState != .userDenied,
                warning: "Denying keeps native messaging blocked."
            ),
            control(
                kind: .revoke,
                hostName: hostName,
                title: "Revoke host",
                available: trustedRecord.trustState
                    == .trustedForDeveloperPreview,
                warning:
                    "Revoking disconnects existing native Ports in the runtime owner."
            ),
            control(
                kind: .reset,
                hostName: hostName,
                title: "Reset host policy",
                available: trustedRecord.trustState != .unknown,
                warning: "Reset removes the persisted trusted-host state."
            ),
        ].sorted {
            if $0.kind != $1.kind { return $0.kind < $1.kind }
            return $0.hostName < $1.hostName
        }
    }

    private static func control(
        kind: ChromeMV3NativeTrustedHostControlKind,
        hostName: String,
        title: String,
        available: Bool,
        warning: String
    ) -> ChromeMV3ExtensionManagerTrustedNativeHostControlDescriptor {
        ChromeMV3ExtensionManagerTrustedNativeHostControlDescriptor(
            id: "\(kind.rawValue):\(hostName)",
            kind: kind,
            hostName: hostName,
            title: title,
            available: available,
            warning: warning,
            diagnostics: [
                "Trusted-host control requires explicit user action.",
                "Trusted-host control never launches a native host.",
                "Executable path and allowed_origins must be inspected before approval.",
            ]
        )
    }
}

struct ChromeMV3ExtensionManagerTrustedNativeHostActionResult:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3NativeTrustedHostControlKind
    var hostName: String
    var succeeded: Bool
    var record: ChromeMV3NativeTrustedHostApprovalRecord?
    var snapshot: ChromeMV3NativeTrustedHostPolicySnapshot?
    var preflight: ChromeMV3NativeMessagingOperationPreflight?
    var serviceWorkerWakeAttempted: Bool
    var nativeHostLaunchAttempted: Bool
    var diagnostics: [String]
}

struct ChromeMV3ExtensionManagerServiceWorkerTrialReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var targetID: String
    var realPackageSource: ChromeMV3PasswordManagerRealPackageSource
    var gateState:
        ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateState
    var gateSource:
        ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource
    var listenerRegistrationCaptureStatus: String
    var capturedListenerFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var importScriptsResult: String
    var importScriptsResolvedCount: Int
    var importedScriptPaths: [String]
    var importScriptsBlockers: [ChromeMV3ServiceWorkerJSImportScriptsBlocker]
    var computedImportScriptsResult: String
    var dynamicImportRewriteResult: String
    var cryptoCapabilityResult: String
    var cryptoOperationSummary: [String]
    var cryptoSubtleSupportedAlgorithms: [String]
    var cryptoSubtleBlockedAlgorithms: [String]
    var i18nCapabilityResult: String
    var i18nOperationSummary: [String]
    var alarmPolicyResult: String
    var alarmRecordSummary: [String]
    var alarmOperationSummary: [String]
    var alarmDispatchResult: String
    var workerNavigatorUserAgentResult: String
    var deviceFailureClassification:
        ChromeMV3PasswordManagerRealPackageDeviceFailureClassification
    var deviceFailureDetail: String
    var precedingChromeAPICalls: [String]
    var storageOperationSummary: [String]
    var runtimeSendMessagePolicyResult: String
    var runtimeSendMessageSummary: [String]
    var runtimeLastErrorObjectShapeResult: String
    var runtimeLastErrorCallbackLifecycleResult: String
    var workerGlobalEventTargetResult: String
    var workerGlobalEventSummary: [String]
    var fetchClassificationResult: String
    var fetchClassificationSummary: [String]
    var workerWindowFailureClassification: String
    var timerPolicyResult: String
    var timerShimResult: String
    var moduleWorkerReadinessResult: String
    var dynamicImportShapeSummary: [String]
    var moduleWorkerGraphSummary: [String]
    var timerAsyncAPISummary: [String]
    var listenerRegistrationSourceSummary: [String]
    var remainingDynamicImportModuleBlockers: [String]
    var staticVsExecutionDeltaStatus:
        ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDeltaStatus
    var dispatchSmokeResult: String
    var dispatchSummaries: [String]
    var nextBlockerClassification:
        ChromeMV3PasswordManagerRealPackageNextBlockerClassification
    var nextBlockerDetail: String
    var nextRecommendedFix: String
    var bitwardenE2ESmoke:
        ChromeMV3PasswordManagerRealPackageE2ESmoke?
    var idleTeardownResult: String
    var hardTimeoutTeardownResult: String
    var blockers: [String]
    var defaultOffDisclaimer: String

    static func latest(
        rootURL: URL,
        record: ChromeMV3ExtensionLifecycleRecord
    ) -> ChromeMV3ExtensionManagerServiceWorkerTrialReportSummary? {
        guard
            let report =
                ChromeMV3PasswordManagerRealPackageCompatibilityReportWriter
                .latestReport(rootURL: rootURL),
            let row = report.rows.first(where: {
                $0.serviceWorkerEventReadiness.declarationReadiness?
                    .extensionID == record.extensionID
                    && $0.serviceWorkerEventReadiness.declarationReadiness?
                    .profileID == record.profileID
            }),
            let gate = row.serviceWorkerEventReadiness.trialGateRecords.last
        else {
            return nil
        }
        let readiness = row.serviceWorkerEventReadiness
        return ChromeMV3ExtensionManagerServiceWorkerTrialReportSummary(
            targetID: row.targetID,
            realPackageSource: row.packageSource,
            gateState: gate.state,
            gateSource: gate.source,
            listenerRegistrationCaptureStatus:
                readiness.actualListenerRegistrationCaptureStatus,
            capturedListenerFamilies: readiness.capturedListenerFamilies,
            importScriptsResult: readiness.importScriptsResult,
            importScriptsResolvedCount: readiness.importScriptsResolvedCount,
            importedScriptPaths: readiness.importedScriptPaths,
            importScriptsBlockers: readiness.importScriptsBlockers,
            computedImportScriptsResult:
                readiness.computedImportScriptsResult,
            dynamicImportRewriteResult: readiness.dynamicImportRewriteResult,
            cryptoCapabilityResult: readiness.cryptoCapabilityResult,
            cryptoOperationSummary: readiness.cryptoOperationSummary,
            cryptoSubtleSupportedAlgorithms:
                readiness.cryptoSubtleSupportedAlgorithms,
            cryptoSubtleBlockedAlgorithms:
                readiness.cryptoSubtleBlockedAlgorithms,
            i18nCapabilityResult: readiness.i18nCapabilityResult,
            i18nOperationSummary: readiness.i18nOperationSummary,
            alarmPolicyResult: readiness.alarmPolicyResult,
            alarmRecordSummary:
                readiness.alarmRecords.map {
                    "\($0.name):scheduled=\($0.scheduledTime):delay=\($0.delayInMinutes.map { String($0) } ?? "none"):period=\($0.periodInMinutes.map { String($0) } ?? "none"):replaced=\($0.replacedExistingAlarm)"
                }.sorted(),
            alarmOperationSummary: readiness.alarmOperationSummary,
            alarmDispatchResult: readiness.alarmDispatchResult,
            workerNavigatorUserAgentResult:
                readiness.workerNavigatorUserAgentResult,
            deviceFailureClassification:
                readiness.deviceFailureClassification,
            deviceFailureDetail: readiness.deviceFailureDetail,
            precedingChromeAPICalls: readiness.precedingChromeAPICalls,
            storageOperationSummary: readiness.storageOperationSummary,
            runtimeSendMessagePolicyResult:
                readiness.runtimeSendMessagePolicyResult,
            runtimeSendMessageSummary:
                readiness.runtimeSendMessageSummary,
            runtimeLastErrorObjectShapeResult:
                readiness.runtimeLastErrorObjectShapeResult,
            runtimeLastErrorCallbackLifecycleResult:
                readiness.runtimeLastErrorCallbackLifecycleResult,
            workerGlobalEventTargetResult:
                readiness.workerGlobalEventTargetResult,
            workerGlobalEventSummary: readiness.workerGlobalEventSummary,
            fetchClassificationResult: readiness.fetchClassificationResult,
            fetchClassificationSummary: readiness.fetchClassificationSummary,
            workerWindowFailureClassification:
                readiness.workerWindowFailureClassification,
            timerPolicyResult:
                "localExperimental=\(readiness.jsExecutionPolicy.timersAvailableInLocalExperimentalGate), default=\(readiness.jsExecutionPolicy.timersAvailableByDefault), wallClock=\(readiness.jsExecutionPolicy.wallClockTimersAllowed), polling=\(readiness.jsExecutionPolicy.pollingAllowed)",
            timerShimResult: readiness.timerShimResult,
            moduleWorkerReadinessResult:
                readiness.moduleWorkerReadinessResult,
            dynamicImportShapeSummary:
                readiness.dependencyInventory.dynamicImportExpressions.map {
                    "\($0.sourcePath):\($0.line):\($0.shape.rawValue)"
                }.sorted(),
            moduleWorkerGraphSummary:
                [
                    "module=\(readiness.dependencyInventory.moduleWorkerInventory.declaredAsModuleWorker)",
                    "staticImports=\(readiness.dependencyInventory.moduleWorkerInventory.staticImportDeclarations.count)",
                    "exports=\(readiness.dependencyInventory.moduleWorkerInventory.exportUsageLocations.count)",
                    "topLevelAwait=\(readiness.dependencyInventory.moduleWorkerInventory.topLevelAwaitDetected)",
                ],
            timerAsyncAPISummary:
                readiness.dependencyInventory.asyncAPIInventory.totals.map {
                    "\($0.api.rawValue)=\($0.count)"
                }.sorted(),
            listenerRegistrationSourceSummary:
                [
                    "main=\(readiness.dependencyInventory.listenerRegistrationMap.mainWorkerCount)",
                    "importScripts=\(readiness.dependencyInventory.listenerRegistrationMap.importScriptsDependencyCount)",
                    "dynamic=\(readiness.dependencyInventory.listenerRegistrationMap.dynamicImportCandidateCount)",
                    "module=\(readiness.dependencyInventory.listenerRegistrationMap.moduleDependencyCandidateCount)",
                    "unknownComputed=\(readiness.dependencyInventory.listenerRegistrationMap.unknownComputedDependencyReferenceCount)",
                ],
            remainingDynamicImportModuleBlockers:
                uniqueSortedExtensionManager(
                    (readiness.resourceLoadResult?.blockers.compactMap {
                        blocker in
                        switch blocker {
                        case .dynamicImportUnsupported,
                             .moduleWorkerUnsupported,
                             .staticModuleImportUnsupported:
                            return blocker.rawValue
                        default:
                            return nil
                        }
                    } ?? [])
                        + readiness.importScriptsBlockers.compactMap {
                            blocker in
                            switch blocker {
                            case .dynamicImportUnsupported,
                                 .staticModuleImportUnsupported:
                                return "importScripts.\(blocker.rawValue)"
                            default:
                                return nil
                            }
                        }
                ),
            staticVsExecutionDeltaStatus:
                readiness.staticVsExecutionDelta.status,
            dispatchSmokeResult: readiness.dispatchSmokeResult,
            dispatchSummaries:
                readiness.actualDispatchResults.map {
                    "\($0.source.rawValue):\($0.resultKind.rawValue)"
                }.sorted(),
            nextBlockerClassification:
                readiness.nextBlockerClassification,
            nextBlockerDetail: readiness.nextBlockerDetail,
            nextRecommendedFix: readiness.nextRecommendedFix,
            bitwardenE2ESmoke:
                row.targetClass == .bitwarden ? row.bitwardenE2ESmoke : nil,
            idleTeardownResult: readiness.idleTeardownResult,
            hardTimeoutTeardownResult: readiness.hardTimeoutTeardownResult,
            blockers: readiness.blockers,
            defaultOffDisclaimer:
                "Read-only scoped trial report. Viewing manager detail never executes a worker; stable runtimeLoadable remains false."
        )
    }
}

struct ChromeMV3ExtensionManagerServiceWorkerReadinessPanel:
    Codable,
    Equatable,
    Sendable
{
    var readiness: ChromeMV3ServiceWorkerDeclarationReadiness?
    var jsExecutionPolicy: ChromeMV3ServiceWorkerJSExecutionPolicy
    var jsExecutionHarnessStatus: String
    var listenerRegistrationCaptureStatus: String
    var capturedListenerFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var jsExecutionTeardownState: String
    var lastEventResult: ChromeMV3ServiceWorkerEventRoutingRecord?
    var listenerCoverage: [ChromeMV3ServiceWorkerListenerCoverage]
    var latestRealPackageTrialReport:
        ChromeMV3ExtensionManagerServiceWorkerTrialReportSummary?
    var idleTimeoutState: String
    var hardTimeoutState: String
    var defaultOffLocalExperimentalDisclaimer: String
    var blockers: [String]
    var remediation: [String]
    var diagnostics: [String]

    static func make(
        rootURL: URL,
        record: ChromeMV3ExtensionLifecycleRecord,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ExtensionManagerServiceWorkerReadinessPanel {
        let manifest = loadManifest(from: record)
        let active = record.activeGeneratedVersionID.flatMap { activeID in
            record.generatedBundleVersions.first { $0.id == activeID }
        }
        let readiness = manifest.map {
            ChromeMV3ServiceWorkerDeclarationReadinessEvaluator.evaluate(
                manifest: $0,
                generatedBundleRootURL:
                    active.map {
                        URL(
                            fileURLWithPath: $0.generatedBundleRootPath,
                            isDirectory: true
                        )
                    },
                extensionID: record.extensionID,
                profileID: record.profileID,
                moduleState:
                    gate.managerAvailableInDeveloperPreview
                        ? .enabled : .disabled,
                extensionEnabled: record.runtimeState.internalRuntimeEnabled,
                localExperimentalGateAllowed: false
            )
        }
        let jsExecutionPolicy = ChromeMV3ServiceWorkerJSExecutionPolicy.evaluate(
            moduleState:
                gate.managerAvailableInDeveloperPreview ? .enabled : .disabled,
            extensionEnabled: record.runtimeState.internalRuntimeEnabled,
            localExperimentalGateAllowed: false,
            generatedBundleRecordAvailable: active != nil
        )
        let blockers =
            uniqueSortedExtensionManager(
                readiness?.blockers.map(\.rawValue)
                    ?? ["manifestSnapshotUnavailable"]
            )
        return ChromeMV3ExtensionManagerServiceWorkerReadinessPanel(
            readiness: readiness,
            jsExecutionPolicy: jsExecutionPolicy,
            jsExecutionHarnessStatus:
                "notConstructed: manager detail is read-only and the local experimental gate remains closed.",
            listenerRegistrationCaptureStatus:
                "notAttempted: no manager-created JavaScript execution harness.",
            capturedListenerFamilies: [],
            jsExecutionTeardownState:
                "notApplicable: manager detail created no JavaScript surface or lifecycle session.",
            lastEventResult: nil,
            listenerCoverage: readiness?.listenerCoverage ?? [],
            latestRealPackageTrialReport:
                ChromeMV3ExtensionManagerServiceWorkerTrialReportSummary
                .latest(rootURL: rootURL, record: record),
            idleTimeoutState:
                "No manager-created lifecycle session; idle is test-controlled.",
            hardTimeoutState:
                "No manager-created lifecycle session; hard timeout is test-controlled.",
            defaultOffLocalExperimentalDisclaimer:
                "Service-worker routing is local experimental/default-off; stable runtimeLoadable remains false.",
            blockers: blockers,
            remediation:
                uniqueSortedExtensionManager(
                    blockers.map { "Resolve service-worker readiness blocker: \($0)." }
                        + [
                            "Keep localExperimentalGateAllowed false unless an explicit scoped test creates a shared lifecycle session.",
                            "Keep importScripts resolution read-only here; scoped trials report generated-bundle imports without manager detail executing a worker.",
                        ]
                ),
            diagnostics:
                uniqueSortedExtensionManager(
                    (readiness?.diagnostics ?? [])
                        + [
                            manifest == nil
                                ? "Manifest snapshot could not be loaded for service-worker readiness."
                                : "Manager detail evaluated service-worker declaration/readiness without constructing a session.",
                            "lastEventResult is nil until a scoped local experimental runtime event is routed.",
                            "Actual JavaScript listener registration capture is not attempted by manager detail.",
                            "importScripts policy is displayed from policy data only; manager detail does not construct the resolver.",
                            "A previously written scoped real-package trial report may be displayed read-only.",
                            "No permanent background page or timer is created by this panel.",
                        ]
                )
        )
    }

    private static func loadManifest(
        from record: ChromeMV3ExtensionLifecycleRecord
    ) -> ChromeMV3Manifest? {
        let url = URL(fileURLWithPath: record.manifestSnapshotPath)
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let snapshot = try? decoder.decode(
                ChromeMV3ManifestSnapshotRecord.self,
                from: data
            ) {
                return snapshot.normalizedManifest
            }
        }
        return try? ChromeMV3ManifestValidator.validateManifestFile(at: url)
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
    var manualSmokeAction:
        ChromeMV3ExtensionManagerManualSmokeActionRecord
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
    var trustedNativeHostPanel:
        ChromeMV3ExtensionManagerTrustedNativeHostPanel
    var serviceWorkerReadinessPanel:
        ChromeMV3ExtensionManagerServiceWorkerReadinessPanel
    var passwordManagerCompatibilitySummary:
        ChromeMV3PasswordManagerCompatibilityManagerSummary?
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
    var manualSmokeResult:
        ChromeMV3LocalExperimentalNormalTabManualSmokeResult?
    var manualSmokeArtifact:
        ChromeMV3ExtensionManagerManualSmokeArtifact?
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
            manualSmokeResult: nil,
            manualSmokeArtifact: nil,
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
            manualSmokeResult: nil,
            manualSmokeArtifact: nil,
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
            manualSmokeResult: nil,
            manualSmokeArtifact: nil,
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
            manualSmokeResult: nil,
            manualSmokeArtifact: nil,
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
            manualSmokeResult: nil,
            manualSmokeArtifact: nil,
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
            manualSmokeResult: nil,
            manualSmokeArtifact: nil,
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

    static func manualSmoke(
        result: ChromeMV3LocalExperimentalNormalTabManualSmokeResult?,
        artifact: ChromeMV3ExtensionManagerManualSmokeArtifact?,
        artifactPath: String?,
        status: ChromeMV3ExtensionManagerActionStatus
    ) -> ChromeMV3ExtensionManagerActionResult {
        ChromeMV3ExtensionManagerActionResult(
            action: .runBitwardenManualSmoke,
            status: status,
            lifecycleOperationResult: nil,
            report: nil,
            packageIntakeReport: nil,
            popupOptionsRunResult: nil,
            manualSmokeResult: result,
            manualSmokeArtifact: artifact,
            diagnosticsJSON: nil,
            blockedDiagnostics:
                result?.allowed == true
                    ? [.manualSmokeNotProductSupport]
                    : [
                        .manualSmokeUnavailable,
                        .manualSmokeNotProductSupport,
                    ],
            diagnostics:
                uniqueSortedExtensionManager(
                    (result?.diagnostics ?? [])
                        + [
                            artifactPath.map {
                                "Manual smoke artifact path: \($0)."
                            } ?? "Manual smoke artifact was not written.",
                            "Product/default runtime remains unavailable; this action is not a Bitwarden support claim.",
                        ]
                ),
            productFlags: .unavailable,
            mutatedLifecycle: false,
            runtimeAttachmentAttempted: false,
            runtimeObjectsCreated: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false
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
        let lastManualSmokeArtifact =
            ChromeMV3ExtensionManagerManualSmokeArtifactWriter.latestArtifact(
                rootURL: rootURL,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        let manualSmokeAction =
            ChromeMV3ExtensionManagerManualSmokeActionRecord.make(
                rootURL: rootURL,
                record: record,
                gate: gate,
                readiness: preflight.normalTabReadiness,
                lastArtifact: lastManualSmokeArtifact
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
            manualSmokeAction: manualSmokeAction,
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
            trustedNativeHostPanel:
                ChromeMV3ExtensionManagerTrustedNativeHostPanel.make(
                    rootURL: rootURL,
                    record: record,
                    manifestSummary: manifestSummary,
                    gate: gate
                ),
            serviceWorkerReadinessPanel:
                ChromeMV3ExtensionManagerServiceWorkerReadinessPanel.make(
                    rootURL: rootURL,
                    record: record,
                    gate: gate
                ),
            passwordManagerCompatibilitySummary:
                ChromeMV3PasswordManagerCompatibilityManagerSummary.make(
                    record: record,
                    report: report,
                    rootURL: rootURL
                ),
            actions: actionDescriptors(
                gate: gate,
                record: record,
                report: report,
                popupOptionsLaunchState: popupOptions,
                manualSmokeAction: manualSmokeAction
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
            ChromeMV3ProductPopupOptionsLaunchState? = nil,
        manualSmokeAction:
            ChromeMV3ExtensionManagerManualSmokeActionRecord? = nil
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
                popupOptionsLaunchState: popupOptionsLaunchState,
                manualSmokeAction: manualSmokeAction
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
            ChromeMV3ProductPopupOptionsLaunchState?,
        manualSmokeAction:
            ChromeMV3ExtensionManagerManualSmokeActionRecord?
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
        if action == .runBitwardenManualSmoke
            && manualSmokeAction?.available != true
        {
            unavailable.append(
                contentsOf:
                    manualSmokeAction?.unavailableDiagnostics
                    ?? [.manualSmokeUnavailable]
            )
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
             .closePopupOptions, .runBitwardenManualSmoke,
             .exportDiagnosticsJSON,
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
             .closePopupOptions, .runBitwardenManualSmoke,
             .exportDiagnosticsJSON:
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
        case .runBitwardenManualSmoke:
            return "Run Bitwarden Manual Smoke"
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

    @MainActor
    static func runBitwardenManualSmoke(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        gate: ChromeMV3ExtensionManagerGate,
        now: () -> Date = Date.init
    ) async -> ChromeMV3ExtensionManagerActionResult {
        guard gate.managerAvailableInDeveloperPreview else {
            return .blocked(
                action: .runBitwardenManualSmoke,
                diagnostics: gate.diagnostics
                    + [.manualSmokeLocalExperimentalGateClosed]
            )
        }
        let registry = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
        guard
            let record = registry.loadLifecycleRecord(
                profileID: profileID,
                extensionID: extensionID
            )
        else {
            return .blocked(
                action: .runBitwardenManualSmoke,
                diagnostics: [.recordMissing]
            )
        }
        let report = registry.latestEndToEndDiagnosticsReport(
            profileID: profileID,
            extensionID: extensionID
        )
        let preflight = ChromeMV3ProductEnablementPreflightSection.make(
            report: report,
            lifecycleRecord: record
        )
        let action = ChromeMV3ExtensionManagerManualSmokeActionRecord.make(
            rootURL: rootURL,
            record: record,
            gate: gate,
            readiness: preflight.normalTabReadiness,
            lastArtifact:
                ChromeMV3ExtensionManagerManualSmokeArtifactWriter
                .latestArtifact(
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        )
        guard action.available else {
            return .blocked(
                action: .runBitwardenManualSmoke,
                diagnostics: action.unavailableDiagnostics
            )
        }

        #if DEBUG
            guard #available(macOS 15.5, *) else {
                return .blocked(
                    action: .runBitwardenManualSmoke,
                    diagnostics: [
                        .make(
                            .manualSmokeUnavailable,
                            severity: .deferred,
                            message: "Manual normal-tab smoke requires macOS 15.5 WKContentWorld evaluation APIs.",
                            remediation: "Run the local experimental smoke on macOS 15.5 or newer."
                        ),
                    ]
                )
            }
            let request = manualSmokeRequest(
                record: record,
                report: report,
                gate: gate
            )
            let result = await
                ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
                .runManualNormalTabSmoke(request)
            let artifact =
                ChromeMV3ExtensionManagerManualSmokeArtifact.make(
                    result: result,
                    record: record,
                    generatedAt: now()
                )
            let artifactURL = try? ChromeMV3ExtensionManagerManualSmokeArtifactWriter
                .write(artifact, rootURL: rootURL)
            return .manualSmoke(
                result: result,
                artifact: artifactURL == nil ? nil : artifact,
                artifactPath: artifactURL?.path,
                status: artifactURL == nil
                    ? .failed
                    : (result.allowed ? .succeeded : .blocked)
            )
        #else
            return .blocked(
                action: .runBitwardenManualSmoke,
                diagnostics: [.manualSmokeLocalExperimentalGateClosed]
            )
        #endif
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

    private static func manualSmokeRequest(
        record: ChromeMV3ExtensionLifecycleRecord,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3LocalExperimentalNormalTabManualSmokeRequest {
        let active = activeGeneratedVersion(record: record, report: report)
        let generated =
            ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle
            .make(active?.generatedBundleRecord)
        let url = "https://sumi.local.test/login"
        let origin = ChromeMV3RuntimeMessagingURL.origin(from: url)
        let modeledRequest =
            ChromeMV3LocalExperimentalProgrammaticInjectionRequest(
                moduleState:
                    gate.managerAvailableInDeveloperPreview
                        ? .enabled : .disabled,
                localExperimentalGateAllowed:
                    gate.managerAvailableInDeveloperPreview,
                extensionEnabled: record.runtimeState.internalRuntimeEnabled,
                profileScopedExtensionLoaded:
                    record.lifecycleState != .uninstalled
                        && record.lifecycleState != .corrupt,
                generatedBundle: generated,
                packageRootPath: active?.generatedBundleRootPath,
                targetURL: url,
                syntheticLoginURL: url,
                tabID: 0,
                frameIDs: [0],
                allFrames: false,
                world: ChromeMV3ContentScriptWorld.isolated.rawValue,
                files: [
                    ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                        .bitwardenDetectFillBootstrapFile,
                ],
                functionSource: nil,
                arguments: [],
                injectImmediately: true,
                hostPermissionOrActiveTabAllowed: true
            )
        let attempt =
            ChromeMV3LocalExperimentalProgrammaticInjectionSession()
            .attempt(modeledRequest)
        let hostDecision = ChromeMV3HostAccessDecision(
            url: url,
            origin: origin,
            status: .allowed,
            grantSource: .activeTabGrant,
            hasHostAccess: true,
            allowedByHostPermission: false,
            allowedByOptionalHostPermission: false,
            allowedByActiveTab: true,
            matchingHostPatterns: ["activeTab:\(origin ?? "invalid")"],
            optionalHostPatternsThatCouldPrompt: [],
            invalidHostPatterns: [],
            unsupportedHostPatterns: [],
            deniedByPattern: false,
            revokedByPattern: false,
            wouldNeedPrompt: false,
            missingReason: .none,
            diagnostics: [
                "Explicit local experimental manager action models an activeTab grant for the synthetic origin only.",
            ]
        )
        let resolution = attempt.resourceResolutions.first
        let reviewedResource = ChromeMV3ProductNormalTabReviewedResource(
            reviewedScriptPath:
                ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                .bitwardenDetectFillBootstrapFile,
            generatedResourceHash: attempt.shapeAudit.reviewedBootstrapSHA256,
            generatedResourceFileSystemPath:
                resolution?.resolvedFileSystemPath,
            present:
                resolution?.status == .copiedGeneratedBundleFile
                    && attempt.shapeAudit.reviewedBootstrapSHA256 != nil,
            packageOwned:
                resolution?.status == .copiedGeneratedBundleFile,
            diagnostics:
                resolution?.diagnostics
                    ?? ["Reviewed generated-bundle resource was not resolved."]
        )
        let preflight =
            ChromeMV3ProductNormalTabReadinessPreflightEvaluator.evaluate(
                input: ChromeMV3ProductNormalTabReadinessPreflightInput(
                    profileID: record.profileID,
                    extensionID: record.extensionID,
                    tabID: "\(attempt.shapeAudit.tabID)",
                    documentID: "manager-bitwarden-manual-smoke-main-frame",
                    urlString: url,
                    moduleEnabled: gate.managerAvailableInDeveloperPreview,
                    extensionEnabled:
                        record.runtimeState.internalRuntimeEnabled,
                    profileEnabled:
                        record.lifecycleState != .uninstalled
                            && record.lifecycleState != .corrupt,
                    localExperimentalProductGateAllowed:
                        gate.managerAvailableInDeveloperPreview,
                    runtimeGateAllowsReadiness: true,
                    contentScriptRouteReady:
                        attempt.shapeAudit.contentScriptDOMInjectionPresent,
                    serviceWorkerRouteReady:
                        attempt.shapeAudit.packageShapeMatched,
                    tabSurface: .normalTab,
                    syntheticHTTPSOrigin: "https://sumi.local.test",
                    frameID: 0,
                    isTopFrame: true,
                    contentWorld: .isolated,
                    hostAccessDecision: hostDecision,
                    reviewedResource: reviewedResource,
                    teardownPending: false
                )
            )
        let plan = ChromeMV3ProductNormalTabReviewedFileInjectionPlan.make(
            preflight: preflight
        )
        return ChromeMV3LocalExperimentalNormalTabManualSmokeRequest(
            preflight: preflight,
            injectionPlan: plan,
            modeledInjectionAttempt: attempt,
            dummyUsername: "sumi-test-user@example.test",
            dummyPassword: "sumi-test-password-not-secret",
            productDefaultRuntimeAvailable: false,
            matchAboutBlank: false,
            matchOriginAsFallback: false
        )
    }

    private static func activeGeneratedVersion(
        record: ChromeMV3ExtensionLifecycleRecord,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?
    ) -> ChromeMV3GeneratedBundleVersionRecord? {
        if let activeID = record.activeGeneratedVersionID,
           let recordVersion = record.generatedBundleVersions.first(where: {
               $0.id == activeID
           })
        {
            return recordVersion
        }
        if let reportVersion = report?.generatedBundleVersionState.last(where: {
            $0.state == .active || $0.state == .rollbackActive
        }) ?? report?.generatedBundleVersionState.last {
            return reportVersion
        }
        return record.generatedBundleVersions.last {
            $0.state == .active || $0.state == .rollbackActive
        } ?? record.generatedBundleVersions.last
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

extension ChromeMV3EndToEndInstallDiagnosticsReport {
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
        var onRunPermissionControl:
            ((
                ChromeMV3ExtensionManagerPermissionControlKind,
                String,
                String,
                String
            ) -> Void)?
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
                    .disabled(
                        !listViewModel.gate.localArchiveImportAvailable
                            || onImportArchive == nil
                    )

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
                        passwordManagerSummary(selectedDetail)
                        preflightSummary(selectedDetail)
                        popupOptionsSummary(selectedDetail)
                        serviceWorkerSummary(selectedDetail)
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

        @ViewBuilder
        private func passwordManagerSummary(
            _ detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> some View {
            if let summary = detail.passwordManagerCompatibilitySummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password Manager Compatibility")
                        .font(.callout.weight(.semibold))
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        fact("Target", summary.targetDisplayName)
                        fact("Readiness", summary.targetStatus.rawValue)
                        fact(
                            "Native Host",
                            summary.nativeHostRequired
                                ? (summary.nativeHostName ?? "required")
                                : "not required"
                        )
                        fact(
                            "Trust",
                            summary.trustedHostState.rawValue
                        )
                        if let rootState = summary.nativeFixtureRootState {
                            fact("Fixture Root", rootState.rawValue)
                        }
                        if let manifestState = summary.nativeManifestState {
                            fact("Host Manifest", manifestState.rawValue)
                        }
                        if let origins =
                            summary.nativeAllowedOriginsState
                        {
                            fact("Allowed Origins", origins.rawValue)
                        }
                        if let send =
                            summary.nativeSendNativeMessageReadiness
                        {
                            fact("send" + "NativeMessage", send)
                        }
                        if let connect =
                            summary.nativeConnectNativeReadiness
                        {
                            fact("connect" + "Native", connect)
                        }
                        if let exchange =
                            summary.nativeFixtureExchangeState
                        {
                            fact("Fixture Exchange", exchange.rawValue)
                        }
                        if let blocker = summary.nativeBlockerState {
                            fact("Native Blocker", blocker.rawValue)
                        }
                        if let source = summary.realPackageSource {
                            fact("Package Source", source.rawValue)
                        }
                        if let kind = summary.realPackageDetectedKind {
                            fact("Package Kind", kind.rawValue)
                        }
                        if let status = summary.realPackageTrialStatus {
                            fact("Real Trial", status.rawValue)
                        }
                    }
                    if summary.fixtureVsRealDeltaSummary.isEmpty == false {
                        Text(
                            summary.fixtureVsRealDeltaSummary
                                .prefix(3)
                                .joined(separator: "\n")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(summary.nextRecommendedFix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let remediation = summary.nativeRemediation {
                        Text(remediation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let disclaimer =
                        summary.realVendorHostDiscoveryBlockedDisclaimer
                    {
                        Text(disclaimer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(summary.notPublicSupportDisclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                let readiness = detail.productEnablementPreflight
                    .normalTabReadiness
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    fact(
                        "Normal-Tab Readiness",
                        readiness.preflight.eligible ? "eligible" : "blocked"
                    )
                    fact(
                        "Readiness Gate",
                        readiness.policy
                            .productNormalTabMV3ReadinessAvailableInLocalExperimentalGate
                            ? "local experimental" : "unavailable"
                    )
                    fact(
                        "Manual Smoke",
                        readiness.policy
                            .manualNormalTabSmokeAvailableInLocalExperimentalGate
                            ? (
                                readiness.manualSmokeReadiness
                                    .canAttemptFutureManualSmoke
                                    ? "allowed by gates"
                                    : "blocked by gates"
                            )
                            : "unavailable"
                    )
                    fact(
                        "Default Runtime",
                        readiness.policy.productDefaultRuntimeAvailable
                            ? "available" : "off"
                    )
                    fact(
                        "Reviewed File",
                        readiness.preflight.reviewedResource.present
                            ? "present" : "missing"
                    )
                    fact(
                        "Permission",
                        readiness.preflight.hostAccessDecision.status.rawValue
                    )
                    fact(
                        "Aux Surfaces",
                        readiness.policy.auxiliarySurfaceAllowed
                            ? "allowed" : "excluded"
                    )
                    fact(
                        "Teardown",
                        readiness.policy.teardownRequired
                            ? "required" : "not required"
                    )
                }
                Text(
                    readiness.preflight.blockers.map(\.rawValue)
                        .joined(separator: ", ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                let smokeAction = detail.manualSmokeAction
                let smokeArtifactState =
                    smokeAction.lastArtifactPath == nil ? "none" : "written"
                let smokeRetainedObjectCount =
                    smokeAction.lastRetainedObjectCount.map(String.init)
                    ?? "not run"
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    fact(
                        "Smoke Action",
                        smokeAction.available ? "available" : "unavailable"
                    )
                    fact(
                        "Manual Only",
                        smokeAction.manualOnly ? "yes" : "no"
                    )
                    fact(
                        "Last Smoke",
                        smokeAction.lastRunStatus?.rawValue ?? "not run"
                    )
                    fact(
                        "Artifact",
                        smokeArtifactState
                    )
                    fact(
                        "Smoke Teardown",
                        smokeAction.lastTeardownStatus ?? "not run"
                    )
                    fact(
                        "Retained",
                        smokeRetainedObjectCount
                    )
                }
                Text(manualSmokeActionSummary(smokeAction))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func manualSmokeActionSummary(
            _ smokeAction:
                ChromeMV3ExtensionManagerManualSmokeActionRecord
        ) -> String {
            var parts = [
                smokeAction.disabledReason
                    ?? smokeAction.enabledReason
                    ?? "No manual smoke action state is available.",
                smokeAction.notProductSupportWarning
            ]

            if let path = smokeAction.lastArtifactPath {
                parts.append("Last artifact: \(path).")
            }

            return parts.joined(separator: " ")
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

        private func serviceWorkerSummary(
            _ detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> some View {
            let panel = detail.serviceWorkerReadinessPanel
            let readiness = panel.readiness
            return VStack(alignment: .leading, spacing: 8) {
                Text("Service Worker")
                    .font(.callout.weight(.semibold))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    fact(
                        "Declared",
                        readiness?.declaresBackgroundServiceWorker == true
                            ? "yes" : "no"
                    )
                    fact(
                        "Worker File",
                        readiness?.serviceWorkerFileAvailable == true
                            ? "available" : "blocked"
                    )
                    fact(
                        "Wrapper",
                        readiness?.serviceWorkerWrapperAvailable == true
                            ? "available" : "blocked"
                    )
                    fact(
                        "Shim",
                        readiness?.wrapperShimAvailable == true
                            ? "available" : "blocked"
                    )
                    fact(
                        "Routing",
                        readiness?.eventRoutingAvailable == true
                            ? "available" : "blocked"
                    )
                    fact(
                        "Gate",
                        readiness?.localExperimentalGateState.rawValue
                            ?? "unavailable"
                    )
                    fact(
                        "Listeners",
                        "\(panel.listenerCoverage.filter { $0.listenerDetected }.count)/\(panel.listenerCoverage.count)"
                    )
                    fact(
                        "JS Harness",
                        panel.jsExecutionPolicy
                            .serviceWorkerJSExecutionAvailableInLocalExperimentalGate
                            ? "available" : "blocked"
                    )
                    fact(
                        "JS Surface",
                        panel.jsExecutionPolicy.executionSurface.rawValue
                    )
                    fact(
                        "importScripts",
                        panel.jsExecutionPolicy.importScriptsScope.rawValue
                    )
                    fact(
                        "runtime.lastError",
                        panel.jsExecutionPolicy
                            .runtimeLastErrorAvailableInLocalExperimentalGate
                            ? "callback-scoped" : "blocked"
                    )
                    fact(
                        "runtime.sendMessage",
                        panel.jsExecutionPolicy
                            .runtimeSendMessageAvailableInLocalExperimentalGate
                            ? "same-extension" : "blocked"
                    )
                    fact(
                        "Queued Callback Shim",
                        panel.jsExecutionPolicy
                            .timersAvailableInLocalExperimentalGate
                            ? "manual queue" : "blocked"
                    )
                    fact(
                        "Wall Clock Scheduling",
                        panel.jsExecutionPolicy.wallClockTimersAllowed
                            ? "allowed" : "blocked"
                    )
                    fact(
                        "Module Worker",
                        panel.jsExecutionPolicy.moduleWorkerImportAvailable
                            ? "available" : "blocked"
                    )
                    fact(
                        "Captured",
                        "\(panel.capturedListenerFamilies.count)"
                    )
                    fact(
                        "runtimeLoadable",
                        readiness.map { String($0.runtimeLoadable) }
                            ?? "false"
                    )
                }
                if let last = panel.lastEventResult {
                    Text(
                        "Last event: \(last.source.rawValue) - \(last.resultKind.rawValue)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text("Harness: \(panel.jsExecutionHarnessStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Listener capture: \(panel.listenerRegistrationCaptureStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let trial = panel.latestRealPackageTrialReport {
                    Text(
                        "Last scoped trial: \(trial.targetID) - \(trial.gateState.rawValue) - \(trial.staticVsExecutionDeltaStatus.rawValue)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text("Trial package: \(trial.realPackageSource.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Trial listeners: "
                            + trial.capturedListenerFamilies
                            .map(\.rawValue)
                            .joined(separator: ", ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Trial imports: \(trial.importScriptsResolvedCount)"
                            + (
                                trial.importedScriptPaths.isEmpty
                                    ? ""
                                    : " - "
                                        + trial.importedScriptPaths
                                        .prefix(3)
                                        .joined(separator: ", ")
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text("Trial importScripts: \(trial.importScriptsResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Trial computed importScripts: "
                            + trial.computedImportScriptsResult
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text("Queued callback policy: \(trial.timerPolicyResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Queued callback shim: \(trial.timerShimResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("WebCrypto slice: \(trial.cryptoCapabilityResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if trial.cryptoOperationSummary.isEmpty == false {
                        Text(
                            "Crypto operations: "
                                + trial.cryptoOperationSummary
                                .prefix(4)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("i18n slice: \(trial.i18nCapabilityResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if trial.i18nOperationSummary.isEmpty == false {
                        Text(
                            "i18n operations: "
                                + trial.i18nOperationSummary
                                .prefix(4)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(
                        "runtime.lastError shape: "
                            + trial.runtimeLastErrorObjectShapeResult
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "runtime.lastError lifecycle: "
                            + trial.runtimeLastErrorCallbackLifecycleResult
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Worker global events: "
                            + trial.workerGlobalEventTargetResult
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if trial.workerGlobalEventSummary.isEmpty == false {
                        Text(
                            "Worker event operations: "
                                + trial.workerGlobalEventSummary
                                .prefix(4)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Fetch policy: \(trial.fetchClassificationResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if trial.fetchClassificationSummary.isEmpty == false {
                        Text(
                            "Fetch calls: "
                                + trial.fetchClassificationSummary
                                .prefix(4)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(
                        "Worker window: "
                            + trial.workerWindowFailureClassification
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Trial dynamic rewrite: "
                            + trial.dynamicImportRewriteResult
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if trial.dynamicImportShapeSummary.isEmpty == false {
                        Text(
                            "Dynamic shapes: "
                                + trial.dynamicImportShapeSummary
                                .prefix(3)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Alarms slice: \(trial.alarmPolicyResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if trial.alarmRecordSummary.isEmpty == false {
                        Text(
                            "Alarm records: "
                                + trial.alarmRecordSummary
                                .prefix(4)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if trial.alarmOperationSummary.isEmpty == false {
                        Text(
                            "Alarm operations: "
                                + trial.alarmOperationSummary
                                .prefix(4)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Alarm dispatch: \(trial.alarmDispatchResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Module graph: "
                            + trial.moduleWorkerGraphSummary
                            .joined(separator: ", ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Module readiness: "
                            + trial.moduleWorkerReadinessResult
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if trial.timerAsyncAPISummary.isEmpty == false {
                        Text(
                            "Async APIs: "
                                + trial.timerAsyncAPISummary
                                .prefix(5)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(
                        "Listener sources: "
                            + trial.listenerRegistrationSourceSummary
                            .joined(separator: ", ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text("Trial dispatch: \(trial.dispatchSmokeResult)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "runtime.sendMessage: "
                            + trial.runtimeSendMessagePolicyResult
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "runtime.sendMessage calls: "
                            + trial.runtimeSendMessageSummary.joined(
                                separator: ", "
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if let smoke = trial.bitwardenE2ESmoke {
                        Text(
                            "Bitwarden E2E: \(smoke.status.rawValue) - \(smoke.nextBlockerClassification?.rawValue ?? "none") - \(smoke.nextBlocker)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden E2E routes: "
                                + smoke.messageRoutesTested.map {
                                    "\($0.route.rawValue):\($0.status.rawValue):\($0.deliveryStatus)"
                                }.joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden E2E service-worker listeners: "
                                + (smoke.serviceWorkerCapturedListenerFamilies
                                    ?? [])
                                .map(\.rawValue)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden E2E service-worker routes: "
                                + smoke.messageRoutesTested
                                .filter {
                                    $0.selectedServiceWorkerListenerFamily
                                        != nil
                                }
                                .map {
                                    "\($0.route.rawValue)=\($0.deliveryStatus):\($0.selectedServiceWorkerListenerFamily?.rawValue ?? "none"):\($0.serviceWorkerRouteReason ?? "none")"
                                }
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden E2E endpoints: total=\(smoke.endpointRegistryState.endpointCount), active=\(smoke.endpointRegistryState.activeEndpointCount), message=\(smoke.endpointRegistryState.messageListenerEndpointCount), connect=\(smoke.endpointRegistryState.connectListenerEndpointCount)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden E2E delivery: "
                                + smoke.messageRoutesTested
                                .filter {
                                    $0.route == .popupTabsSendMessage
                                        || $0.route == .popupTabsConnect
                                }
                                .map {
                                    "\($0.route.rawValue)=\($0.deliveryStatus)"
                                }
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden E2E endpoint metadata: "
                                + smoke.endpointRegistryState.endpointMetadata
                                .map {
                                    "\($0.endpointID):tab=\($0.tabID):frame=\($0.frameID):document=\($0.documentID):host=\($0.hostPermissionSource.rawValue):scope=\($0.frameScope.rawValue)"
                                }
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden detect/fill smoke: \(smoke.detectFillSmoke.status.rawValue) - \(smoke.detectFillSmoke.nextBlockerClassification?.rawValue ?? "none") - \(smoke.detectFillSmoke.nextBlocker)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            verbatim:
                            "Bitwarden programmatic injection: allowed=\(smoke.detectFillSmoke.programmaticInjectionAttempt.allowed); api=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.apiUsed); files=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.files.joined(separator: ",")); packageOwned=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.packageOwnedFiles); resources=\(smoke.detectFillSmoke.programmaticInjectionAttempt.resourceResolutions.map(\.status.rawValue).joined(separator: ",")); tab=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.tabID); frames=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.frameIDs.map(String.init).joined(separator: ",")); allFrames=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.allFrames); world=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.world); func=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.functionInjected); args=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.argumentCount); immediate=\(smoke.detectFillSmoke.programmaticInjectionAttempt.shapeAudit.injectImmediately); blocker=\(smoke.detectFillSmoke.programmaticInjectionAttempt.currentBlocker); activeAfterTeardown=\(smoke.detectFillSmoke.programmaticInjectionActiveAfterTeardownCount)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            verbatim:
                            "Bitwarden WebKit reviewed-bundle adapter: attempted=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.attempted); allowed=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.allowed); file=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.injectedReviewedFile ?? "none"); world=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.contentWorldName ?? "none"); isolated=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.isolatedWorldUsed); topFrameOnly=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.topFrameOnly); actualDOMChanged=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.dummyValuesWrittenByActualWebKitExecutedScript); webView=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.hiddenSyntheticWebViewCreated); nonPersistent=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.nonPersistentWebsiteDataStoreUsed); userScripts=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.userScriptAttachmentCount); handlers=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.scriptMessageHandlerAttachmentCount); teardown=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.teardown.completed); blocker=\(smoke.detectFillSmoke.webKitProgrammaticInjectionResult.currentBlocker)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden detect/fill routes: "
                                + smoke.detectFillSmoke.routeRecords.map {
                                    "\($0.purpose):\($0.status.rawValue):\($0.messageClassification.rawValue):domChanged=\($0.domChanged)"
                                }.joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden detect/fill contracts: "
                                + smoke.detectFillSmoke
                                .messageContractEvidence.map {
                                    "\($0.messageName)@\($0.sourcePath):\($0.role):attached=\($0.attachedByManifest)"
                                }
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden dummy fill payload: "
                                + smoke.detectFillSmoke
                                .dummyFillPayloadSummary
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden synthetic login DOM: "
                                + smoke.detectFillSmoke.domObservationResult
                                + "; before username=\(smoke.detectFillSmoke.domObservationBefore.usernameValue), password=\(smoke.detectFillSmoke.domObservationBefore.passwordValue)"
                                + "; after username=\(smoke.detectFillSmoke.domObservationAfter.usernameValue), password=\(smoke.detectFillSmoke.domObservationAfter.passwordValue)"
                                + "; dummy fill: "
                                + smoke.detectFillSmoke.dummyFillResult
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Bitwarden reverse tabs.sendMessage: "
                                + smoke.detectFillSmoke
                                .reverseTabsSendMessageClassification
                                .classificationSummary
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(
                        "Worker navigator: "
                            + trial.workerNavigatorUserAgentResult
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Device-path classification: \(trial.deviceFailureClassification.rawValue) - \(trial.deviceFailureDetail)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if trial.storageOperationSummary.isEmpty == false {
                        Text(
                            "Storage diagnostics: "
                                + trial.storageOperationSummary
                                .prefix(3)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if trial.importScriptsBlockers.isEmpty == false {
                        Text(
                            "Import blockers: "
                                + trial.importScriptsBlockers
                                .map(\.rawValue)
                                .prefix(3)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(
                        "\(trial.nextBlockerClassification == .dispatchDelivered ? "Dispatch state" : "Next blocker"): \(trial.nextBlockerClassification.rawValue) - \(trial.nextBlockerDetail)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(trial.nextRecommendedFix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(trial.defaultOffDisclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Idle: \(panel.idleTimeoutState)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Teardown: \(panel.jsExecutionTeardownState)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if panel.blockers.isEmpty == false {
                    Text("Blockers: " + panel.blockers.prefix(4).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(panel.defaultOffLocalExperimentalDisclaimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                if panel.controls.isEmpty == false {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(panel.controls.prefix(8)) { control in
                            Button(control.title) {
                                onRunPermissionControl?(
                                    control.kind,
                                    detail.listItem.profileID,
                                    detail.listItem.extensionID,
                                    control.value
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                control.available == false
                                    || onRunPermissionControl == nil
                            )
                            .help(control.blockerReason ?? control.title)
                        }
                    }
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
                        rendersDetailAction($0, detail: detail)
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
                        .help(detailActionHelp(descriptor, detail: detail))
                    }
                }
            }
        }

        private func rendersDetailAction(
            _ descriptor: ChromeMV3ExtensionManagerActionDescriptor,
            detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> Bool {
            switch descriptor.action {
            case .installUnpacked, .importZipArchive, .importCRXArchive,
                 .chromeWebStoreInstall, .openActionPopup, .openOptions,
                 .closePopupOptions:
                return false
            case .runBitwardenManualSmoke:
                return detail.gate.managerAvailableInDeveloperPreview
            default:
                return true
            }
        }

        private func detailActionHelp(
            _ descriptor: ChromeMV3ExtensionManagerActionDescriptor,
            detail: ChromeMV3ExtensionManagerDetailViewModel
        ) -> String {
            if descriptor.action == .runBitwardenManualSmoke {
                return detail.manualSmokeAction.notProductSupportWarning
            }
            return descriptor.unavailableDiagnostics.first?.message
                ?? descriptor.title
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
