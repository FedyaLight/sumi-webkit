//
//  UserScriptCSPHandler.swift
//  Sumi
//
//  Handles Content Security Policy (CSP) violations for userscripts.
//  When a script with @inject-into auto is blocked by CSP,
//  this handler retries injection in the content script world.
//

import Foundation
import WebKit

enum UserScriptCSPHandler {

    /// Generate a CSP violation listener that triggers re-injection
    /// for @inject-into auto scripts.
    ///
    /// This script listens for `securitypolicyviolation` events on the document.
    /// When a script-src or script-src-elem violation is detected, it notifies
    /// the native side to re-inject blocked scripts in content world.
    static func cspFallbackListenerScript(handlerName: String) -> String {
        return """
        \(UserScriptInjector.userScriptMarker)
        (function() {
            if (window.__sumiCSPFallbackInstalled) return;
            window.__sumiCSPFallbackInstalled = true;

            document.addEventListener('securitypolicyviolation', function(e) {
                if (e.effectiveDirective === 'script-src' || e.effectiveDirective === 'script-src-elem') {
                    try {
                        window.webkit.messageHandlers['\(handlerName)'].postMessage({
                            type: 'csp_violation',
                            blockedURI: e.blockedURI,
                            effectiveDirective: e.effectiveDirective,
                            originalPolicy: e.originalPolicy
                        });
                    } catch(err) {
                        // Handler might not exist, ignore
                    }
                }
            }, { once: true });
        })();
        """
    }

    /// Create a WKUserScript for CSP monitoring that injects at document-start.
    static func createCSPMonitorScript(handlerName: String) -> WKUserScript {
        let source = cspFallbackListenerScript(handlerName: handlerName)
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
    }
}
