//
//  SumiNativeScrollbarHideUserScript.swift
//  Sumi
//

import Foundation
import WebKit

/// Hides WebKit's native page scrollbars so the AppKit overlay indicator can own the chrome.
/// Does not inject a custom DOM scrollbar — only suppresses the system scroller.
@MainActor
final class SumiNativeScrollbarHideUserScript: NSObject, SumiPageScript {
    let source: String = SumiNativeScrollbarHideUserScript.makeSource()
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let messageNames: [String] = []

    static func makeSource() -> String {
        """
        (function() {
            if (window.__sumiNativeScrollbarHideInstalled) { return; }
            window.__sumiNativeScrollbarHideInstalled = true;
            var css = [
                'html, body {',
                '  scrollbar-width: none !important;',
                '}',
                'html::-webkit-scrollbar, body::-webkit-scrollbar {',
                '  display: none !important;',
                '  width: 0 !important;',
                '  height: 0 !important;',
                '  background: transparent !important;',
                '}'
            ].join('\\n');
            var style = document.createElement('style');
            style.setAttribute('data-sumi-native-scrollbar-hide', '1');
            style.textContent = css;
            var root = document.documentElement;
            if (root) {
                root.appendChild(style);
            } else {
                document.addEventListener('DOMContentLoaded', function() {
                    if (document.documentElement) {
                        document.documentElement.appendChild(style);
                    }
                }, { once: true });
            }
        })();
        """
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        _ = message
    }
}
