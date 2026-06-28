//
//  SafariExtensionInlineUIInfrastructureProbe.swift
//  Sumi
//
//  Static structural probes for inline extension overlay infrastructure.
//  Never inspects page DOM, credentials, or extension message payloads.
//

import Foundation

struct SafariExtensionInlineUIInfrastructureProbeResult: Equatable, Sendable {
    let clipsToBoundsOnTabContainer: Bool
    /// AppKit `clipsToBounds` on `SumiWebViewContainerView` only clips NSView subviews.
    /// Extension inline overlays (fixed-position DOM, shadow roots, in-page iframes) render
    /// inside WKWebView's compositor and are not affected by the container's AppKit clipping.
    let clipsToBoundsAffectsInPageExtensionOverlays: Bool
    let masksToBoundsOnRoundedViewport: Bool
    let lateBindBlocksLoadedPages: Bool
    let inlineUINavigationResponderWired: Bool
    let detail: String
}

enum SafariExtensionInlineUIInfrastructureProbe {
    static let tabContainerRequiredSymbols: [String] = [
        "final class SumiWebViewContainerView",
        "clipsToBounds = true",
        "layer?.masksToBounds = radius > 0",
    ]

    static let lateBindRequiredSymbols: [String] = [
        "func canLateBindExtensionController(to webView: WKWebView) -> Bool",
        "enum ExtensionRuntimeWebViewBindingPolicy",
        "normalizedURL.isEmpty || normalizedURL == \"about:blank\"",
        "func tabNeedsExtensionContentScriptRebind(_ tab: Tab) -> Bool",
    ]

    static let navigationResponderRequiredSymbols: [String] = [
        "final class SafariExtensionInlineUINavigationResponder",
        "recordExtensionResourceNavigation",
    ]

    static func evaluate(
        tabContainerSource: String? = nil,
        profilesSource: String? = nil,
        navigationResponderSource: String? = nil
    ) -> SafariExtensionInlineUIInfrastructureProbeResult {
        let container = tabContainerSource ?? loadSource(
            relativeToExtensionManager: "WebViewCoordinator/SumiWebViewContainerView.swift"
        )
        let profiles = profilesSource ?? loadSource(
            relativeToExtensionManager: "ExtensionManager+Profiles.swift"
        )
        let webViewBindingPolicy = loadSource(
            relativeToExtensionManager: "ExtensionRuntimeWebViewBindingPolicy.swift"
        )
        let navigation = navigationResponderSource ?? loadSource(
            relativeToTabNavigation: "SafariExtensionInlineUINavigationResponder.swift"
        )

        let clipsToBoundsOnTabContainer =
            container?.contains("clipsToBounds = true") == true
        let masksToBoundsOnRoundedViewport =
            container?.contains("layer?.masksToBounds = radius > 0") == true
        let lateBindBlocksLoadedPages =
            profiles?.contains("func canLateBindExtensionController(to webView: WKWebView) -> Bool") == true
            && webViewBindingPolicy?.contains("enum ExtensionRuntimeWebViewBindingPolicy") == true
            && webViewBindingPolicy?.contains("normalizedURL.isEmpty || normalizedURL == \"about:blank\"") == true
        let inlineUINavigationResponderWired =
            navigationResponderRequiredSymbols.allSatisfy { navigation?.contains($0) == true }

        var detailParts: [String] = []
        if clipsToBoundsOnTabContainer {
            detailParts.append("tabContainerClipsToBoundsChromeOnly")
        }
        if masksToBoundsOnRoundedViewport {
            detailParts.append("roundedViewportMasksToBounds")
        }
        if lateBindBlocksLoadedPages {
            detailParts.append("lateBindBlankOnly")
        }
        if inlineUINavigationResponderWired == false {
            detailParts.append("inlineUINavigationResponderMissing")
        }

        return SafariExtensionInlineUIInfrastructureProbeResult(
            clipsToBoundsOnTabContainer: clipsToBoundsOnTabContainer,
            clipsToBoundsAffectsInPageExtensionOverlays: false,
            masksToBoundsOnRoundedViewport: masksToBoundsOnRoundedViewport,
            lateBindBlocksLoadedPages: lateBindBlocksLoadedPages,
            inlineUINavigationResponderWired: inlineUINavigationResponderWired,
            detail: detailParts.isEmpty ? "inlineUIInfrastructureProbePassed" : detailParts.joined(separator: ",")
        )
    }

    private static func managersRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func loadSource(relativeToExtensionManager path: String) -> String? {
        let url = managersRootURL().appendingPathComponent(path)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func loadSource(relativeToTabNavigation path: String) -> String? {
        let url = managersRootURL()
            .deletingLastPathComponent()
            .appendingPathComponent("Models/Tab/Navigation")
            .appendingPathComponent(path)
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
