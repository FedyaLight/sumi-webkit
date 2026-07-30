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
                nativeMessagingProtocol: .yes,
                autofill: .yes,
                popupAnchoring: .yes,
                notes: """
                2026-07-30 maintainer verification: import, popup, sign-in, inline autofill, and tested \
                local biometric/native-messaging paths work. Profile-isolation release retest pending.
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
                importEnable: .yes,
                mv2WarningObserved: .notApplicable,
                popup: .yes,
                signInSession: .yes,
                saveFlow: .notApplicable,
                profileIsolation: .pending,
                desktopLaunchLoop: .no,
                nativeMessagingProtocol: .yes,
                autofill: .yes,
                popupAnchoring: .yes,
                notes: """
                2026-07-30 maintainer verification: import, popup sign-in, permissions, worker-driven \
                scripting, and inline autofill work. Profile-isolation release retest pending.
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
