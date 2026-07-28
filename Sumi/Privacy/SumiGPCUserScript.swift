import Foundation
import WebKit

/// Injects the Global Privacy Control (GPC) DOM signal into every frame of every
/// page, per the GPC spec (https://www.w3.org/TR/gpc/). Sites read
/// `navigator.globalPrivacyControl` to learn the user does not consent to having
/// their data sold or shared.
///
/// Defines the property on `Navigator.prototype` (not the `navigator` instance)
/// so it survives frame proxies and is visible to `typeof` checks the same way
/// browsers that ship GPC natively expose it.
@MainActor
final class SumiGPCUserScript: NSObject, SumiPageScript {
    let source: String = SumiGPCUserScript.makeSource()
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = false
    let requiresRunInPageContentWorld = true
    let messageNames: [String] = []

    static func makeSource() -> String {
        """
        (function() {
            try {
                if (navigator.globalPrivacyControl === true) { return; }
                Object.defineProperty(Navigator.prototype, "globalPrivacyControl", {
                    get: function() { return true; },
                    configurable: true,
                    enumerable: true
                });
            } catch (e) {
                try {
                    Object.defineProperty(navigator, "globalPrivacyControl", {
                        get: function() { return true; },
                        configurable: true,
                        enumerable: true
                    });
                } catch (e2) { /* Best-effort fallback only. */ }
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
