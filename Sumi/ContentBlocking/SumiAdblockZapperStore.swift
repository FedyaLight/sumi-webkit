import Foundation
import WebKit

@MainActor
final class SumiAdblockZapperStore {
    struct State: Codable, Equatable {
        var rules: [String]
        var disabled: Bool

        static let empty = State(rules: [], disabled: false)
    }

    static let shared = SumiAdblockZapperStore()

    private enum DefaultsKey {
        static let statesByPersistentProfileAndHost = "settings.adblock.zapper.statesByPersistentProfileAndHost.v1"
    }

    private struct Scope {
        static let persistentPrefix = "persistent:"
        static let ephemeralPrefix = "ephemeral:"

        let storageKey: String
        let isEphemeral: Bool

        init?(
            profilePartitionId: String,
            isEphemeralProfile: Bool
        ) {
            let normalizedProfileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
            guard !normalizedProfileId.isEmpty else { return nil }

            self.storageKey = "\(isEphemeralProfile ? Self.ephemeralPrefix : Self.persistentPrefix)\(normalizedProfileId)"
            self.isEphemeral = isEphemeralProfile
        }
    }

    private let userDefaults: UserDefaults
    private var statesByScopeAndHost: [String: [String: State]]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.statesByScopeAndHost = Self.loadPersistentStates(from: userDefaults)
    }

    func state(
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) -> State {
        guard let scope = Scope(
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) else {
            return .empty
        }

        let normalizedHost = normalizedHost(host)
        guard !normalizedHost.isEmpty else { return .empty }
        return statesByScopeAndHost[scope.storageKey]?[normalizedHost] ?? .empty
    }

    func setRules(
        _ rules: [String],
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) {
        updateState(
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) { state in
            state.rules = Self.normalizedRules(rules)
        }
    }

    func appendRule(
        _ rule: String,
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) {
        let normalizedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRule.isEmpty else { return }
        updateState(
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) { state in
            guard !state.rules.contains(normalizedRule) else { return }
            state.rules.append(normalizedRule)
        }
    }

    func setEnabled(
        _ isEnabled: Bool,
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) {
        updateState(
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) { state in
            state.disabled = !isEnabled
        }
    }

    private func updateState(
        forHost host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        mutate: (inout State) -> Void
    ) {
        guard let scope = Scope(
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        ) else {
            return
        }

        let normalizedHost = normalizedHost(host)
        guard !normalizedHost.isEmpty else { return }

        var hostStates = statesByScopeAndHost[scope.storageKey] ?? [:]
        var state = hostStates[normalizedHost] ?? .empty
        mutate(&state)
        if state == .empty {
            hostStates.removeValue(forKey: normalizedHost)
        } else {
            hostStates[normalizedHost] = state
        }
        if hostStates.isEmpty {
            statesByScopeAndHost.removeValue(forKey: scope.storageKey)
        } else {
            statesByScopeAndHost[scope.storageKey] = hostStates
        }
        if !scope.isEphemeral {
            savePersistentStates()
        }
    }

    private func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private func savePersistentStates() {
        let persistentStates = statesByScopeAndHost.filter { scopeKey, _ in
            scopeKey.hasPrefix(Scope.persistentPrefix)
        }
        guard !persistentStates.isEmpty else {
            userDefaults.removeObject(forKey: DefaultsKey.statesByPersistentProfileAndHost)
            return
        }
        guard let data = try? JSONEncoder().encode(persistentStates) else { return }
        userDefaults.set(data, forKey: DefaultsKey.statesByPersistentProfileAndHost)
    }

    private static func loadPersistentStates(from userDefaults: UserDefaults) -> [String: [String: State]] {
        guard let data = userDefaults.data(forKey: DefaultsKey.statesByPersistentProfileAndHost),
              let decoded = try? JSONDecoder().decode([String: [String: State]].self, from: data)
        else { return [:] }
        return decoded.filter { scopeKey, _ in
            scopeKey.hasPrefix(Scope.persistentPrefix)
        }
    }

    private static func normalizedRules(_ rules: [String]) -> [String] {
        var seen = Set<String>()
        return rules.compactMap { rule in
            let trimmedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRule.isEmpty,
                  seen.insert(trimmedRule).inserted
            else {
                return nil
            }
            return trimmedRule
        }
    }
}

