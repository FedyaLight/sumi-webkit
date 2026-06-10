//
//  SafariExtensionInlineUIClassificationCatalog.swift
//  Sumi
//
//  Generic inline-UI capability classification per Safari import target.
//  Manifest-derived — not site-specific. Updated when infrastructure fixes land.
//

import Foundation

enum SafariExtensionInlineUIVerificationStatus: String, Codable, CaseIterable, Sendable {
    case fixed
    case pending
    case blockedByPlatform
    case classified
    case notApplicable
}

enum SafariExtensionInlineUIBlocker: String, Codable, CaseIterable, Sendable {
    case none
    /// `browser.scripting` denied for manifests declaring `browser_specific_settings.safari`.
    case scriptingPermissionDenied
    /// WebKit reports scripting/content-script registration APIs unsupported for Safari targets.
    case webKitScriptingAPIUnsupported
    /// Background dynamic content-script bootstrap depends on granted scripting (Proton Pass).
    case dynamicContentScriptBootstrapBlocked
    /// Companion desktop IPC not yet documented; fill may still work via vault cache.
    case companionAppProtocolUnknown
    /// Requires manual GUI verification on dev machine.
    case manualVerificationRequired
}

enum SafariExtensionInlineUIFixtureExpectation: String, Codable, CaseIterable, Sendable {
    /// Inline overlay/menu expected after field focus on controlled fixture.
    case expected
    /// Infrastructure ready; GUI retest not yet recorded.
    case pending
    /// Blocked by platform policy before fixture can be exercised.
    case blockedByPlatform
    /// Classify only — no site-specific runtime hacks.
    case classifiedOnly
    case notApplicable
}

struct SafariExtensionInlineUIFixtureMatrix: Codable, Equatable, Sendable {
    let localBasic: SafariExtensionInlineUIFixtureExpectation
    let autocomplete: SafariExtensionInlineUIFixtureExpectation
    let iframe: SafariExtensionInlineUIFixtureExpectation
    let realSite: SafariExtensionInlineUIFixtureExpectation
}

struct SafariExtensionInlineUIClassification: Codable, Equatable, Sendable {
    let expectedCapability: String
    let primaryBlocker: SafariExtensionInlineUIBlocker
    let verificationStatus: SafariExtensionInlineUIVerificationStatus
    let fixtures: SafariExtensionInlineUIFixtureMatrix
    let notes: String
}

enum SafariExtensionInlineUIClassificationCatalog {
    static func classification(forTargetKey targetKey: String) -> SafariExtensionInlineUIClassification {
        switch targetKey {
        case "bitwarden":
            return SafariExtensionInlineUIClassification(
                expectedCapability: """
                MV2 manifest content_scripts inject autofill.css (all_frames) and bootstrap JS; \
                inline menu via sandboxed overlay iframes (menu-button.html, menu-list.html).
                """,
                primaryBlocker: .none,
                verificationStatus: .fixed,
                fixtures: SafariExtensionInlineUIFixtureMatrix(
                    localBasic: .expected,
                    autocomplete: .expected,
                    iframe: .expected,
                    realSite: .classifiedOnly
                ),
                notes: """
                Post tab-reconcile attach-order fix (Cycle C): manifest CSS/JS should inject on open tabs. \
                Popup/fill paths wired; NM companionAppProtocolUnknown does not block inline overlay render. \
                Manual GUI retest pending for inlineUIRenderAttempted bucket.
                """
            )
        case "1password":
            return SafariExtensionInlineUIClassification(
                expectedCapability: """
                MV2 bootstrap content_script (inject-content-scripts.js) dynamically imports \
                inline/injected.js via extension-resource import(); manifest also injects injected.css. \
                Inline menu via web_accessible inline/menu/menu.html.
                """,
                primaryBlocker: .manualVerificationRequired,
                verificationStatus: .pending,
                fixtures: SafariExtensionInlineUIFixtureMatrix(
                    localBasic: .pending,
                    autocomplete: .pending,
                    iframe: .pending,
                    realSite: .classifiedOnly
                ),
                notes: """
                Manifest declares scripting but no browser_specific_settings — Sumi grants scripting \
                (shouldDenyAutoGrantForWebKitRuntime does not apply). Bootstrap uses dynamic import(), \
                not browser.scripting.executeScript. Companion NM unverified; not required for inline menu shell.
                """
            )
        case "proton-pass":
            return SafariExtensionInlineUIClassification(
                expectedCapability: """
                MV3 orchestrator.js manifest content_script (all_frames) hosts field detection and \
                INLINE_DROPDOWN messages; dropdown.html is web_accessible. Background may register \
                additional scripts via browser.scripting when LOAD_CONTENT_SCRIPT fires.
                """,
                primaryBlocker: .scriptingPermissionDenied,
                verificationStatus: .blockedByPlatform,
                fixtures: SafariExtensionInlineUIFixtureMatrix(
                    localBasic: .pending,
                    autocomplete: .pending,
                    iframe: .pending,
                    realSite: .classifiedOnly
                ),
                notes: """
                browser_specific_settings.safari present — Sumi denies scripting via \
                shouldDenyAutoGrantForWebKitRuntime; WebKit also lists browser.scripting.* as unsupported. \
                Manifest orchestrator path may still render dropdown on fixtures; dynamic bootstrap from \
                background is blocked-by-platform until WebKit grants scripting or extension drops MV3 scripting dep.
                """
            )
        default:
            return SafariExtensionInlineUIClassification(
                expectedCapability: "Unknown target",
                primaryBlocker: .none,
                verificationStatus: .notApplicable,
                fixtures: SafariExtensionInlineUIFixtureMatrix(
                    localBasic: .notApplicable,
                    autocomplete: .notApplicable,
                    iframe: .notApplicable,
                    realSite: .notApplicable
                ),
                notes: "No inline UI classification for target key \(targetKey)."
            )
        }
    }
}
