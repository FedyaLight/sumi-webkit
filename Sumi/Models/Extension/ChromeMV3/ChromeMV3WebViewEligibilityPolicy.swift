//
//  ChromeMV3WebViewEligibilityPolicy.swift
//  Sumi
//
//  Pure WebView-surface policy for future Chrome MV3 WebKit attachment.
//  This file intentionally stays Foundation-only and does not mutate WebView state.
//

import Foundation

enum ChromeMV3WebViewSurface: String, Codable, CaseIterable, Sendable {
    case syntheticTestConfiguration
    case normalTab
    case pinnedEssentialsLauncherMetadata
    case pinnedEssentialsLiveNormalBrowsing
    case peekGlancePreview
    case miniWindow
    case faviconDownload
    case downloadHelper
    case helperWebView
    case extensionOwnedPopup
    case extensionOwnedOptionsPage
    case webKitCreatedPopupOrNewWindow
}

enum ChromeMV3WebViewEligibilityStatus: String, Codable, Sendable {
    case futureEligible
    case futureEligibleThroughExtensionUIHostOnly
    case eligibleAfterPromotionAndReevaluation
    case notEligible
    case neverEligible
}

struct ChromeMV3WebViewEligibility: Codable, Equatable, Sendable {
    var surface: ChromeMV3WebViewSurface
    var status: ChromeMV3WebViewEligibilityStatus
    var reason: String
    var requiredFuturePreconditions: [String]
    var canAttachControllerNow: Bool

    var isFutureEligibleForNormalBrowsing: Bool {
        status == .futureEligible
    }
}

enum ChromeMV3WebViewEligibilityPolicy {
    static func evaluate(
        surface: ChromeMV3WebViewSurface,
        extensionModuleEnabled: Bool,
        profileHostActive: Bool
    ) -> ChromeMV3WebViewEligibility {
        switch surface {
        case .syntheticTestConfiguration:
            return eligibility(
                surface: surface,
                status: .neverEligible,
                reason: "Synthetic test configurations are not real browsing surfaces and must use the dedicated synthetic attachment gate.",
                requiredFuturePreconditions: []
            )

        case .normalTab:
            return normalBrowsingEligibility(
                surface: surface,
                extensionModuleEnabled: extensionModuleEnabled,
                profileHostActive: profileHostActive,
                reasonWhenEligible: "Normal tabs are the only general browsing surface that may be considered for future Chrome MV3 WebKit attachment."
            )

        case .pinnedEssentialsLiveNormalBrowsing:
            return normalBrowsingEligibility(
                surface: surface,
                extensionModuleEnabled: extensionModuleEnabled,
                profileHostActive: profileHostActive,
                reasonWhenEligible: "A pinned or Essentials live runtime is future-eligible only when it is backed by a real normal browsing WebView."
            )

        case .pinnedEssentialsLauncherMetadata:
            return eligibility(
                surface: surface,
                status: .neverEligible,
                reason: "Pinned or Essentials launcher identity and metadata are not browsing WebViews.",
                requiredFuturePreconditions: []
            )

        case .peekGlancePreview:
            return eligibility(
                surface: surface,
                status: .notEligible,
                reason: "Peek and Glance previews are not eligible by default.",
                requiredFuturePreconditions: [
                    "A future prompt must explicitly promote this preview model to a normal browsing surface before re-evaluation.",
                ]
            )

        case .miniWindow:
            return eligibility(
                surface: surface,
                status: .notEligible,
                reason: "Mini windows are not eligible by default.",
                requiredFuturePreconditions: [
                    "A future prompt must define mini-window extension semantics before re-evaluation.",
                ]
            )

        case .faviconDownload:
            return eligibility(
                surface: surface,
                status: .neverEligible,
                reason: "Favicon download WebViews are helper surfaces and must never host extension runtime.",
                requiredFuturePreconditions: []
            )

        case .downloadHelper:
            return eligibility(
                surface: surface,
                status: .neverEligible,
                reason: "Download helper WebViews are not user browsing surfaces and must never host extension runtime.",
                requiredFuturePreconditions: []
            )

        case .helperWebView:
            return eligibility(
                surface: surface,
                status: .neverEligible,
                reason: "Helper WebViews are not user browsing surfaces and must never host extension runtime.",
                requiredFuturePreconditions: []
            )

        case .extensionOwnedPopup:
            return eligibility(
                surface: surface,
                status: .futureEligibleThroughExtensionUIHostOnly,
                reason: "Extension-owned popup pages may only be considered through a future extension UI host, not through general browsing WebViews.",
                requiredFuturePreconditions: extensionUIHostFutureRequirements()
            )

        case .extensionOwnedOptionsPage:
            return eligibility(
                surface: surface,
                status: .futureEligibleThroughExtensionUIHostOnly,
                reason: "Extension-owned options pages may only be considered through a future extension UI host, not through general browsing WebViews.",
                requiredFuturePreconditions: extensionUIHostFutureRequirements()
            )

        case .webKitCreatedPopupOrNewWindow:
            return eligibility(
                surface: surface,
                status: .eligibleAfterPromotionAndReevaluation,
                reason: "WebKit-created popup and new-window helper surfaces are not eligible until Sumi promotes them to a normal tab or window and re-evaluates policy.",
                requiredFuturePreconditions: [
                    "Promote the surface to a real normal browsing tab or window.",
                    "Re-run profile host preflight and normal-tab eligibility before any future attachment.",
                ]
            )
        }
    }

    private static func normalBrowsingEligibility(
        surface: ChromeMV3WebViewSurface,
        extensionModuleEnabled: Bool,
        profileHostActive: Bool,
        reasonWhenEligible: String
    ) -> ChromeMV3WebViewEligibility {
        guard extensionModuleEnabled else {
            return eligibility(
                surface: surface,
                status: .notEligible,
                reason: "The extensions module is disabled.",
                requiredFuturePreconditions: [
                    "Enable the extensions module before considering Chrome MV3 runtime preflight.",
                ]
            )
        }

        guard profileHostActive else {
            return eligibility(
                surface: surface,
                status: .notEligible,
                reason: "No active Chrome MV3 profile host is available.",
                requiredFuturePreconditions: [
                    "Create an enabled profile-scoped Chrome MV3 host before considering future attachment.",
                ]
            )
        }

        return eligibility(
            surface: surface,
            status: .futureEligible,
            reason: reasonWhenEligible,
            requiredFuturePreconditions: [
                "Runtime preflight must clear all generated-rewritten variant blockers.",
                "A future WebKit controller must be explicitly created for the profile.",
                "A future loaded context must be associated with the same controller.",
                "Normal browsing WebViews must be reconfigured only through an explicit future loading prompt.",
            ]
        )
    }

    private static func extensionUIHostFutureRequirements() -> [String] {
        [
            "Define a dedicated extension-owned UI host.",
            "Load only through a verified future extension context.",
            "Keep popup and options pages separate from general normal-tab browsing.",
        ]
    }

    private static func eligibility(
        surface: ChromeMV3WebViewSurface,
        status: ChromeMV3WebViewEligibilityStatus,
        reason: String,
        requiredFuturePreconditions: [String]
    ) -> ChromeMV3WebViewEligibility {
        ChromeMV3WebViewEligibility(
            surface: surface,
            status: status,
            reason: reason,
            requiredFuturePreconditions: requiredFuturePreconditions.sorted(),
            canAttachControllerNow: false
        )
    }
}
