//
//  SafariExtensionPlatformBlocker.swift
//  Sumi
//
//  Formal platform blockers for Safari Web Extension compatibility.
//  No private SPI — evidence cites public SDK headers only.
//

import Foundation

/// Platform capabilities that block full PM / host-app parity on public APIs.
enum SafariExtensionPlatformBlocker: String, Codable, CaseIterable, Sendable {
    /// No public WebKit API relays extension JSON to a third-party host `.app`.
    case hostApplicationMessageRelay

    var summary: String {
        switch self {
        case .hostApplicationMessageRelay:
            return "Public WebKit delegate does not relay extension messages to third-party host apps"
        }
    }

    /// Sanitized evidence for compatibility / acceptance reports (header citations, no secrets).
    var evidence: String {
        switch self {
        case .hostApplicationMessageRelay:
            return """
            WKWebExtensionControllerDelegate.h (macOS 15.4+, verified \(SafariExtensionHostRelaySDKProbeMetadata.probedSDK)): \
            sendMessage:toApplicationWithIdentifier:for:replyHandler: and connectUsingMessagePort:for:completionHandler: \
            place the embedding browser in the relay path; default appex-handler forwarding applies only when loaded from an appex bundle. \
            WKWebExtensionMessagePort.h exposes applicationIdentifier and sendMessage/disconnect only — no host-app IPC surface. \
            macOS 27.0 WebKit headers: no API_AVAILABLE(macos(26|27)) host-relay additions in WKWebExtension*.h. \
            Sumi returns hostRelayUnavailable (code 3) after NSWorkspace host wake.
            """
        }
    }

    /// Password-manager targets that require native messaging to the host app.
    static let passwordManagerTargets: Set<String> = [
        "bitwarden",
        "1password",
        "proton-pass",
    ]

    static func blockers(forTargetKey targetKey: String) -> [SafariExtensionPlatformBlocker] {
        if passwordManagerTargets.contains(targetKey) {
            return [.hostApplicationMessageRelay]
        }
        return []
    }
}

/// Local SDK metadata from the macOS 27 beta probe machine (Cycle 7).
enum SafariExtensionHostRelaySDKProbeMetadata {
    /// Canonical SDK name from `MacOSX27.0.sdk/SDKSettings.json`.
    static let probedSDK = "macOS 27.0 SDK (MacOSX27.0.sdk)"
    /// Host OS at probe time (`sw_vers ProductVersion` / `BuildVersion`).
    static let hostOS = "macOS 27.0 beta (26A5353q)"
}

/// Probes local SDK for a future public host-relay API (stub only — no production SPI).
enum SafariExtensionHostRelayAPIProbe {
    /// `true` when a documented public host-relay symbol ships (none on macOS 27.0 SDK).
    static var publicHostRelayAvailable: Bool {
        if #available(macOS 27, *) {
            return probeMacOS27HostRelayAPI()
        }
        return false
    }

    @available(macOS 27, *)
    private static func probeMacOS27HostRelayAPI() -> Bool {
        // macOS 27.0 SDK: WKWebExtension*.h unchanged for browser↔third-party-host relay.
        // Delegate sendMessage/connectUsing still require the embedding browser in the path.
        false
    }

    static let sdkProbeNote: String = """
    Probed WebKit.framework headers in \(SafariExtensionHostRelaySDKProbeMetadata.probedSDK) \
    on \(SafariExtensionHostRelaySDKProbeMetadata.hostOS): \
    WKWebExtensionControllerDelegate.h, WKWebExtensionMessagePort.h, WKWebExtension.h — \
    no API_AVAILABLE(macos(26|27)) host-application relay additions; \
    sendMessage/connectUsing remain macOS 15.4+ with browser-in-the-middle semantics.
    """
}
