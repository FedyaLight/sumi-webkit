//
//  Tab+JavaScriptInjection.swift
//  Sumi
//

import Foundation
import WebKit

extension Tab {
    func injectLinkHoverJavaScript(to webView: WKWebView) {
        let glanceActivationMethod = (sumiSettings?.glanceActivationMethod ?? .alt).rawValue
        let linkHoverHandlerName = coreScriptMessageHandlerName("linkHover")
        let commandHoverHandlerName = coreScriptMessageHandlerName("commandHover")
        let commandClickHandlerName = coreScriptMessageHandlerName("commandClick")
        let linkHoverScript = """
            (function() {
                if (window.__sumiLinkHoverInstalled) { return; }
                window.__sumiLinkHoverInstalled = true;
                var currentHoveredLink = null;
                var isCommandPressed = false;
                var glanceActivationMethod = "\(glanceActivationMethod)";
                var linkHoverHandlerName = "\(linkHoverHandlerName)";
                var commandHoverHandlerName = "\(commandHoverHandlerName)";
                var commandClickHandlerName = "\(commandClickHandlerName)";
                var pointerDownLink = null;
                var pointerDownFlags = null;

                function sendLinkHover(href) {
                    var handler = window.webkit?.messageHandlers?.[linkHoverHandlerName];
                    if (handler) {
                        handler.postMessage(href);
                    }
                }

                function sendCommandHover(href) {
                    var handler = window.webkit?.messageHandlers?.[commandHoverHandlerName];
                    if (handler) {
                        handler.postMessage(href);
                    }
                }

                function findLinkTarget(start) {
                    var target = start;
                    while (target && target !== document) {
                        if (target.tagName === 'A' && target.href) {
                            return target;
                        }
                        target = target.parentElement;
                    }
                    return null;
                }

                function hasSingleModifier(event) {
                    var count = 0;
                    if (event.metaKey) count++;
                    if (event.altKey) count++;
                    if (event.ctrlKey) count++;
                    if (event.shiftKey) count++;
                    return count === 1;
                }

                function matchesGlanceModifier(event) {
                    switch (glanceActivationMethod) {
                        case 'ctrl':
                            return event.ctrlKey;
                        case 'alt':
                            return event.altKey;
                        case 'shift':
                            return event.shiftKey;
                        case 'meta':
                            return event.metaKey;
                        default:
                            return false;
                    }
                }

                function capturePointerDown(event) {
                    var target = findLinkTarget(event.target);
                    if (!target || event.button !== 0 || !hasSingleModifier(event)) {
                        pointerDownLink = null;
                        pointerDownFlags = null;
                        return;
                    }

                    pointerDownLink = target.href;
                    pointerDownFlags = {
                        altKey: !!event.altKey,
                        ctrlKey: !!event.ctrlKey,
                        shiftKey: !!event.shiftKey,
                        metaKey: !!event.metaKey
                    };
                }

                document.addEventListener('keydown', function(e) {
                    if (e.metaKey) {
                        isCommandPressed = true;
                        if (currentHoveredLink) {
                            sendCommandHover(currentHoveredLink);
                        }
                    }
                });

                document.addEventListener('keyup', function(e) {
                    if (!e.metaKey) {
                        isCommandPressed = false;
                        sendCommandHover(null);
                    }
                });

                function updateHoveredLink(link) {
                    var href = link && link.href ? link.href : null;
                    if (currentHoveredLink === href) {
                        return;
                    }

                    currentHoveredLink = href;
                    sendLinkHover(href);
                    if (isCommandPressed) {
                        sendCommandHover(href);
                    } else if (!href) {
                        sendCommandHover(null);
                    }
                }

                document.addEventListener('mouseover', function(e) {
                    updateHoveredLink(findLinkTarget(e.target));
                }, { passive: true, capture: true });

                document.addEventListener('mouseout', function(e) {
                    if (!currentHoveredLink) {
                        return;
                    }

                    var nextTarget = findLinkTarget(e.relatedTarget);
                    if (nextTarget && nextTarget.href === currentHoveredLink) {
                        return;
                    }

                    updateHoveredLink(null);
                }, { passive: true, capture: true });

                document.addEventListener('mousedown', capturePointerDown, true);

                document.addEventListener('click', function(e) {
                    var target = findLinkTarget(e.target);
                    if (!target || e.button !== 0 || e.defaultPrevented || !hasSingleModifier(e)) {
                        pointerDownLink = null;
                        pointerDownFlags = null;
                        return;
                    }

                    var shouldOpenInGlance = matchesGlanceModifier(e);
                    var shouldOpenInNewTab = e.metaKey && glanceActivationMethod !== 'meta';
                    if (!shouldOpenInGlance && !shouldOpenInNewTab) {
                        return;
                    }

                    e.preventDefault();
                    e.stopPropagation();
                    if (e.stopImmediatePropagation) {
                        e.stopImmediatePropagation();
                    }

                    var handler = window.webkit?.messageHandlers?.[commandClickHandlerName];
                    if (handler) {
                        handler.postMessage({
                            href: pointerDownLink || target.href,
                            altKey: pointerDownFlags ? pointerDownFlags.altKey : !!e.altKey,
                            ctrlKey: pointerDownFlags ? pointerDownFlags.ctrlKey : !!e.ctrlKey,
                            shiftKey: pointerDownFlags ? pointerDownFlags.shiftKey : !!e.shiftKey,
                            metaKey: pointerDownFlags ? pointerDownFlags.metaKey : !!e.metaKey
                        });
                    }
                    pointerDownLink = null;
                    pointerDownFlags = null;
                    return false;
                }, true);
            })();
            """

        webView.evaluateJavaScript(linkHoverScript) { _, error in
            if let error = error {
                RuntimeDiagnostics.emit(
                    "Error injecting link hover JavaScript: \(error.localizedDescription)"
                )
            }
        }
    }
}
