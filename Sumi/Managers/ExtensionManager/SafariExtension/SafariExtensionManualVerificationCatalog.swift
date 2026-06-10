//
//  SafariExtensionManualVerificationCatalog.swift
//  Sumi
//
//  Documented manual E2E acceptance status per Safari import target.
//  Updated when dev-machine verification completes — not inferred at runtime.
//

import Foundation

enum SafariExtensionManualVerificationValue: String, Codable, CaseIterable, Sendable {
    case yes
    case no
    case pending
    case fixed
    case classified
    case notApplicable
    case notVerified
    case unknown
}

struct SafariExtensionManualVerificationRow: Codable, Equatable, Sendable {
    let importEnable: SafariExtensionManualVerificationValue
    let mv2WarningObserved: SafariExtensionManualVerificationValue
    let popup: SafariExtensionManualVerificationValue
    let signInSession: SafariExtensionManualVerificationValue
    let saveFlow: SafariExtensionManualVerificationValue
    let profileIsolation: SafariExtensionManualVerificationValue
    let desktopLaunchLoop: SafariExtensionManualVerificationValue
    let nativeMessagingProtocol: SafariExtensionManualVerificationValue
    let autofill: SafariExtensionManualVerificationValue
    let popupAnchoring: SafariExtensionManualVerificationValue
    let notes: String
}

enum SafariExtensionManualVerificationCatalog {
    static func row(forTargetKey targetKey: String) -> SafariExtensionManualVerificationRow {
        switch targetKey {
        case "raindrop":
            return SafariExtensionManualVerificationRow(
                importEnable: .yes,
                mv2WarningObserved: .notApplicable,
                popup: .yes,
                signInSession: .yes,
                saveFlow: .yes,
                profileIsolation: .yes,
                desktopLaunchLoop: .notApplicable,
                nativeMessagingProtocol: .notApplicable,
                autofill: .notApplicable,
                popupAnchoring: .yes,
                notes: "Cycle 9–11 verified import, popup, login, save; profile isolation Cycle 10."
            )
        case "bitwarden":
            return SafariExtensionManualVerificationRow(
                importEnable: .yes,
                mv2WarningObserved: .yes,
                popup: .yes,
                signInSession: .yes,
                saveFlow: .notApplicable,
                profileIsolation: .pending,
                desktopLaunchLoop: .no,
                nativeMessagingProtocol: .unknown,
                autofill: .fixed,
                popupAnchoring: .fixed,
                notes: """
                Inline UI: manifest content_scripts CSS + overlay iframes; tab-reconcile fix applied — \
                fixtures expected, GUI retest pending. NM companionAppProtocolUnknown; does not block overlay.
                """
            )
        case "1password":
            return SafariExtensionManualVerificationRow(
                importEnable: .notVerified,
                mv2WarningObserved: .notVerified,
                popup: .notVerified,
                signInSession: .notVerified,
                saveFlow: .notApplicable,
                profileIsolation: .notVerified,
                desktopLaunchLoop: .notVerified,
                nativeMessagingProtocol: .unknown,
                autofill: .pending,
                popupAnchoring: .notVerified,
                notes: """
                Inline UI: inject-content-scripts.js bootstrap via dynamic import (scripting granted — no \
                browser_specific_settings). Fixtures pending manual verification.
                """
            )
        case "proton-pass":
            return SafariExtensionManualVerificationRow(
                importEnable: .notVerified,
                mv2WarningObserved: .notApplicable,
                popup: .notVerified,
                signInSession: .notVerified,
                saveFlow: .notApplicable,
                profileIsolation: .notVerified,
                desktopLaunchLoop: .notVerified,
                nativeMessagingProtocol: .unknown,
                autofill: .classified,
                popupAnchoring: .notVerified,
                notes: """
                Inline UI: orchestrator manifest content_script + dropdown.html; scripting denied \
                (browser_specific_settings.safari) — dynamic background bootstrap blocked-by-platform.
                """
            )
        default:
            return SafariExtensionManualVerificationRow(
                importEnable: .notVerified,
                mv2WarningObserved: .notVerified,
                popup: .notVerified,
                signInSession: .notVerified,
                saveFlow: .notApplicable,
                profileIsolation: .notVerified,
                desktopLaunchLoop: .notVerified,
                nativeMessagingProtocol: .notVerified,
                autofill: .notVerified,
                popupAnchoring: .notVerified,
                notes: "Unknown target key."
            )
        }
    }
}
