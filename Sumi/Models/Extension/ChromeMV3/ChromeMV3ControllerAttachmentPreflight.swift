//
//  ChromeMV3ControllerAttachmentPreflight.swift
//  Sumi
//
//  Pure policy for future WebView configuration controller attachment.
//  This prompt keeps every real WebView configuration unattached.
//

import Foundation

struct ChromeMV3ControllerAttachmentPreflight:
    Codable,
    Equatable,
    Sendable
{
    var surface: ChromeMV3WebViewSurface
    var eligibilityStatus: ChromeMV3WebViewEligibilityStatus
    var moduleState: ChromeMV3ProfileHostModuleState
    var controllerState: ChromeMV3EmptyControllerOwnerState
    var futureEligibleForNormalBrowsing: Bool
    var canAttachControllerNow: Bool
    var wouldRequireEnabledModule: Bool
    var wouldRequireCreatedController: Bool
    var wouldRequireLoadableRuntime: Bool
    var wouldRequireNormalBrowsingSurface: Bool
    var wouldRequireSameControllerAsFutureContext: Bool
    var blockingReasons: [String]
    var riskNotes: [String]
}

enum ChromeMV3ControllerAttachmentPreflightEvaluator {
    static func evaluate(
        surface: ChromeMV3WebViewSurface,
        eligibility: ChromeMV3WebViewEligibility,
        controllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?,
        runtimePreflight: ChromeMV3RuntimePreflightResult?,
        moduleState: ChromeMV3ProfileHostModuleState
    ) -> ChromeMV3ControllerAttachmentPreflight {
        let moduleEnabled = moduleState == .enabled
        let controllerCreated = controllerDiagnostics?.controllerCreated ?? false
        let controllerState = controllerDiagnostics?.controllerState
            ?? .notCreated
        let runtimeReady = runtimePreflight?.runtimeLoadable ?? false
        let futureNormalBrowsingSurface =
            eligibility.status == .futureEligible
                && (
                    surface == .normalTab
                        || surface == .pinnedEssentialsLiveNormalBrowsing
                )
        let sameControllerRequired = futureNormalBrowsingSurface

        return ChromeMV3ControllerAttachmentPreflight(
            surface: surface,
            eligibilityStatus: eligibility.status,
            moduleState: moduleState,
            controllerState: controllerState,
            futureEligibleForNormalBrowsing: futureNormalBrowsingSurface,
            canAttachControllerNow: false,
            wouldRequireEnabledModule: moduleEnabled == false,
            wouldRequireCreatedController: controllerCreated == false,
            wouldRequireLoadableRuntime: runtimeReady == false,
            wouldRequireNormalBrowsingSurface:
                futureNormalBrowsingSurface == false,
            wouldRequireSameControllerAsFutureContext:
                sameControllerRequired,
            blockingReasons: blockingReasons(
                eligibility: eligibility,
                controllerDiagnostics: controllerDiagnostics,
                runtimePreflight: runtimePreflight,
                moduleEnabled: moduleEnabled,
                controllerCreated: controllerCreated,
                runtimeReady: runtimeReady,
                futureNormalBrowsingSurface: futureNormalBrowsingSurface
            ),
            riskNotes: riskNotes(
                eligibility: eligibility,
                futureNormalBrowsingSurface: futureNormalBrowsingSurface,
                sameControllerRequired: sameControllerRequired
            )
        )
    }

    private static func blockingReasons(
        eligibility: ChromeMV3WebViewEligibility,
        controllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?,
        runtimePreflight: ChromeMV3RuntimePreflightResult?,
        moduleEnabled: Bool,
        controllerCreated: Bool,
        runtimeReady: Bool,
        futureNormalBrowsingSurface: Bool
    ) -> [String] {
        var reasons = [
            "Controller attachment is blocked now; this prompt only performs preflight.",
        ]

        if moduleEnabled == false {
            reasons.append("The extensions module must be enabled before future controller attachment.")
        }

        if controllerCreated == false {
            reasons.append("A profile-scoped empty controller must exist before future attachment.")
        }

        if runtimeReady == false {
            reasons.append("Runtime loadability remains false, so future context loading and attachment stay blocked.")
        }

        if futureNormalBrowsingSurface == false {
            reasons.append(eligibility.reason)
        }

        if controllerDiagnostics?.canAttachToNormalTabsNow == false {
            reasons.append("Controller owner diagnostics keep normal-tab attachment blocked.")
        }

        if runtimePreflight?.canAttachToNormalTabsNow == false {
            reasons.append("Runtime preflight keeps normal-tab attachment blocked.")
        }

        return Array(Set(reasons.filter { $0.isEmpty == false })).sorted()
    }

    private static func riskNotes(
        eligibility: ChromeMV3WebViewEligibility,
        futureNormalBrowsingSurface: Bool,
        sameControllerRequired: Bool
    ) -> [String] {
        var notes = eligibility.requiredFuturePreconditions

        if futureNormalBrowsingSurface {
            notes.append("This surface is future-eligible only as a normal browsing WebView.")
            notes.append("Future tab WebViews must receive the same WKWebExtensionController as the future loaded context.")
        } else {
            notes.append("This surface must remain unattached unless a future prompt reclassifies it.")
        }

        if sameControllerRequired {
            notes.append("The same-controller requirement comes from WKWebExtensionTab.webView(for:).")
        }

        return Array(Set(notes.filter { $0.isEmpty == false })).sorted()
    }
}
