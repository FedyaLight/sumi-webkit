//
//  ExtensionManager+ExternallyConnectableLifecycle.swift
//  Sumi
//
//  Bridge installation, lifecycle, and policy helpers for externally_connectable.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
extension ExtensionManager {
    func pageBridgeMarker(for extensionId: String) -> String {
        "/* \(Self.externallyConnectablePageBridgeMarker)\(extensionId) */"
    }

    func removeExternallyConnectablePageBridge(for extensionId: String) {
        let bridgeMarker = pageBridgeMarker(for: extensionId)
        let userContentController = browserConfiguration
            .webViewConfiguration
            .userContentController

        let preservedScripts = userContentController.userScripts.filter { script in
            guard Self.isManagedExternallyConnectablePageBridgeScript(script) else {
                return true
            }
            return script.source.contains(bridgeMarker) == false
        }

        guard preservedScripts.count != userContentController.userScripts.count else {
            installedPageBridgeIDs.remove(extensionId)
            removeExternallyConnectablePolicy(for: extensionId)
            return
        }

        userContentController.removeAllUserScripts()
        preservedScripts.forEach { userContentController.addUserScript($0) }
        installedPageBridgeIDs.remove(extensionId)
        removeExternallyConnectablePolicy(for: extensionId)
    }

    func setupExternallyConnectableBridge(
        extensionId: String,
        packagePath: String
    ) {
        let manifestURL = URL(fileURLWithPath: packagePath)
            .appendingPathComponent("manifest.json")
        guard let manifest = try? ExtensionUtils.loadJSONObject(at: manifestURL),
              let policy = Self.externallyConnectablePolicy(
                  from: manifest,
                  extensionId: extensionId
              )
        else {
            removeExternallyConnectablePageBridge(for: extensionId)
            return
        }

        externallyConnectablePolicies[extensionId] = policy

        Self.logger.info(
            "Installing page-world externally_connectable shim for extension \(extensionId, privacy: .public): \(policy.matchPatternStrings.joined(separator: ", "), privacy: .public)"
        )

        let runtimeConfiguration = browserConfiguration.webViewConfiguration
        let runtimeUserContentController = runtimeConfiguration.userContentController
        installExternallyConnectableNativeBridgeIfNeeded(into: runtimeUserContentController)
        removeExternallyConnectablePageBridge(for: extensionId)
        externallyConnectablePolicies[extensionId] = policy

        let pageScriptSource = Self.pageWorldExternallyConnectableBridgeScript(
            configJSON: Self.pageWorldExternallyConnectableBridgeConfigJSON(
                policy: policy,
                bridgeMarker: pageBridgeMarker(for: extensionId)
            ),
            bridgeMarker: pageBridgeMarker(for: extensionId)
        )

        let pageScript = SumiCreatePrivateUserScript(
            pageScriptSource,
            .atDocumentStart,
            false,
            policy.matchPatternStrings,
            nil,
            nil,
            WKContentWorld.page
        )
        runtimeUserContentController.addUserScript(pageScript)
        installedPageBridgeIDs.insert(extensionId)
    }

    func installExternallyConnectableNativeBridgeIfNeeded(
        into controller: WKUserContentController
    ) {
        guard externallyConnectablePolicies.isEmpty == false else { return }

        SumiExtensionMessageBroker.installIfNeeded(
            ecBroker,
            into: controller
        )
    }

    func updateExternallyConnectableNavigationLifecycle(
        for webView: WKWebView,
        currentURL: URL?
    ) {
        guard externallyConnectablePolicies.isEmpty == false else {
            releaseExternallyConnectableRuntime(
                for: webView,
                reason: "no externally_connectable policies are active"
            )
            return
        }

        let previousURLString = ecRegistry.trackedPageURL(for: webView)
        let currentURLString = currentURL?.absoluteString

        if previousURLString != currentURLString {
            cancelExternallyConnectablePendingRequests(
                for: webView,
                reason: "Extension request canceled due to navigation"
            )
            closeExternallyConnectableNativePorts(
                for: webView,
                reason: "Extension port disconnected due to navigation",
                notifyPage: true
            )
        }

        ecRegistry.setTrackedPageURL(currentURLString, for: webView)
    }

