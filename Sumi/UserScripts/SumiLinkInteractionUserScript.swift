import Foundation
import WebKit

/// Reports the link currently under the pointer to the exact physical WebView
/// that emitted the script message. The script is intentionally independent of
/// `Tab`, so ephemeral presentation WebViews such as Reader can install it
/// without inheriting the normal-tab script bundle or its runtime authority.
@MainActor
final class SumiLinkInteractionUserScript: NSObject, SumiUserScript {
    private let context: String

    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentEnd
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = false
    let messageNames: [String]

    init(contextID: UUID) {
        self.context = "sumiLinkInteraction_\(contextID.uuidString)"
        self.messageNames = [context]
        self.source = Self.makeSource(context: context)
        super.init()
    }

    private static func makeSource(context: String) -> String {
        """
        (function() {
            if (window.__sumiLinkInteractionInstalled) { return; }
            window.__sumiLinkInteractionInstalled = true;

            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers["\(context)"];
            if (!handler) { return; }

            let currentHoveredLink = null;
            let currentHoveredLinkElement = null;

            function post(method, params) {
                handler.postMessage({
                    context: "\(context)",
                    featureName: "linkInteraction",
                    method: method,
                    params: params || {}
                });
            }

            function findLinkTarget(start) {
                let t = start;
                while (t && t !== document) {
                    if (t.nodeType === 1 && t.localName && t.localName.toLowerCase() === "a" && t.href) {
                        return t;
                    }
                    t = t.parentElement;
                }
                return null;
            }

            function sendHover(method, href) {
                post(method, { href: href || null });
            }

            function updateHoveredLink(link) {
                const href = link && link.href ? link.href : null;
                currentHoveredLinkElement = link || null;
                if (currentHoveredLink === href) {
                    return;
                }

                currentHoveredLink = href;
                sendHover("linkHover", href);
            }

            document.addEventListener("mouseover", function(event) {
                if (currentHoveredLinkElement && currentHoveredLinkElement.contains(event.target)) {
                    return;
                }

                updateHoveredLink(findLinkTarget(event.target));
            }, { passive: true, capture: true });

            document.addEventListener("mouseout", function(event) {
                if (!currentHoveredLink) {
                    return;
                }

                if (currentHoveredLinkElement && event.relatedTarget && currentHoveredLinkElement.contains(event.relatedTarget)) {
                    return;
                }

                const nextTarget = findLinkTarget(event.relatedTarget);
                if (nextTarget && nextTarget.href === currentHoveredLink) {
                    currentHoveredLinkElement = nextTarget;
                    return;
                }

                updateHoveredLink(null);
            }, { passive: true, capture: true });
        })();
        """
    }

    func userContentController(
        _ _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == context,
              let body = message.body as? [String: Any],
              body["context"] as? String == context,
              body["featureName"] as? String == "linkInteraction",
              body["method"] as? String == "linkHover",
              let params = body["params"] as? [String: Any],
              params.keys.contains("href"),
              let webView = message.webView as? FocusableWKWebView
        else { return }

        let value = params["href"]
        if value == nil || value is NSNull {
            webView.hoveredLink.update(nil)
        } else if let href = value as? String {
            webView.hoveredLink.update(href)
        }
    }
}
