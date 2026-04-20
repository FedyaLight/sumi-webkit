//
//  WebContextMenuBridge.swift
//  Sumi
//
//  Created by Codex on 09/02/2025.
//

import ObjectiveC.runtime
import WebKit

@MainActor
final class WebContextMenuBridge: NSObject {
    private weak var tab: Tab?
    private weak var userContentController: WKUserContentController?

    init(tab: Tab, configuration: WKWebViewConfiguration) {
        self.tab = tab
        let controller = configuration.userContentController
        self.userContentController = controller
        super.init()

        SharedContextMenuPayloadRouter.installIfNeeded(into: controller)
    }

    func detach() {
        tab?.deliverContextMenuCapture(nil)
        tab = nil
        userContentController = nil
    }
}

@MainActor
private final class SharedContextMenuPayloadRouter: NSObject, WKScriptMessageHandler {
    private static var associationKey: UInt8 = 0
    private static let handlerName = "contextMenuPayload"

    static func installIfNeeded(into controller: WKUserContentController) {
        if objc_getAssociatedObject(controller, &associationKey)
            as? SharedContextMenuPayloadRouter != nil
        {
            return
        }

        let router = SharedContextMenuPayloadRouter()
        controller.add(router, name: handlerName)
        controller.addUserScript(script)
        objc_setAssociatedObject(
            controller,
            &associationKey,
            router,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName else { return }

        let sourceTab = (message.frameInfo.webView as? FocusableWKWebView)?.owningTab
        guard let sourceTab else { return }
        guard let dictionary = message.body as? [String: Any] else {
            sourceTab.deliverContextMenuCapture(nil)
            return
        }

        let capture = WebContextMenuCapture(dictionary: dictionary)
        sourceTab.deliverContextMenuCapture(capture)
    }

    private static let scriptSource: String = """
    (function() {
        if (window.__sumiContextMenuBridgeInstalled) { return; }
        window.__sumiContextMenuBridgeInstalled = true;
        console.log('[Sumi Context Menu] Bridge script installed');

        const INVOCATIONS = {
            page: 1 << 0,
            textSelection: 1 << 1,
            link: 1 << 2,
            image: 1 << 3,
            ignored: 1 << 4
        };

        function sanitizeURL(value) {
            if (!value) { return null; }
            return value;
        }

        function shadowRootFor(node) {
            if (!node) { return null; }
            return node.shadowRoot || node.__sumiClosedShadowRoot || null;
        }

        function isEligibleField(element) {
            if (!element || element.disabled || element.readOnly) { return false; }
            const tagName = (element.tagName || '').toLowerCase();
            if (tagName !== 'input' && tagName !== 'textarea') { return false; }

            const type = (element.getAttribute('type') || '').toLowerCase();
            const autocomplete = (element.getAttribute('autocomplete') || '').toLowerCase();
            const inputMode = (element.getAttribute('inputmode') || '').toLowerCase();
            const identifier = [
                element.name || '',
                element.id || '',
                element.getAttribute('aria-label') || '',
                element.placeholder || ''
            ].join(' ').toLowerCase();

            if (type === 'password') { return true; }
            if (autocomplete.includes('username') || autocomplete.includes('email')) { return true; }
            if (inputMode === 'email') { return true; }

            return identifier.includes('user')
                || identifier.includes('email')
                || identifier.includes('login')
                || identifier.includes('pass');
        }

        function describeField(element) {
            const type = (element && element.getAttribute && element.getAttribute('type') || '').toLowerCase();
            if (type === 'password') { return 'password'; }
            if (type === 'email') { return 'email'; }
            return 'credential';
        }

        function inspectNode(node) {
            const element = node && node.nodeType === Node.ELEMENT_NODE
                ? node
                : node && node.parentElement;
            if (!element) { return null; }

            if (isEligibleField(element)) { return element; }

            if (typeof element.closest === 'function') {
                const closestField = element.closest('input, textarea');
                if (isEligibleField(closestField)) { return closestField; }
            }

            const nestedRoot = shadowRootFor(element);
            if (nestedRoot && nestedRoot.querySelectorAll) {
                const nestedField = nestedRoot.querySelector('input, textarea');
                if (isEligibleField(nestedField)) { return nestedField; }
            }

            return null;
        }

        function resolveEligibleField(event) {
            const path = event && typeof event.composedPath === 'function'
                ? event.composedPath()
                : [];
            for (const candidate of path) {
                const resolved = inspectNode(candidate);
                if (resolved) { return resolved; }
            }
            return inspectNode(event && event.target);
        }

        function capturePayload(event) {
            console.log('[Sumi Context Menu] capturePayload called');
            try {
                var invocations = 0;
                var params = {};

                var selection = window.getSelection();
                if (selection && !selection.isCollapsed) {
                    invocations |= INVOCATIONS.textSelection;
                    params.contents = selection.toString().slice(0, 2000);
                }

                var link = event.target && event.target.closest ? event.target.closest('a[href]') : null;
                if (link && link.href) {
                    invocations |= INVOCATIONS.link;
                    params.href = sanitizeURL(link.href);
                }

                var image = event.target;
                if (!image) {
                    invocations |= INVOCATIONS.page;
                } else {
                    if (!(image.tagName && image.tagName.toUpperCase() === 'IMG')) {
                        image = image.closest ? image.closest('img') : null;
                    }
                    if (image && (image.src || image.currentSrc)) {
                        invocations |= INVOCATIONS.image;
                        params.src = sanitizeURL(image.currentSrc || image.src || image.getAttribute('src'));
                    }
                }

                if (invocations === 0) {
                    invocations |= INVOCATIONS.page;
                    params.href = sanitizeURL(document.location.href);
                }

                const payload = {
                    invocations: invocations,
                    parameters: params,
                    href: sanitizeURL(document.location.href),
                    frameHref: sanitizeURL(location.href),
                    contextHref: sanitizeURL(location.href),
                    inSubframe: window.top !== window,
                    fieldKind: (() => {
                        const field = resolveEligibleField(event);
                        return isEligibleField(field) ? describeField(field) : null;
                    })(),
                    capturedAt: Date.now()
                };

                console.log('[Sumi Context Menu] Payload prepared:', JSON.stringify(payload));
                
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contextMenuPayload) {
                    console.log('[Sumi Context Menu] Posting message to native');
                    window.webkit.messageHandlers.contextMenuPayload.postMessage(payload);
                } else {
                    console.error('[Sumi Context Menu] messageHandler not available!');
                }
            } catch (error) {
                console.error('[Sumi Context Menu] Context menu payload error', error);
            }
        }

        document.addEventListener('contextmenu', capturePayload, true);
        console.log('[Sumi Context Menu] Event listener registered');
    })();
    """

    private static var script: WKUserScript {
        WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}