@MainActor
enum SumiAdblockZapperInjector {
    private static let styleElementID = "sumi-adblock-zapper-style"

    static func applySavedRules(
        to webView: WKWebView,
        host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        store: SumiAdblockZapperStore? = nil
    ) {
        let store = store ?? .shared
        let state = store.state(
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        )
        let rules = state.disabled ? [] : state.rules
        webView.evaluateJavaScript(applyRulesScript(rules: rules)) { _, _ in }
    }

    static func clearAppliedRules(to webView: WKWebView) {
        webView.evaluateJavaScript(applyRulesScript(rules: [])) { _, _ in }
    }

    static func activateElementPicker(
        in webView: WKWebView,
        host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        store: SumiAdblockZapperStore? = nil
    ) async -> Bool {
        let store = store ?? .shared
        let handlerName = "sumiAdblockZapper\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let userContentController = webView.configuration.userContentController
        let handler = SumiAdblockZapperMessageHandler(
            name: handlerName,
            host: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile,
            webView: webView,
            userContentController: userContentController,
            store: store
        )
        userContentController.add(handler, name: handlerName)

        let didInstall = await evaluate(
            elementPickerScript(handlerName: handlerName),
            in: webView
        )
        if didInstall {
            handler.scheduleTimeout()
        } else {
            handler.finish()
        }
        return didInstall
    }

