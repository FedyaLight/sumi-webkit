//
//  ChromeMV3WebViewConfigurationAttachmentGuard.swift
//  Sumi
//
//  Read-only diagnostics for proving current WebView configurations remain
//  unattached to the Chrome MV3 empty controller.
//

import Foundation
import WebKit

struct ChromeMV3WebViewConfigurationAttachmentDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var siteID: String
    var surface: ChromeMV3WebViewSurface
    var isNormalTabConfiguration: Bool
    var hasControllerAttachment: Bool
    var userScriptCount: Int
    var attachmentAllowedNow: Bool
    var verdict: String
    var notes: [String]
}

enum ChromeMV3WebViewConfigurationAttachmentGuard {
    @MainActor
    static func inspect(
        configuration: WKWebViewConfiguration,
        siteID: String,
        surface: ChromeMV3WebViewSurface
    ) -> ChromeMV3WebViewConfigurationAttachmentDiagnostic {
        let hasControllerAttachment =
            configuration.webExtensionController != nil
        return ChromeMV3WebViewConfigurationAttachmentDiagnostic(
            siteID: siteID,
            surface: surface,
            isNormalTabConfiguration:
                configuration.sumiIsNormalTabWebViewConfiguration,
            hasControllerAttachment: hasControllerAttachment,
            userScriptCount:
                configuration.userContentController.userScripts.count,
            attachmentAllowedNow: false,
            verdict: hasControllerAttachment
                ? "Unexpected Chrome MV3 controller attachment detected."
                : "No Chrome MV3 controller attachment detected.",
            notes: notes(
                surface: surface,
                isNormalTabConfiguration:
                    configuration.sumiIsNormalTabWebViewConfiguration,
                hasControllerAttachment: hasControllerAttachment
            )
        )
    }

    private static func notes(
        surface: ChromeMV3WebViewSurface,
        isNormalTabConfiguration: Bool,
        hasControllerAttachment: Bool
    ) -> [String] {
        var notes: [String] = [
            "This diagnostic is read-only and does not mutate WebView configuration.",
            "Attachment remains blocked for all current Sumi WebView surfaces.",
        ]

        if isNormalTabConfiguration {
            notes.append("Normal-tab configuration is only future-eligible through attachment preflight.")
        }

        switch surface {
        case .syntheticTestConfiguration:
            notes.append("Synthetic configurations must use the dedicated test-only attachment harness.")
        case .normalTab, .pinnedEssentialsLiveNormalBrowsing:
            notes.append("Normal browsing surfaces remain unattached in this prompt.")
        case .extensionOwnedPopup, .extensionOwnedOptionsPage:
            notes.append("Extension-owned UI is future-only and is not wired to the empty controller.")
        default:
            notes.append("Helper, preview, mini, and metadata surfaces are not eligible for current attachment.")
        }

        if hasControllerAttachment {
            notes.append("A non-nil controller would violate the Chrome MV3 preflight-only boundary.")
        }

        return Array(Set(notes)).sorted()
    }
}
