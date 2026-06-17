import Foundation
import WebKit

@MainActor
final class SumiBoostZapSession: NSObject, WKScriptMessageHandler {
    private let messageName = "sumiBoostZap_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    private let boost: SumiBoost
    private weak var webView: WKWebView?
    private let isEphemeral: Bool
    private weak var module: SumiBoostsModule?
    private let onSelector: @MainActor (SumiBoost) -> Void
    private let onFinish: @MainActor () -> Void
    private var isRunning = false
    private var didNotifyFinish = false

    init(
        boost: SumiBoost,
        webView: WKWebView,
        isEphemeral: Bool,
        module: SumiBoostsModule,
        onSelector: @escaping @MainActor (SumiBoost) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) {
        self.boost = boost
        self.webView = webView
        self.isEphemeral = isEphemeral
        self.module = module
        self.onSelector = onSelector
        self.onFinish = onFinish
        super.init()
    }

    func start() {
        guard !isRunning, let webView else { return }
        isRunning = true
        webView.configuration.userContentController.add(
            self,
            contentWorld: .page,
            name: messageName
        )
        webView.evaluateJavaScript(Self.overlayJavaScript(messageName: messageName), completionHandler: nil)
    }

    func stop() {
        guard isRunning, let webView else { return }
        isRunning = false
        webView.evaluateJavaScript(Self.stopJavaScript(), completionHandler: nil)
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: messageName,
            contentWorld: .page
        )
        notifyFinish()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        guard let body = message.body as? [String: Any] else {
            return
        }

        if body["cancelled"] as? Bool == true {
            stop()
            return
        }

        guard let selector = body["selector"] as? String,
              !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        guard let updated = module?.updateBoost(
            boost,
            isEphemeral: isEphemeral,
            markChanged: true,
            mutate: { data in
                if !data.zapSelectors.contains(selector) {
                    data.zapSelectors.append(selector)
                }
            }
        ) else {
            stop()
            return
        }
        onSelector(updated)
        stop()
    }

    private func notifyFinish() {
        guard !didNotifyFinish else { return }
        didNotifyFinish = true
        onFinish()
    }

    static func previewJavaScript(selector: String, isHighlighted: Bool) -> String {
        let payload = encodedJSONObject(["selector": selector])
        return """
        (function() {
            const payload = \(payload);
            const selector = payload.selector;
            try {
                document.querySelectorAll(selector).forEach(function(element) {
                    if (\(isHighlighted ? "true" : "false")) {
                        element.setAttribute('zen-zap-unhide', '');
                        element.setAttribute('data-sumi-boost-zap-preview', '');
                        element.style.setProperty('outline', '2px solid Highlight', 'important');
                        element.style.setProperty('outline-offset', '2px', 'important');
                    } else {
                        element.removeAttribute('zen-zap-unhide');
                        if (element.hasAttribute('data-sumi-boost-zap-preview')) {
                            element.removeAttribute('data-sumi-boost-zap-preview');
                            element.style.removeProperty('outline');
                            element.style.removeProperty('outline-offset');
                        }
                    }
                });
            } catch (_) {}
        })();
        """
    }

    private static func overlayJavaScript(messageName: String) -> String {
        """
        (function() {
            if (window.__sumiBoostZap && window.__sumiBoostZap.cleanup) {
                window.__sumiBoostZap.cleanup();
            }

            const style = document.createElement('style');
            style.setAttribute('data-sumi-boost-zap-overlay', '');
            style.textContent = [
                '*[data-sumi-boost-zap-hover] { outline: 2px solid Highlight !important; outline-offset: 2px !important; cursor: crosshair !important; }',
                'html[data-sumi-boost-zap-active], html[data-sumi-boost-zap-active] * { cursor: crosshair !important; }'
            ].join('\\n');
            (document.head || document.documentElement).appendChild(style);
            document.documentElement.setAttribute('data-sumi-boost-zap-active', '');

            let hovered = null;
            function cssEscape(value) {
                if (window.CSS && typeof window.CSS.escape === 'function') {
                    return window.CSS.escape(value);
                }
                return String(value).replace(/[^a-zA-Z0-9_-]/g, '\\\\$&');
            }
            function partFor(element) {
                if (!element || !element.localName) return null;
                if (element.id) return '#' + cssEscape(element.id);
                let part = element.localName.toLowerCase();
                const className = typeof element.className === 'string'
                    ? element.className.trim().split(/\\s+/).filter(Boolean)[0]
                    : '';
                if (className) part += '.' + cssEscape(className);
                const parent = element.parentElement;
                if (!parent) return part;
                const siblings = Array.prototype.filter.call(parent.children, function(child) {
                    return child.localName === element.localName;
                });
                if (siblings.length > 1) {
                    part += ':nth-of-type(' + (siblings.indexOf(element) + 1) + ')';
                }
                return part;
            }
            function selectorFor(element) {
                const parts = [];
                let current = element;
                while (current && current.nodeType === 1 && current !== document.documentElement) {
                    const part = partFor(current);
                    if (!part) break;
                    parts.unshift(part);
                    if (part[0] === '#') break;
                    current = current.parentElement;
                }
                return parts.join(' > ');
            }
            function setHovered(element) {
                if (hovered === element) return;
                if (hovered) hovered.removeAttribute('data-sumi-boost-zap-hover');
                hovered = element;
                if (hovered) hovered.setAttribute('data-sumi-boost-zap-hover', '');
            }
            function onMouseOver(event) {
                setHovered(event.target);
                event.preventDefault();
                event.stopPropagation();
            }
            function onMouseOut(event) {
                if (event.target === hovered) setHovered(null);
                event.preventDefault();
                event.stopPropagation();
            }
            function onClick(event) {
                event.preventDefault();
                event.stopPropagation();
                const selector = selectorFor(event.target);
                if (selector) {
                    window.webkit.messageHandlers.\(messageName).postMessage({ selector: selector });
                }
                cleanup();
            }
            function onKeyDown(event) {
                if (event.key === 'Escape') {
                    event.preventDefault();
                    event.stopPropagation();
                    window.webkit.messageHandlers.\(messageName).postMessage({ cancelled: true });
                    cleanup();
                }
            }
            function cleanup() {
                document.removeEventListener('mouseover', onMouseOver, true);
                document.removeEventListener('mouseout', onMouseOut, true);
                document.removeEventListener('click', onClick, true);
                document.removeEventListener('keydown', onKeyDown, true);
                if (hovered) hovered.removeAttribute('data-sumi-boost-zap-hover');
                hovered = null;
                style.remove();
                document.documentElement.removeAttribute('data-sumi-boost-zap-active');
                if (window.__sumiBoostZap && window.__sumiBoostZap.cleanup === cleanup) {
                    window.__sumiBoostZap = null;
                }
            }

            document.addEventListener('mouseover', onMouseOver, true);
            document.addEventListener('mouseout', onMouseOut, true);
            document.addEventListener('click', onClick, true);
            document.addEventListener('keydown', onKeyDown, true);
            window.__sumiBoostZap = { cleanup: cleanup };
        })();
        """
    }

    private static func stopJavaScript() -> String {
        """
        (function() {
            if (window.__sumiBoostZap && window.__sumiBoostZap.cleanup) {
                window.__sumiBoostZap.cleanup();
            }
        })();
        """
    }

    private static func encodedJSONObject(_ object: [String: String]) -> String {
        (try? JSONEncoder().encode(object))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"selector":""}"#
    }
}