    fileprivate static func applyRulesScript(rules: [String]) -> String {
        let rulesLiteral = jsonLiteral(rules)
        return #"""
        (() => {
            const id = "\#(styleElementID)";
            const selectors = \#(rulesLiteral);
            const hiddenSelector = "[data-sumi-adblock-zapper-hidden]";
            function restoreInlineHides() {
                document.querySelectorAll(hiddenSelector).forEach((element) => {
                    const previousDisplay = element.getAttribute("data-sumi-adblock-zapper-display-value");
                    const previousPriority = element.getAttribute("data-sumi-adblock-zapper-display-priority") || "";
                    if (previousDisplay) {
                        element.style.setProperty("display", previousDisplay, previousPriority);
                    } else {
                        element.style.removeProperty("display");
                    }
                    element.removeAttribute("data-sumi-adblock-zapper-hidden");
                    element.removeAttribute("data-sumi-adblock-zapper-display-value");
                    element.removeAttribute("data-sumi-adblock-zapper-display-priority");
                });
            }

            let style = document.getElementById(id);
            restoreInlineHides();
            if (!selectors.length) {
                if (style) { style.remove(); }
                return true;
            }
            if (!style) {
                style = document.createElement("style");
                style.id = id;
                style.setAttribute("data-sumi-adblock-zapper", "true");
                (document.head || document.documentElement).appendChild(style);
            }
            while (style.sheet && style.sheet.cssRules.length) {
                style.sheet.deleteRule(0);
            }
            for (const selector of selectors) {
                try {
                    style.sheet.insertRule(`${selector}{display:none!important}`, style.sheet.cssRules.length);
                } catch (_) {}
                try {
                    document.querySelectorAll(selector).forEach((element) => {
                        if (!element.hasAttribute("data-sumi-adblock-zapper-hidden")) {
                            element.setAttribute("data-sumi-adblock-zapper-hidden", "true");
                            element.setAttribute(
                                "data-sumi-adblock-zapper-display-value",
                                element.style.getPropertyValue("display")
                            );
                            element.setAttribute(
                                "data-sumi-adblock-zapper-display-priority",
                                element.style.getPropertyPriority("display")
                            );
                        }
                        element.style.setProperty("display", "none", "important");
                    });
                } catch (_) {}
            }
            return true;
        })();
        """#
    }

    private static func elementPickerScript(handlerName: String) -> String {
        let handlerLiteral = jsonLiteral(handlerName)
        return #"""
        (() => {
            const handlerName = \#(handlerLiteral);
            if (window.__sumiAdblockZapper && window.__sumiAdblockZapper.stop) {
                window.__sumiAdblockZapper.stop("restart");
            }
            const cssEscape = window.CSS && CSS.escape
                ? CSS.escape
                : (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
            const root = document.createElement("div");
            root.setAttribute("data-sumi-adblock-zapper-overlay", "true");
            Object.assign(root.style, {
                position: "fixed",
                inset: "0",
                zIndex: "2147483647",
                pointerEvents: "none",
                fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif",
                color: "#F5F5F7"
            });

            const outline = document.createElement("div");
            outline.setAttribute("data-sumi-adblock-zapper-highlight", "true");
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

            const toolbar = document.createElement("div");
            toolbar.setAttribute("data-sumi-adblock-zapper-toolbar", "true");
            Object.assign(toolbar.style, {
                position: "fixed",
                left: "50%",
                bottom: "24px",
                transform: "translateX(-50%)",
                width: "min(720px, calc(100vw - 32px))",
                zIndex: "2147483647",
                pointerEvents: "auto",
                display: "grid",
                gridTemplateColumns: "1fr auto",
                gap: "10px 12px",
                alignItems: "center",
                padding: "12px",
                background: "rgba(26, 26, 28, 0.96)",
                border: "1px solid rgba(255, 255, 255, 0.18)",
                borderRadius: "8px",
                boxShadow: "0 18px 54px rgba(0, 0, 0, 0.36)",
                backdropFilter: "saturate(140%) blur(18px)",
                WebkitBackdropFilter: "saturate(140%) blur(18px)"
            });
            toolbar.innerHTML = `
                <div style="min-width:0">
                    <div style="font-size:12px;font-weight:700;letter-spacing:0;text-transform:uppercase;color:rgba(255,255,255,.64);margin-bottom:6px">Sumi Element Zapper</div>
                    <input data-sumi-zapper-selector spellcheck="false" style="box-sizing:border-box;width:100%;height:30px;border-radius:6px;border:1px solid rgba(255,255,255,.22);background:rgba(255,255,255,.1);color:#fff;padding:0 9px;font:12px ui-monospace,SFMono-Regular,Menlo,monospace;outline:none" />
                    <div data-sumi-zapper-status style="min-height:16px;margin-top:5px;font-size:11px;color:rgba(255,255,255,.64);white-space:nowrap;overflow:hidden;text-overflow:ellipsis">Hover an element, click to preview, then create the rule.</div>
                </div>
                <div style="display:flex;gap:8px;align-self:end">
                    <button data-sumi-zapper-preview style="height:30px;border-radius:6px;border:1px solid rgba(255,255,255,.22);background:rgba(255,255,255,.11);color:#fff;padding:0 11px;font:12px -apple-system,BlinkMacSystemFont,system-ui,sans-serif">Preview</button>
                    <button data-sumi-zapper-create style="height:30px;border-radius:6px;border:1px solid rgba(10,132,255,.95);background:#0A84FF;color:#fff;padding:0 13px;font:600 12px -apple-system,BlinkMacSystemFont,system-ui,sans-serif">Create</button>
                    <button data-sumi-zapper-cancel style="height:30px;border-radius:6px;border:1px solid rgba(255,255,255,.2);background:transparent;color:rgba(255,255,255,.82);padding:0 11px;font:12px -apple-system,BlinkMacSystemFont,system-ui,sans-serif">Cancel</button>
                </div>
            `;
            root.append(outline, toolbar);
            document.documentElement.appendChild(root);

            const selectorInput = toolbar.querySelector("[data-sumi-zapper-selector]");
            const statusLabel = toolbar.querySelector("[data-sumi-zapper-status]");
            const previewButton = toolbar.querySelector("[data-sumi-zapper-preview]");
            const createButton = toolbar.querySelector("[data-sumi-zapper-create]");
            const cancelButton = toolbar.querySelector("[data-sumi-zapper-cancel]");
            let target = null;
            let locked = false;
            let previewActive = false;
            let previewRecords = [];
            let finished = false;

            function post(message) {
                window.webkit.messageHandlers[handlerName].postMessage(message);
            }

            function setStatus(message, isError = false) {
                statusLabel.textContent = message;
                statusLabel.style.color = isError
                    ? "rgba(255, 104, 104, 0.92)"
                    : "rgba(255, 255, 255, 0.64)";
            }

            function updateButtons() {
                previewButton.textContent = previewActive ? "Unpreview" : "Preview";
                createButton.disabled = !selectorInput.value.trim();
                createButton.style.opacity = createButton.disabled ? "0.45" : "1";
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
            }

            function setTarget(element, shouldLock) {
                target = element;
                locked = shouldLock;
                const selector = selectorFor(element);
                selectorInput.value = selector;
                updateOutline(element);
                updateButtons();
                if (shouldLock) {
                    setStatus("Previewing the selected selector. Edit it before creating if needed.");
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
                updateButtons();
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
                    setStatus("Preview disabled. Create will still save the selector.");
                    return true;
                }
                const selector = selectorInput.value.trim();
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
                updateButtons();
                setStatus(`Preview hides ${elements.length} element${elements.length === 1 ? "" : "s"}.`);
                return true;
            }

            function move(event) {
                if (locked || isOverlayNode(event.target)) { return; }
                const element = elementFromPointer(event);
                if (!element) {
                    target = null;
                    outline.style.display = "none";
                    selectorInput.value = "";
                    updateButtons();
                    setStatus("Hover an element, click to preview, then create the rule.");
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
                root.remove();
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

            function createRule() {
                const selector = selectorInput.value.trim();
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

            selectorInput.addEventListener("input", () => {
                restorePreview();
                locked = true;
                updateButtons();
                setStatus("Selector edited. Preview it before creating.");
            });
            previewButton.addEventListener("click", (event) => {
                event.preventDefault();
                setPreview(!previewActive);
            });
            createButton.addEventListener("click", (event) => {
                event.preventDefault();
                createRule();
            });
            cancelButton.addEventListener("click", (event) => {
                event.preventDefault();
                stop("cancel");
            });

            window.__sumiAdblockZapper = { stop };
            window.addEventListener("mousemove", move, true);
            window.addEventListener("click", click, true);
            window.addEventListener("keydown", keydown, true);
            window.addEventListener("contextmenu", cancel, true);
            window.addEventListener("scroll", refreshOutline, true);
            window.addEventListener("resize", refreshOutline, true);
            selectorInput.focus({ preventScroll: true });
            updateButtons();
            return true;
        })();
        """#
    }

    private static func evaluate(_ script: String, in webView: WKWebView) async -> Bool {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private static func jsonLiteral<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8)
        else { return "null" }
        return string
    }
}

private final class SumiAdblockZapperMessageHandler: NSObject, WKScriptMessageHandler {
    private let name: String
    private let host: String
    private let profilePartitionId: String
    private let isEphemeralProfile: Bool
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private let store: SumiAdblockZapperStore
    private var didFinish = false

    init(
        name: String,
        host: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        webView: WKWebView,
        userContentController: WKUserContentController,
        store: SumiAdblockZapperStore
    ) {
        self.name = name
        self.host = host
        self.profilePartitionId = profilePartitionId
        self.isEphemeralProfile = isEphemeralProfile
        self.webView = webView
        self.userContentController = userContentController
        self.store = store
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }

        let selector = body["selector"] as? String
        Task { @MainActor [weak self] in
            self?.handleMessage(type: type, selector: selector)
        }
    }

    @MainActor
    func scheduleTimeout() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000_000)
            guard let self,
                  !self.didFinish
            else { return }
            self.stopInPagePicker(reason: "timeout")
            self.finish()
        }
    }

    @MainActor
    fileprivate func finish() {
        guard !didFinish else { return }
        didFinish = true
        userContentController?.removeScriptMessageHandler(forName: name)
    }

    @MainActor
    private func stopInPagePicker(reason: String) {
        let script = """
        (() => {
            if (window.__sumiAdblockZapper && window.__sumiAdblockZapper.stop) {
                window.__sumiAdblockZapper.stop("\(reason)");
            }
        })();
        """
        webView?.evaluateJavaScript(script) { _, _ in }
    }

    @MainActor
    private func handleMessage(type: String, selector: String?) {
        defer { finish() }
        guard type == "selected",
              let selector
        else { return }

        store.appendRule(
            selector,
            forHost: host,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        )
        if let webView {
            SumiAdblockZapperInjector.applySavedRules(
                to: webView,
                host: host,
                profilePartitionId: profilePartitionId,
                isEphemeralProfile: isEphemeralProfile,
                store: store
            )
        }
    }
}