    func releaseExternallyConnectableRuntime(
        for webView: WKWebView,
        reason: String
    ) {
        guard ecRegistry.hasTrackedState(for: webView) else { return }

        cancelExternallyConnectablePendingRequests(
            for: webView,
            reason: "Extension request canceled because \(reason)"
        )
        closeExternallyConnectableNativePorts(
            for: webView,
            reason: "Extension port disconnected because \(reason)",
            notifyPage: true
        )
        ecRegistry.removeTrackedPageURL(for: webView)
    }

    func removeExternallyConnectablePolicy(for extensionId: String) {
        externallyConnectablePolicies.removeValue(forKey: extensionId)
        cancelExternallyConnectablePendingRequests(
            for: extensionId,
            reason: "Extension request canceled because the extension runtime was torn down"
        )
        closeExternallyConnectableNativePorts(
            for: extensionId,
            reason: "Extension port disconnected because the extension runtime was torn down",
            notifyPage: true
        )

        if externallyConnectablePolicies.isEmpty {
            ecRegistry.clearAllTrackedPageURLs()
            SumiExtensionMessageBroker.removeIfInstalled(
                from: browserConfiguration.webViewConfiguration.userContentController,
                context: Self.externallyConnectableNativeBridgeHandlerName
            )
        }
    }

    func normalizeExternallyConnectableExtensionID(_ rawValue: Any?) -> String? {
        guard let string = rawValue as? String else { return nil }
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func logExternallyConnectableBridgeEvent(
        _ message: @autoclosure () -> String
    ) {
        guard Self.isExternallyConnectableBridgeDebugLoggingEnabled else { return }
        let renderedMessage = message()
        Self.logger.debug("\(renderedMessage, privacy: .public)")
    }

    static func originString(for url: URL?) -> String? {
        guard let url, let scheme = url.scheme, let host = url.host else {
            return nil
        }

        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }

        return "\(scheme)://\(host)"
    }

    @MainActor
    static func externallyConnectablePolicy(
        from manifest: [String: Any],
        extensionId: String
    ) -> ExternallyConnectablePolicy? {
        guard let externallyConnectable = manifest["externally_connectable"] as? [String: Any],
              let matchPatternStrings = externallyConnectable["matches"] as? [String],
              matchPatternStrings.isEmpty == false
        else {
            return nil
        }

        let validPatterns: [WKWebExtension.MatchPattern] =
            matchPatternStrings.compactMap { patternString -> WKWebExtension.MatchPattern? in
                guard patternString != "<all_urls>" else { return nil }
                return try? WKWebExtension.MatchPattern(string: patternString)
            }

        guard validPatterns.isEmpty == false else {
            return nil
        }

        return ExternallyConnectablePolicy(
            extensionId: extensionId,
            matchPatternStrings: matchPatternStrings,
            matchPatterns: validPatterns
        )
    }

    @MainActor
    static func externallyConnectableHostnames(
        from manifest: [String: Any]
    ) -> [String] {
        guard let policy = externallyConnectablePolicy(
            from: manifest,
            extensionId: "policy"
        ) else {
            return []
        }

        return policy.normalizedHostnames
    }

    @MainActor
    static func pageWorldExternallyConnectableBridgeConfigJSON(
        policy: ExternallyConnectablePolicy,
        bridgeMarker: String
    ) -> String {
        let config: [String: Any] = [
            "allowedHosts": policy.normalizedHostnames,
            "bridgeMarkerKey": bridgeMarker,
            "bridgeVersion": 1,
            "configuredRuntimeId": policy.extensionId,
            "debugLoggingEnabled": isExternallyConnectableBridgeDebugLoggingEnabled,
            "nativeBridgeHandlerName": externallyConnectableNativeBridgeHandlerName,
            "supportsConnect": true,
            "transportMode": "nativeHybrid",
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: config,
            options: [.sortedKeys]
        ), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return json
    }
}
