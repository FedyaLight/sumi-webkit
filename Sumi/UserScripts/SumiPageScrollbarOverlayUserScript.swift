import Foundation
import WebKit

/// Hides only the root WebKit scroller and reports root scroll geometry to the
/// AppKit overlay owned by the page host. WebKit remains the scroll authority.
@MainActor
final class SumiPageScrollbarOverlayUserScript: NSObject, SumiPageScript {
    private static let messageName = "sumiPageScrollbarOverlay"

    let source: String = SumiPageScrollbarOverlayUserScript.makeSource()
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let messageNames = [SumiPageScrollbarOverlayUserScript.messageName]

    static func makeSource() -> String {
        """
        (() => {
            if (window.__sumiPageScrollbarOverlayInstalled) { return; }
            window.__sumiPageScrollbarOverlayInstalled = true;

            const handler = window.webkit?.messageHandlers?.["\(messageName)"];
            if (!handler) { return; }

            const style = document.createElement("style");
            style.setAttribute("data-sumi-page-scrollbar-overlay", "1");
            style.textContent = `
                html, body {
                    scrollbar-width: none !important;
                }
                html::-webkit-scrollbar,
                body::-webkit-scrollbar {
                    display: none !important;
                    width: 0 !important;
                    height: 0 !important;
                    background: transparent !important;
                }
            `;

            function installStyle() {
                const root = document.head || document.documentElement;
                if (root && !style.isConnected) { root.appendChild(style); }
            }

            let animationFrame = 0;
            let shouldReveal = false;
            let lastSignature = "";

            function publishMetrics() {
                animationFrame = 0;
                const scrollingElement = document.scrollingElement || document.documentElement;
                const root = document.documentElement;
                const body = document.body;
                if (!scrollingElement || !root) { return; }

                const viewportHeight = window.visualViewport?.height
                    || window.innerHeight
                    || root.clientHeight;
                const contentHeight = Math.max(
                    scrollingElement.scrollHeight,
                    root.scrollHeight,
                    body ? body.scrollHeight : 0
                );
                const contentOffset = Math.max(scrollingElement.scrollTop, window.scrollY || 0);
                const reveal = shouldReveal;
                shouldReveal = false;
                const signature = `${viewportHeight}:${contentHeight}:${contentOffset}`;
                if (!reveal && signature === lastSignature) { return; }
                lastSignature = signature;

                handler.postMessage({
                    context: "\(messageName)",
                    viewportHeight,
                    contentHeight,
                    contentOffset,
                    reveal
                });
            }

            function scheduleMetrics(reveal) {
                shouldReveal = shouldReveal || reveal;
                if (animationFrame) { return; }
                animationFrame = requestAnimationFrame(publishMetrics);
            }

            function beginObservingGeometry() {
                installStyle();
                scheduleMetrics(false);
                if (typeof ResizeObserver === "function") {
                    const resizeObserver = new ResizeObserver(() => scheduleMetrics(false));
                    resizeObserver.observe(document.documentElement);
                    if (document.body) { resizeObserver.observe(document.body); }
                }
            }

            installStyle();
            window.addEventListener("scroll", () => scheduleMetrics(true), { passive: true });
            window.addEventListener("resize", () => scheduleMetrics(false), { passive: true });
            if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", beginObservingGeometry, { once: true });
            } else {
                beginObservingGeometry();
            }
            window.addEventListener("load", () => scheduleMetrics(false), { once: true });
            scheduleMetrics(false);
        })();
        """
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        guard message.name == Self.messageName,
              message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              body["context"] as? String == Self.messageName,
              let viewportHeight = Self.cgFloat(body["viewportHeight"]),
              let contentHeight = Self.cgFloat(body["contentHeight"]),
              let contentOffset = Self.cgFloat(body["contentOffset"]),
              let webView = message.webView as? FocusableWKWebView
        else { return }

        webView.pageScrollbarOverlay?.update(
            WebContentOverlayScrollMetrics(
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                contentOffset: contentOffset
            ),
            reveal: body["reveal"] as? Bool == true
        )
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        guard let number = value as? NSNumber else { return nil }
        return CGFloat(truncating: number)
    }
}
