import Foundation

enum SumiElementZapperPageScript {
    static func picker(
        handlerName: String,
        configuration: SumiElementZapperSession.Configuration
    ) -> String {
        let handlerLiteral = jsonLiteral(handlerName)
        let initialStatusLiteral = jsonLiteral(configuration.initialStatus)
        let selectedStatusLiteral = jsonLiteral(configuration.selectedStatus)
        let editedStatusLiteral = jsonLiteral(configuration.editedStatus)

        return #"""
        (() => {
            const handlerName = \#(handlerLiteral);
            const initialStatus = \#(initialStatusLiteral);
            const selectedStatus = \#(selectedStatusLiteral);
            const editedStatus = \#(editedStatusLiteral);

            if (window.__sumiElementZapper && window.__sumiElementZapper.stop) {
                window.__sumiElementZapper.stop("restart");
            }
            if (window.__sumiAdblockZapper && window.__sumiAdblockZapper.stop) {
                window.__sumiAdblockZapper.stop("restart");
            }
            if (window.__sumiBoostZap && window.__sumiBoostZap.cleanup) {
                window.__sumiBoostZap.cleanup();
            }

            const cssEscape = window.CSS && CSS.escape
                ? CSS.escape
                : (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
            const style = document.createElement("style");
            style.setAttribute("data-sumi-element-zapper-style", "true");
            style.textContent = `
                html[data-sumi-element-zapper-active],
                html[data-sumi-element-zapper-active] * {
                    cursor: crosshair !important;
                }
            `;
            (document.head || document.documentElement).appendChild(style);
            document.documentElement.setAttribute("data-sumi-element-zapper-active", "true");

            const root = document.createElement("div");
            root.setAttribute("data-sumi-element-zapper-overlay", "true");
            Object.assign(root.style, {
                position: "fixed",
                inset: "0",
                zIndex: "2147483647",
                pointerEvents: "none"
            });

            const outline = document.createElement("div");
            outline.setAttribute("data-sumi-element-zapper-highlight", "true");
            Object.assign(outline.style, {
                position: "fixed",
                zIndex: "2147483647",
                pointerEvents: "none",
                border: "2px solid #0A84FF",
                background: "rgba(10, 132, 255, 0.18)",
                boxShadow: "0 0 0 99999px rgba(0, 0, 0, 0.22), 0 0 0 1px rgba(255, 255, 255, 0.52)",
                borderRadius: "3px",
                boxSizing: "border-box",
                display: "none"
            });

            root.append(outline);
            document.documentElement.appendChild(root);

            let target = null;
            let locked = false;
            let selectionStack = [];
            let selectorValue = "";
            let statusMessage = initialStatus;
            let statusIsError = false;
            let previewActive = false;
            let previewRecords = [];
            let lastStateJSON = "";
            let finished = false;

            function post(message) {
                window.webkit.messageHandlers[handlerName].postMessage(message);
            }

            function pushState() {
                const canRefine = locked && target && target.isConnected;
                const parent = canRefine ? selectableParent(target) : null;
                const state = {
                    type: "state",
                    selector: selectorValue,
                    status: statusMessage,
                    isError: statusIsError,
                    previewActive,
                    canCreate: !!selectorValue.trim(),
                    canSelectParent: !!parent,
                    canSelectChild: canRefine && selectionStack.length > 1
                };
                const stateJSON = JSON.stringify(state);
                if (stateJSON === lastStateJSON) { return; }
                lastStateJSON = stateJSON;
                post(state);
            }

            function setStatus(message, isError = false) {
                statusMessage = message;
                statusIsError = !!isError;
                pushState();
            }

            function setSelector(value) {
                selectorValue = value == null ? "" : String(value);
                pushState();
            }

            function selectableParent(element) {
                if (!element || !element.parentElement) { return null; }
                const parent = element.parentElement;
                if (parent === document.body || parent === document.documentElement) {
                    return null;
                }
                return parent;
            }

            function replaceSelectionStack(elements) {
                selectionStack.length = 0;
                for (const element of elements) {
                    if (element && element.isConnected) {
                        selectionStack.push(element);
                    }
                }
            }

            function isOverlayNode(node) {
                return node && root.contains(node);
            }

            function elementFromPointer(event) {
                const element = document.elementFromPoint(event.clientX, event.clientY);
                if (!element || isOverlayNode(element) || element === document.documentElement || element === document.body) {
                    return null;
                }
                return element;
            }

            function nthOfType(element) {
                let index = 1;
                let sibling = element;
                while ((sibling = sibling.previousElementSibling)) {
                    if (sibling.localName === element.localName) { index += 1; }
                }
                return index;
            }

            function selectorFor(element) {
                const parts = [];
                let current = element;
                while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.documentElement) {
                    const tag = current.localName;
                    if (!tag || tag === "body") { break; }
                    if (current.id) {
                        parts.unshift(`#${cssEscape(current.id)}`);
                        break;
                    }
                    const classes = Array.from(current.classList || [])
                        .filter((name) => name && !name.startsWith("sumi-"))
                        .slice(0, 2)
                        .map((name) => `.${cssEscape(name)}`)
                        .join("");
                    parts.unshift(`${tag}${classes}:nth-of-type(${nthOfType(current)})`);
                    current = current.parentElement;
                }
                return parts.join(" > ");
            }

            function updateOutline(element) {
                if (!element || !element.isConnected) {
                    outline.style.display = "none";
                    pushState();
                    return;
                }
                const rect = element.getBoundingClientRect();
                Object.assign(outline.style, {
                    display: "block",
                    left: `${Math.max(0, rect.left)}px`,
                    top: `${Math.max(0, rect.top)}px`,
                    width: `${Math.max(0, rect.width)}px`,
                    height: `${Math.max(0, rect.height)}px`
                });
                pushState();
            }

            function setTarget(element, shouldLock, history) {
                if (shouldLock && previewActive) {
                    restorePreview();
                }
                target = element;
                locked = shouldLock;
                if (shouldLock) {
                    replaceSelectionStack(history && history.length ? history : [element]);
                } else {
                    replaceSelectionStack([element]);
                }
                const selector = selectorFor(element);
                setSelector(selector);
                updateOutline(element);
                if (shouldLock) {
                    setStatus(selectedStatus);
                    setPreview(true);
                } else {
                    setStatus("Click to preview this element.");
                }
            }

            function restorePreview() {
                for (const record of previewRecords) {
                    if (!record.element || !record.element.isConnected) { continue; }
                    if (record.display) {
                        record.element.style.setProperty("display", record.display, record.priority);
                    } else {
                        record.element.style.removeProperty("display");
                    }
                }
                previewRecords = [];
                previewActive = false;
                pushState();
            }

            function elementsForSelector(selector) {
                try {
                    return Array.from(document.querySelectorAll(selector))
                        .filter((element) => !isOverlayNode(element));
                } catch (_) {
                    setStatus("Invalid CSS selector.", true);
                    return null;
                }
            }

            function setPreview(isEnabled) {
                restorePreview();
                if (!isEnabled) {
                    setStatus("Preview disabled. The selector will still be saved.");
                    return true;
                }
                const selector = selectorValue.trim();
                if (!selector) {
                    setStatus("Choose an element or enter a selector first.", true);
                    return false;
                }
                const elements = elementsForSelector(selector);
                if (!elements) { return false; }
                if (!elements.length) {
                    setStatus("Selector does not match any element on this page.", true);
                    return false;
                }
                previewRecords = elements.map((element) => ({
                    element,
                    display: element.style.getPropertyValue("display"),
                    priority: element.style.getPropertyPriority("display")
                }));
                for (const element of elements) {
                    element.style.setProperty("display", "none", "important");
                }
                previewActive = true;
                pushState();
                setStatus(`Preview hides ${elements.length} element${elements.length === 1 ? "" : "s"}.`);
                return true;
            }

            function move(event) {
                if (locked || isOverlayNode(event.target)) { return; }
                const element = elementFromPointer(event);
                if (!element) {
                    target = null;
                    outline.style.display = "none";
                    replaceSelectionStack([]);
                    setSelector("");
                    setStatus(initialStatus);
                    return;
                }
                if (target !== element) {
                    setTarget(element, false);
                } else {
                    updateOutline(element);
                }
            }

            function stop(reason) {
                if (finished) { return; }
                finished = true;
                restorePreview();
                window.removeEventListener("mousemove", move, true);
                window.removeEventListener("click", click, true);
                window.removeEventListener("keydown", keydown, true);
                window.removeEventListener("contextmenu", cancel, true);
                window.removeEventListener("scroll", refreshOutline, true);
                window.removeEventListener("resize", refreshOutline, true);
                document.documentElement.removeAttribute("data-sumi-element-zapper-active");
                style.remove();
                root.remove();
                if (window.__sumiElementZapper && window.__sumiElementZapper.stop === stop) {
                    window.__sumiElementZapper = null;
                }
                if (reason !== "selected") {
                    post({ type: "cancelled", reason });
                }
            }

            function click(event) {
                if (isOverlayNode(event.target)) { return; }
                const element = elementFromPointer(event);
                if (!element) { return; }
                event.preventDefault();
                event.stopPropagation();
                setTarget(element, true);
            }

            function selectParentTarget() {
                const parent = selectableParent(target);
                if (!parent) { return; }
                const history = selectionStack.length
                    ? selectionStack.concat(parent)
                    : [target, parent].filter(Boolean);
                setTarget(parent, true, history);
            }

            function selectChildTarget() {
                if (selectionStack.length <= 1) { return; }
                const history = selectionStack.slice(0, -1);
                setTarget(history[history.length - 1], true, history);
            }

            function createRule() {
                const selector = selectorValue.trim();
                if (!selector) {
                    setStatus("Choose an element or enter a selector first.", true);
                    return;
                }
                const elements = elementsForSelector(selector);
                if (!elements || !elements.length) { return; }
                restorePreview();
                post({ type: "selected", selector });
                stop("selected");
            }

            function keydown(event) {
                if (event.key === "Escape") {
                    event.preventDefault();
                    stop("escape");
                } else if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
                    event.preventDefault();
                    createRule();
                }
            }

            function cancel(event) {
                event.preventDefault();
                stop("contextmenu");
            }

            function refreshOutline() {
                if (target) { updateOutline(target); }
            }

            function editSelector(selector) {
                restorePreview();
                locked = true;
                replaceSelectionStack([]);
                setSelector(selector);
                setStatus(editedStatus);
            }

            function command(message) {
                if (finished || !message || typeof message.type !== "string") { return; }
                switch (message.type) {
                case "setSelector":
                    editSelector(message.selector);
                    break;
                case "togglePreview":
                    setPreview(!previewActive);
                    break;
                case "selectParent":
                    selectParentTarget();
                    break;
                case "selectChild":
                    selectChildTarget();
                    break;
                case "create":
                    createRule();
                    break;
                case "cancel":
                    stop("cancel");
                    break;
                default:
                    break;
                }
            }

            window.__sumiElementZapper = { stop, command };
            window.addEventListener("mousemove", move, true);
            window.addEventListener("click", click, true);
            window.addEventListener("keydown", keydown, true);
            window.addEventListener("contextmenu", cancel, true);
            window.addEventListener("scroll", refreshOutline, true);
            window.addEventListener("resize", refreshOutline, true);
            pushState();
            return true;
        })();
        """#
    }

    static func stop(reason: String) -> String {
        let reasonLiteral = jsonLiteral(reason)
        return #"""
        (() => {
            if (window.__sumiElementZapper && window.__sumiElementZapper.stop) {
                window.__sumiElementZapper.stop(\#(reasonLiteral));
            }
        })();
        """#
    }

    static func jsonLiteral<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8)
        else { return "null" }
        return string
    }
}
