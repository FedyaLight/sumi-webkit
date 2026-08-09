import Foundation
import WebKit

/// Restores the Safari surface that WebKit omits from WKWebView. Some sites
/// use this object together with Safari's user agent to select WebKit-specific
/// behavior.
@MainActor
final class SumiSafariCompatibilityUserScript: NSObject, SumiPageScript {
    static let sourceMarker = "__sumiSafariCompatibilityInstalled"

    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = false
    let requiresRunInPageContentWorld = true
    let messageNames: [String] = []

    let source = """
    (function() {
        if (window.outerHeight === 0 || window.outerWidth === 0) {
            window.outerHeight = window.innerHeight;
            window.outerWidth = window.innerWidth;
        }

        if (window.safari) { return; }
        window.__sumiSafariCompatibilityInstalled = true;

        Object.defineProperty(window, "safari", {
            value: {},
            writable: true,
            configurable: true,
            enumerable: true
        });
        Object.defineProperty(window.safari, "pushNotification", {
            value: {},
            configurable: true,
            enumerable: true
        });

        class SafariRemoteNotificationPermission {
            constructor() {
                this.deviceToken = null;
                this.permission = "denied";
            }
        }

        Object.defineProperty(window.safari.pushNotification, "toString", {
            value: () => "[object SafariRemoteNotification]",
            configurable: true,
            enumerable: true
        });
        Object.defineProperty(window.safari.pushNotification, "permission", {
            value: () => new SafariRemoteNotificationPermission(),
            configurable: true,
            enumerable: true
        });
        Object.defineProperty(window.safari.pushNotification, "requestPermission", {
            value: (_name, _domain, _options, callback) => {
                if (typeof callback === "function") {
                    callback(new SafariRemoteNotificationPermission());
                    return;
                }
                throw new Error(
                    "Invalid 'callback' value passed to safari.pushNotification.requestPermission(). Expected a function."
                );
            },
            configurable: true,
            enumerable: true
        });
    })();
    """

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {}
}
