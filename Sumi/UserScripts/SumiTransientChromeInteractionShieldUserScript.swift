import Foundation
import WebKit

struct SumiTransientChromeInteractionShieldRect {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
}

@MainActor
final class SumiTransientChromeInteractionShieldUserScript: NSObject, SumiUserScript {
    static let apiName = "__sumiTransientChromeInteractionShield"
    static let sourceMarker = "__sumiTransientChromeInteractionShieldInstalled"

    let source: String = SumiTransientChromeInteractionShieldUserScript.makeSource()
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String] = []

    static func makeSetActiveSource(
        _ isActive: Bool,
        clientPoint: CGPoint?,
        rects: [SumiTransientChromeInteractionShieldRect]
    ) -> String {
        let pointSource: String
        if let clientPoint {
            pointSource = "{ clientX: \(clientPoint.x), clientY: \(clientPoint.y) }"
        } else {
            pointSource = "null"
        }

        let rectsSource = "[" + rects.map {
            "{ left: \($0.x), top: \($0.y), width: \($0.width), height: \($0.height) }"
        }.joined(separator: ",") + "]"

        return """
        (function() {
            const shield = window.\(apiName);
            if (shield && typeof shield.setActive === "function") {
                shield.setActive(\(isActive ? "true" : "false"), \(pointSource), \(rectsSource));
            }
        })();
        """
    }

    private static func makeSource() -> String {
        """
        (function() {
            if (window.\(Self.sourceMarker)) { return; }
            window.\(Self.sourceMarker) = true;

            const shieldIdPrefix = "__sumi_transient_chrome_interaction_shield_";
            const blockedEventTypes = [
                "auxclick",
                "click",
                "contextmenu",
                "dblclick",
                "dragstart",
                "mousedown",
                "mouseenter",
                "mouseleave",
                "mousemove",
                "mouseout",
                "mouseover",
                "mouseup",
                "pointercancel",
                "pointerdown",
                "pointerenter",
                "pointerleave",
                "pointermove",
                "pointerout",
                "pointerover",
                "pointerup",
                "wheel"
            ];

            let active = false;
            let shieldElements = [];
            let activeRects = [];
            const listenerOptions = { capture: true, passive: false };

            function clampPoint(point) {
                if (!point) { return null; }

                const clientX = Number(point.clientX);
                const clientY = Number(point.clientY);
                if (!Number.isFinite(clientX) || !Number.isFinite(clientY)) {
                    return null;
                }

                return {
                    clientX: Math.min(Math.max(clientX, 0), Math.max(document.documentElement.clientWidth, window.innerWidth || 0)),
                    clientY: Math.min(Math.max(clientY, 0), Math.max(document.documentElement.clientHeight, window.innerHeight || 0))
                };
            }

            function normalizeRect(rect) {
                if (!rect) { return null; }

                const left = Number(rect.left);
                const top = Number(rect.top);
                const width = Number(rect.width);
                const height = Number(rect.height);
                if (!Number.isFinite(left) || !Number.isFinite(top) || !Number.isFinite(width) || !Number.isFinite(height)) {
                    return null;
                }
                if (width <= 0 || height <= 0) {
                    return null;
                }

                return { left, top, width, height, right: left + width, bottom: top + height };
            }

            function pointIsInsideActiveRect(clientX, clientY) {
                if (!Number.isFinite(clientX) || !Number.isFinite(clientY)) {
                    return false;
                }

                return activeRects.some(function(rect) {
                    return clientX >= rect.left && clientX <= rect.right && clientY >= rect.top && clientY <= rect.bottom;
                });
            }

            function eventIsInsideShield(event) {
                if (!active) { return false; }
                if (event.target && event.target.nodeType === 1 && event.target.getAttribute("data-sumi-transient-chrome-shield") === "true") {
                    return true;
                }

                return pointIsInsideActiveRect(Number(event.clientX), Number(event.clientY));
            }

            function ensureShieldElement(index) {
                if (shieldElements[index] && shieldElements[index].isConnected) {
                    return shieldElements[index];
                }

                const shieldId = shieldIdPrefix + index;
                const shieldElement = document.getElementById(shieldId) || document.createElement("div");
                shieldElement.id = shieldId;
                shieldElement.setAttribute("aria-hidden", "true");
                shieldElement.setAttribute("data-sumi-transient-chrome-shield", "true");
                Object.assign(shieldElement.style, {
                    position: "fixed",
                    zIndex: "2147483647",
                    background: "transparent",
                    pointerEvents: "auto",
                    cursor: "default",
                    userSelect: "none",
                    webkitUserSelect: "none",
                    touchAction: "none",
                    contain: "strict"
                });

                const parent = document.documentElement || document.body;
                if (parent) {
                    parent.appendChild(shieldElement);
                }
                shieldElements[index] = shieldElement;
                return shieldElement;
            }

            function removeShieldElements(fromIndex) {
                for (let i = fromIndex; i < shieldElements.length; i += 1) {
                    if (shieldElements[i]) {
                        shieldElements[i].remove();
                    }
                }
                shieldElements.length = fromIndex;
            }

            function applyRects(rects) {
                activeRects.length = 0;
                (Array.isArray(rects) ? rects : []).forEach(function(rect, index) {
                    const normalized = normalizeRect(rect);
                    if (!normalized) { return; }

                    activeRects.push(normalized);
                    const shieldElement = ensureShieldElement(index);
                    Object.assign(shieldElement.style, {
                        left: normalized.left + "px",
                        top: normalized.top + "px",
                        width: normalized.width + "px",
                        height: normalized.height + "px"
                    });
                });

                removeShieldElements(activeRects.length);
            }

            function stopPageEvent(event) {
                if (!eventIsInsideShield(event)) { return; }

                event.stopImmediatePropagation();
                event.stopPropagation();
                if (event.cancelable) {
                    event.preventDefault();
                }
            }

            function installEventBlockers() {
                blockedEventTypes.forEach(function(type) {
                    window.addEventListener(type, stopPageEvent, listenerOptions);
                    document.addEventListener(type, stopPageEvent, listenerOptions);
                });
            }

            function removeEventBlockers() {
                blockedEventTypes.forEach(function(type) {
                    window.removeEventListener(type, stopPageEvent, listenerOptions);
                    document.removeEventListener(type, stopPageEvent, listenerOptions);
                });
            }

            function dispatchExitEvents(target, relatedTarget, point) {
                if (!target || target === relatedTarget || (relatedTarget && relatedTarget.contains(target))) {
                    return;
                }

                const common = {
                    view: window,
                    bubbles: true,
                    cancelable: true,
                    composed: true,
                    clientX: point ? point.clientX : 0,
                    clientY: point ? point.clientY : 0,
                    relatedTarget: relatedTarget || null
                };

                try {
                    target.dispatchEvent(new MouseEvent("mouseout", common));
                    target.dispatchEvent(new MouseEvent("mouseleave", Object.assign({}, common, { bubbles: false })));
                } catch (_) {}

                if (typeof PointerEvent === "function") {
                    try {
                        target.dispatchEvent(new PointerEvent("pointerout", common));
                        target.dispatchEvent(new PointerEvent("pointerleave", Object.assign({}, common, { bubbles: false })));
                    } catch (_) {}
                }
            }

            function setActive(nextActive, point, rects) {
                nextActive = !!nextActive;

                if (nextActive) {
                    applyRects(rects);
                    if (activeRects.length === 0) {
                        setActive(false, null, []);
                        return;
                    }

                    const clampedPoint = clampPoint(point);
                    const previousTarget = clampedPoint ? document.elementFromPoint(clampedPoint.clientX, clampedPoint.clientY) : null;
                    const shield = shieldElements.find(function(element) {
                        return element && clampedPoint && pointIsInsideActiveRect(clampedPoint.clientX, clampedPoint.clientY);
                    }) || shieldElements[0] || null;
                    if (!active && clampedPoint && pointIsInsideActiveRect(clampedPoint.clientX, clampedPoint.clientY)) {
                        dispatchExitEvents(previousTarget, shield, clampedPoint);
                    }
                    if (!active) {
                        active = true;
                        installEventBlockers();
                    }
                } else {
                    if (!active && shieldElements.length === 0) { return; }
                    active = false;
                    removeEventBlockers();
                    activeRects.length = 0;
                    removeShieldElements(0);
                }
            }

            window.\(Self.apiName) = { setActive };
        })();
        """
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {}
}
