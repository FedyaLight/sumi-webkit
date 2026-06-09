//
//  SafariExtensionNativeMessagingClassification.swift
//  Sumi
//
//  Precise native-messaging readiness buckets. Absence of Chrome-style host
//  manifests is informational — not a platform blocker.
//

import Foundation

/// Classification buckets for Safari / WebKit native app messaging readiness.
enum SafariExtensionNativeMessagingClassification: String, Codable, CaseIterable, Equatable, Sendable {
    /// Chrome `nativeMessaging` host manifests and subprocess stdio relay are not used on Safari.
    case noChromeStyleNativeHostRelay
    /// Public `WKWebExtensionControllerDelegate` send/connect hooks are available (macOS 15.4+).
    case wkWebExtensionAppMessagingAvailable
    /// Sumi delegate relay path is not wired or policy denies the session.
    case sumiRelayNotImplemented
    /// Companion host `.app` protocol for JSON relay is not documented / reverse-engineered.
    case companionAppProtocolUnknown
    /// Hard platform limitation with cited public-SDK evidence only.
    case platformBlocked
}

enum SafariExtensionNativeMessagingClassificationCatalog {
    /// Baseline classifications that apply to every Safari import target.
    static let globalBaseline: [SafariExtensionNativeMessagingClassification] = [
        .noChromeStyleNativeHostRelay,
        .wkWebExtensionAppMessagingAvailable,
    ]

    /// Password-manager targets that request native messaging to a companion `.app`.
    static let passwordManagerTargetKeys: Set<String> = [
        "bitwarden",
        "1password",
        "proton-pass",
    ]

    static func classifications(forTargetKey targetKey: String) -> [SafariExtensionNativeMessagingClassification] {
        var result = globalBaseline
        if passwordManagerTargetKeys.contains(targetKey) {
            result.append(.companionAppProtocolUnknown)
        }
        return result
    }

    static func globalReportClassifications(
        sumiRelayImplemented: Bool = true
    ) -> [SafariExtensionNativeMessagingClassification] {
        var result = globalBaseline
        if sumiRelayImplemented == false {
            result.append(.sumiRelayNotImplemented)
        }
        return result
    }
}
