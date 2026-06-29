//
//  SafariExtensionInlineUIInfrastructureProbe.swift
//  Sumi
//
//  Runtime probes for inline extension overlay infrastructure.
//  Never inspects page DOM, credentials, or extension message payloads.
//

import AppKit
import Foundation
import WebKit

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
        normalTabRuntimeBindingSource: String? = nil,
        webViewBindingPolicySource: String? = nil,
        navigationResponderSource: String? = nil
    ) -> SafariExtensionInlineUIInfrastructureProbeResult {
        if tabContainerSource != nil
            || profilesSource != nil
            || normalTabRuntimeBindingSource != nil
            || webViewBindingPolicySource != nil
            || navigationResponderSource != nil {
            return evaluateSources(
                tabContainerSource: tabContainerSource,
                profilesSource: profilesSource,
                normalTabRuntimeBindingSource: normalTabRuntimeBindingSource,
                webViewBindingPolicySource: webViewBindingPolicySource,
                navigationResponderSource: navigationResponderSource
            )
        }

        let runtimeResult: SafariExtensionInlineUIInfrastructureProbeResult
        if Thread.isMainThread {
            runtimeResult = MainActor.assumeIsolated {
                evaluateRuntimeInfrastructure()
            }
        } else {
            runtimeResult = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    evaluateRuntimeInfrastructure()
                }
            }
        }

        return runtimeResult
    }

    @MainActor
    private static func evaluateRuntimeInfrastructure() -> SafariExtensionInlineUIInfrastructureProbeResult {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            configuration: WKWebViewConfiguration()
        )
        let container = SumiWebViewContainerView(tab: tab, webView: webView)
        container.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        container.setBrowserContentViewport(
            geometry: BrowserChromeGeometry(outerRadius: 16, elementSeparation: 0)
        )

        let navigationBundle = tab.installNavigationDelegate(on: webView)
        let inlineUINavigationResponderWired =
            webView.navigationDelegate === navigationBundle.distributedNavigationDelegate
                && navigationBundle.hasInlineUIExtensionResourceResponderInChain()

        let lateBindBlocksLoadedPages: Bool
        if #available(macOS 15.5, *) {
            lateBindBlocksLoadedPages =
                ExtensionRuntimeWebViewBindingPolicy.canLateBindController(
                    currentURL: URL(string: "about:blank")
                )
                && ExtensionRuntimeWebViewBindingPolicy.canLateBindController(
                    currentURL: URL(string: "https://example.com")
                ) == false
        } else {
            lateBindBlocksLoadedPages = false
        }

        return result(
            clipsToBoundsOnTabContainer: container.clipsToBounds,
            masksToBoundsOnRoundedViewport: container.layer?.masksToBounds == true,
            lateBindBlocksLoadedPages: lateBindBlocksLoadedPages,
            inlineUINavigationResponderWired: inlineUINavigationResponderWired
        )
    }

    private static func evaluateSources(
        tabContainerSource: String?,
        profilesSource: String?,
        normalTabRuntimeBindingSource: String?,
        webViewBindingPolicySource: String?,
        navigationResponderSource: String?
    ) -> SafariExtensionInlineUIInfrastructureProbeResult {
        let container = tabContainerSource
        let profiles = profilesSource
        let normalTabRuntimeBinding = normalTabRuntimeBindingSource
        let webViewBindingPolicy = webViewBindingPolicySource
        let navigation = navigationResponderSource
        let clipsToBoundsOnTabContainer =
            tabContainerRequiredSymbols.allSatisfy { container?.contains($0) == true }
        let masksToBoundsOnRoundedViewport = clipsToBoundsOnTabContainer
        let lateBindBlocksLoadedPages =
            lateBindRequiredSymbols.allSatisfy { symbol in
                profiles?.contains(symbol) == true
                    || normalTabRuntimeBinding?.contains(symbol) == true
                    || webViewBindingPolicy?.contains(symbol) == true
            }
            && normalTabRuntimeBinding?.contains("func tabNeedsExtensionContentScriptRebind(_ tab: Tab) -> Bool") == true
        let inlineUINavigationResponderWired =
            navigationResponderRequiredSymbols.allSatisfy { navigation?.contains($0) == true }

        return result(
            clipsToBoundsOnTabContainer: clipsToBoundsOnTabContainer,
            masksToBoundsOnRoundedViewport: masksToBoundsOnRoundedViewport,
            lateBindBlocksLoadedPages: lateBindBlocksLoadedPages,
            inlineUINavigationResponderWired: inlineUINavigationResponderWired
        )
    }

    private static func result(
        clipsToBoundsOnTabContainer: Bool,
        masksToBoundsOnRoundedViewport: Bool,
        lateBindBlocksLoadedPages: Bool,
        inlineUINavigationResponderWired: Bool
    ) -> SafariExtensionInlineUIInfrastructureProbeResult {
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
}
