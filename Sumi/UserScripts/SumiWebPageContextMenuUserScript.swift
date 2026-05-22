import Foundation
import WebKit

@MainActor
final class SumiWebPageContextMenuUserScript: NSObject, SumiUserScript {
    private weak var tab: Tab?
    private let context: String

    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(tab: Tab) {
        self.tab = tab
        self.context = "sumiWebPageContextMenu_\(tab.id.uuidString)"
        self.messageNames = [context]
        self.source = Self.makeSource(context: context)
        super.init()
    }

    private static func makeSource(context: String) -> String {
        """
        (function() {
            if (window.__sumiWebPageContextMenuInstalled) { return; }
            window.__sumiWebPageContextMenuInstalled = true;

            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers["\(context)"];
            if (!handler) { return; }

            function closestElement(start, predicate) {
                let node = start;
                while (node && node !== document) {
                    if (node.nodeType === 1 && predicate(node)) {
                        return node;
                    }
                    node = node.parentElement;
                }
                return null;
            }

            function localName(element) {
                return element && element.localName ? element.localName.toLowerCase() : "";
            }

            function isEditable(element) {
                const tag = localName(element);
                if (element.isContentEditable) { return true; }
                if (tag === "textarea" || tag === "select") { return true; }
                if (tag !== "input") { return false; }
                const type = (element.getAttribute("type") || "text").toLowerCase();
                return !["button", "checkbox", "color", "file", "hidden", "image", "radio", "range", "reset", "submit"].includes(type);
            }

            function isInteractive(element) {
                const tag = localName(element);
                const role = (element.getAttribute("role") || "").toLowerCase();
                if (["button", "details", "label", "option", "select", "summary"].includes(tag)) { return true; }
                if (tag === "input" && !isEditable(element)) { return true; }
                if (element.hasAttribute("onclick")) { return true; }
                if (element.tabIndex >= 0 && role) { return true; }
                return ["button", "checkbox", "combobox", "link", "menuitem", "option", "radio", "switch", "tab"].includes(role);
            }

            function classifyTarget(target) {
                if (!target || target === document || target === document.documentElement || target === document.body) {
                    return "page";
                }

                if (closestElement(target, function(element) { return isEditable(element); })) {
                    return "editable";
                }
                if (closestElement(target, function(element) { return localName(element) === "a" && element.href; })) {
                    return "link";
                }
                if (closestElement(target, function(element) { return localName(element) === "img"; })) {
                    return "image";
                }
                if (closestElement(target, function(element) { return ["audio", "video"].includes(localName(element)); })) {
                    return "media";
                }
                if (closestElement(target, function(element) { return isInteractive(element); })) {
                    return "interactiveElement";
                }
                return "otherElement";
            }

            function selectionTextForTarget(target) {
                const selection = window.getSelection && window.getSelection();
                if (!selection || selection.rangeCount === 0) { return null; }

                const text = String(selection.toString() || "").trim();
                if (!text) { return null; }

                const node = target && target.nodeType === Node.TEXT_NODE ? target.parentElement : target;
                if (!node) { return null; }

                for (let index = 0; index < selection.rangeCount; index += 1) {
                    try {
                        if (selection.getRangeAt(index).intersectsNode(node)) {
                            return text.slice(0, 500);
                        }
                    } catch (_) {}
                }
                return null;
            }

            document.addEventListener("contextmenu", function(event) {
                handler.postMessage({
                    kind: classifyTarget(event.target),
                    selectedText: selectionTextForTarget(event.target)
                });
            }, { capture: true, passive: true });
        })();
        """
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        guard let dictionary = message.body as? [String: Any],
              let rawKind = dictionary["kind"] as? String,
              let kind = SumiWebPageContextMenuTargetKind(rawValue: rawKind)
        else { return }
        tab?.lastWebPageContextMenuTarget = SumiWebPageContextMenuTargetSnapshot(
            kind: kind,
            selectedText: dictionary["selectedText"] as? String
        )
    }
}
