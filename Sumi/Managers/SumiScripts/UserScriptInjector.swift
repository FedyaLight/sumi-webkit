//
//  UserScriptInjector.swift
//  Sumi
//
//  Handles the actual injection of userscripts into WKWebView
//  via WKUserScript and WKUserContentController.
//
//  Manages injection timing, content-world isolation,
//  and CSP fallback for @inject-into auto scripts.
//

import Foundation
import WebKit

@MainActor
final class UserScriptInjector {
    nonisolated static let userScriptMarker = "/* SUMI_USER_SCRIPT_RUNTIME */"

    /// Active privileged API brokers per webView.
    @MainActor
    private var activeBrokers: [UUID: SumiUserScriptMessageBroker] = [:]

    weak var tabHandler: SumiScriptsTabHandler?
    weak var browserManager: BrowserManager?

    // MARK: - Public API

    /// Configure a WKUserContentController with userscripts that match the given URL.
    /// This is called during WebView setup (before navigation) for document-start scripts,
    /// and adds all required message handlers.
    ///
    /// - Parameters:
    ///   - controller: The content controller to configure
    ///   - scripts: Pre-filtered and sorted scripts for the current URL
    ///   - webViewId: Unique identifier for the webView (e.g., tab ID)
    func installScripts(
        into controller: WKUserContentController,
        scripts: [UserScript],
        webViewId: UUID,
        profileId: UUID?
    ) {
        // Remove any previously installed SumiScripts content
        cleanupBridges(for: webViewId, from: controller)

        let broker = SumiUserScriptMessageBroker(
            profileId: profileId,
            tabHandler: tabHandler,
            downloadManager: browserManager?.downloadManager
        )
        var didRegisterPrivilegedBridge = false

        for script in scripts {
            switch script.fileType {
            case .javascript:
                installJavaScript(
                    script,
                    into: controller,
                    broker: broker,
                    didRegisterPrivilegedBridge: &didRegisterPrivilegedBridge
                )
            case .css:
                installCSS(script, into: controller)
            }
        }

        if didRegisterPrivilegedBridge {
            activeBrokers[webViewId] = broker
        }
    }

    /// Remove all SumiScripts-related handlers from a controller.
    func cleanupBridges(for webViewId: UUID, from controller: WKUserContentController) {
        activeBrokers.removeValue(forKey: webViewId)?.unregisterAll(from: controller)
        removeInstalledUserScripts(from: controller)
    }

    /// Inject document-idle scripts via evaluateJavaScript (called after page load).
    func injectDocumentIdleScripts(
        into webView: WKWebView,
        scripts: [UserScript]
    ) {
        let idleScripts = scripts.filter { $0.metadata.runAt == .documentIdle }
        guard !idleScripts.isEmpty else { return }

        for script in idleScripts {
            guard script.fileType == .javascript else { continue }

            let bridge = findBridge(for: script)
            let gmShim = bridge?.generateJSShim() ?? ""
            let code = script.assembledCode(gmShim: gmShim)

            webView.evaluateJavaScript(code) { _, error in
                if let error {
                    // Log but don't crash — CSP might block this
                    RuntimeDiagnostics.debug(
                        "Error injecting idle script '\(script.name)': \(error.localizedDescription)",
                        category: "SumiScripts"
                    )
                }
            }
        }
    }

    func executeMenuCommand(script: UserScript, commandId: String, webView: WKWebView?) {
        guard let webView,
              let bridge = findBridge(for: script)
        else { return }
        bridge.resolveMenuCommand(commandId, webView: webView)
    }

    // MARK: - Private: JavaScript Injection

