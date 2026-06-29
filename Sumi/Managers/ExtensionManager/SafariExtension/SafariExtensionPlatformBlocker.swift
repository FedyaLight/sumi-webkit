//
//  SafariExtensionPlatformBlocker.swift
//  Sumi
//
//  Hard platform blockers for Safari Web Extension compatibility.
//  Native messaging relay absence is NOT a platform blocker — see
//  SafariExtensionNativeMessagingClassification.
//

import Foundation

/// Platform capabilities that block full parity on public APIs with cited evidence.
enum SafariExtensionPlatformBlocker: String, Codable, CaseIterable, Sendable {
    /// No hard platform blockers are currently recorded (Cycle 8).
    case none
}

/// Local SDK metadata from the macOS 27 beta probe machine (Cycle 7–8).
enum SafariExtensionHostRelaySDKProbeMetadata {
    /// Canonical SDK name from `MacOSX27.0.sdk/SDKSettings.json`.
    static let probedSDK = "macOS 27.0 SDK (MacOSX27.0.sdk)"
    /// Host OS at probe time (`sw_vers ProductVersion` / `BuildVersion`).
    static let hostOS = "macOS 27.0 beta (26A5353q)"

    static let sdkProbeNote: String = """
    Probed WebKit.framework headers in \(probedSDK) \
    on \(hostOS): \
    WKWebExtensionControllerDelegate.h, WKWebExtensionMessagePort.h, WKWebExtension.h — \
    sendMessage:toApplicationWithIdentifier:for:replyHandler: and \
    connectUsingMessagePort:for:completionHandler: available macOS 15.4+; \
    Swift delegate signatures verified: \
    webExtensionController(_:sendMessage:toApplicationWithIdentifier:for:replyHandler:), \
    webExtensionController(_:connectUsing:for:completionHandler:); \
    no API_AVAILABLE(macos(26|27)) third-party-host IPC additions in WKWebExtension*.h; \
    Chrome-style native host manifests are not used on Safari. \
    WebKit logs \"Runtime error reported:\" for each delegate reply error returned to \
    runtime.sendNativeMessage()/connectNative(); Sumi cannot suppress that console output.
    """
}

/// Probes local SDK for WKWebExtension native messaging delegate availability.
enum SafariExtensionHostRelayAPIProbe {
    /// `true` when WKWebExtension delegate native messaging is compiled in for this target.
    static var wkWebExtensionAppMessagingAvailable: Bool {
        if #available(macOS 15.4, *) {
            return true
        }
        return false
    }

    /// Legacy probe name retained for compatibility with existing SDK probe reports.
    static var publicHostRelayAvailable: Bool {
        false
    }

    static let sdkProbeNote = SafariExtensionHostRelaySDKProbeMetadata.sdkProbeNote
}