    private func installJavaScript(
        _ script: UserScript,
        into controller: WKUserContentController,
        broker: SumiUserScriptMessageBroker,
        didRegisterPrivilegedBridge: inout Bool
    ) {
        // Determine content world before registering the native message handler:
        // WebKit routes script messages by both name and content world.
        let contentWorld: WKContentWorld
        let injectInto = effectiveInjectionScope(for: script)

        switch injectInto {
        case .content:
            contentWorld = WKContentWorld.world(name: "SumiUserScript_\(script.id.uuidString)")
        case .page, .auto:
            contentWorld = .page
        }

        // Create GM bridge if script uses any GM APIs
        let bridge: UserScriptGMBridge?
        if script.requiresContentWorldIsolation || !script.metadata.grants.isEmpty {
            let b = broker.registerBridge(
                for: script,
                contentWorld: contentWorld,
                in: controller
            )
            didRegisterPrivilegedBridge = true
            bridge = b
        } else {
            bridge = nil
        }

        let gmShim = bridge?.generateJSShim() ?? ""

        // For document-idle, injection is deferred to evaluateJavaScript after load.
        // document-body uses a document-start bootstrap that waits for body.
        guard script.metadata.runAt != .documentIdle else { return }

        let rawCode = Self.userScriptMarker + "\n" + script.assembledCode(gmShim: gmShim)
        let code = script.metadata.runAt == .documentBody
            ? Self.wrapForDocumentBody(rawCode)
            : rawCode

        let wkScript = WKUserScript(
            source: code,
            injectionTime: script.metadata.runAt == .documentBody ? .atDocumentStart : script.injectionTime,
            forMainFrameOnly: script.forMainFrameOnly,
            in: contentWorld
        )

        controller.addUserScript(wkScript)
    }

    private static func wrapForDocumentBody(_ code: String) -> String {
        """
        (() => {
            const __sumiRun = () => {
                try {
                    \(code)
                } catch (error) {
                    console.error('Sumi document-body userscript failed', error);
                }
            };
            if (document.body) {
                __sumiRun();
                return;
            }
            new MutationObserver((_, observer) => {
                if (!document.body) return;
                observer.disconnect();
                __sumiRun();
            }).observe(document.documentElement || document, { childList: true, subtree: true });
        })();
        """
    }

    // MARK: - Private: CSS Injection

    private func installCSS(_ script: UserScript, into controller: WKUserContentController) {
        // Inject CSS via a <style> tag creation script
        let escapedCSS = script.code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let cssInjectionJS = """
        \(Self.userScriptMarker)
        (function() {
            var tag = document.createElement('style');
            tag.textContent = `\(escapedCSS)`;
            tag.setAttribute('data-sumi-userscript', '\(script.filename)');
            (document.head || document.documentElement).appendChild(tag);
        })();
        """

        let wkScript = WKUserScript(
            source: cssInjectionJS,
            injectionTime: script.injectionTime,
            forMainFrameOnly: script.forMainFrameOnly,
            in: .page
        )

        controller.addUserScript(wkScript)
    }

    private func removeInstalledUserScripts(from controller: WKUserContentController) {
        let preserved = controller.userScripts.filter {
            $0.source.contains(Self.userScriptMarker) == false
        }
        guard preserved.count != controller.userScripts.count else { return }
        controller.removeAllUserScripts()
        preserved.forEach { controller.addUserScript($0) }
    }

    // MARK: - Helpers

    private func effectiveInjectionScope(for script: UserScript) -> UserScriptInjectInto {
        var scope = script.metadata.injectInto

        // If script has @grant values and scope is auto, force content scope
        if scope == .auto && script.requiresContentWorldIsolation {
            scope = .content
        }

        // If script has @grant values and scope is page, strip grants (per quoid/userscripts behavior)
        // This is logged but we still use page scope
        if scope == .page && script.requiresContentWorldIsolation {
            // In page scope, GM APIs won't work — log warning
            RuntimeDiagnostics.debug(
                "Warning: '\(script.name)' has @grant values but @inject-into page; GM APIs will not work",
                category: "SumiScripts"
            )
        }

        return scope
    }

    private func findBridge(for script: UserScript) -> UserScriptGMBridge? {
        for broker in activeBrokers.values {
            if let bridge = broker.bridge(for: script) {
                return bridge
            }
        }
        return nil
    }
}
