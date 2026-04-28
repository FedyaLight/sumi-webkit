import AppKit
import Foundation
import UserScript
import WebKit

extension Tab {
    func normalTabCoreUserScripts() -> [UserScript] {
        [
            SumiLinkInteractionUserScript(tab: self),
            SumiIdentityUserScript(tab: self),
            SumiTabSuspensionUserScript(tab: self),
            SumiWebNotificationUserScript(tab: self),
        ]
    }

    func setClickModifierFlags(_ flags: NSEvent.ModifierFlags) {
        clickModifierFlags = flags.intersection([.command, .option, .control, .shift])
    }

    func isGlanceTriggerActive(_ flags: NSEvent.ModifierFlags? = nil) -> Bool {
        guard sumiSettings?.glanceEnabled ?? true else { return false }

        let activeFlags = flags ?? clickModifierFlags
        switch sumiSettings?.glanceActivationMethod ?? .alt {
        case .ctrl:
            return activeFlags.contains(.control)
        case .alt:
            return activeFlags.contains(.option)
        case .shift:
            return activeFlags.contains(.shift)
        case .meta:
            return activeFlags.contains(.command)
        }
    }

    func openURLInGlance(_ url: URL) {
        browserManager?.peekManager.presentExternalURL(url, from: self)
    }

    func handleModifiedLinkClick(url: URL, flags: NSEvent.ModifierFlags) {
        if isGlanceTriggerActive(flags) {
            openURLInGlance(url)
        } else if flags.contains(.command) {
            let context = BrowserManager.TabOpenContext.background(
                windowState: browserManager?.windowState(containing: self),
                sourceTab: self,
                preferredSpaceId: spaceId
            )
            browserManager?.openNewTab(
                url: url.absoluteString,
                context: context
            )
        }
    }

    func navigationModifierFlags(from navigationAction: WKNavigationAction) -> NSEvent.ModifierFlags {
        let flags = navigationAction.modifierFlags.intersection([.command, .option, .control, .shift])
        return flags.isEmpty ? clickModifierFlags : flags
    }

    func handleOAuthRequest(url: URL, interactive: Bool, requestId: String) {
        RuntimeDiagnostics.emit(
            "🔐 [Tab] OAuth request received: id=\(requestId) url=\(url.absoluteString) interactive=\(interactive)"
        )

        guard let manager = browserManager else {
            finishIdentityFlow(requestId: requestId, with: .failure(.unableToStart))
            return
        }

        let identityRequest = AuthenticationManager.IdentityRequest(
            requestId: requestId,
            url: url,
            interactive: interactive
        )

        manager.authenticationManager.beginIdentityFlow(identityRequest, from: self)
    }

    func finishIdentityFlow(
        requestId: String,
        with result: AuthenticationManager.IdentityFlowResult
    ) {
        guard let webView = existingWebView else {
            RuntimeDiagnostics.emit("⚠️ [Tab] Unable to deliver identity result; webView missing")
            return
        }

        var payload: [String: Any] = ["requestId": requestId]

        switch result {
        case .success(let url):
            payload["status"] = "success"
            payload["url"] = url.absoluteString
        case .cancelled:
            payload["status"] = "cancelled"
            payload["code"] = "cancelled"
            payload["message"] = "Authentication cancelled by user."
        case .failure(let failure):
            payload["status"] = "failure"
            payload["code"] = failure.code
            payload["message"] = failure.message
        }

        if let status = payload["status"] as? String {
            let urlDescription = payload["url"] as? String ?? "nil"
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Identity flow completed: id=\(requestId) status=\(status) url=\(urlDescription)"
            )
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: data, encoding: .utf8) else {
            RuntimeDiagnostics.emit("❌ [Tab] Failed to serialise identity payload for requestId=\(requestId)")
            return
        }

        let script =
            "window.__nookCompleteIdentityFlow && window.__nookCompleteIdentityFlow(\(jsonString));"
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                RuntimeDiagnostics.emit("❌ [Tab] Failed to deliver identity result: \(error.localizedDescription)")
            }
        }
    }

    func shouldRedirectToPeek(url: URL) -> Bool {
        if isGlanceTriggerActive() {
            return true
        }

        guard let currentHost = self.url.host,
              let newHost = url.host else { return false }

        return currentHost != newHost
    }
}

@MainActor
private final class SumiLinkInteractionUserScript: NSObject, UserScript, UserScriptMessaging, WKScriptMessageHandlerWithReply {
    private let context: String
    let broker: UserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(tab: Tab) {
        self.context = "sumiLinkInteraction_\(tab.id.uuidString)"
        self.broker = UserScriptMessageBroker(context: context, requiresRunInPageContentWorld: true)
        self.messageNames = [context]
        self.source = Self.makeSource(
            context: context,
            glanceActivationMethod: (tab.sumiSettings?.glanceActivationMethod ?? .alt).rawValue
        )
        super.init()
        registerSubfeature(delegate: SumiLinkInteractionSubfeature(tab: tab))
    }

    private static func makeSource(context: String, glanceActivationMethod: String) -> String {
        """
        (function() {
            if (window.__sumiLinkInteractionInstalled) { return; }
            window.__sumiLinkInteractionInstalled = true;

            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers["\(context)"];
            if (!handler) { return; }

            let currentHoveredLink = null;
            let isCommandPressed = { value: false };
            let pointerDownLink = { value: null };
            let pointerDownFlags = { value: null };
            const glanceActivationMethod = "\(glanceActivationMethod)";

            function post(method, params) {
                handler.postMessage({
                    context: "\(context)",
                    featureName: "linkInteraction",
                    method: method,
                    params: params || {}
                });
            }

            function findLinkTarget(start) {
                let target = start;
                while (target && target !== document) {
                    if (target.tagName === "A" && target.href) {
                        return target;
                    }
                    target = target.parentElement;
                }
                return null;
            }

            function hasSingleModifier(event) {
                let count = 0;
                if (event.metaKey) count++;
                if (event.altKey) count++;
                if (event.ctrlKey) count++;
                if (event.shiftKey) count++;
                return count === 1;
            }

            function matchesGlanceModifier(event) {
                switch (glanceActivationMethod) {
                    case "ctrl": return event.ctrlKey;
                    case "alt": return event.altKey;
                    case "shift": return event.shiftKey;
                    case "meta": return event.metaKey;
                    default: return false;
                }
            }

            function sendHover(method, href) {
                post(method, { href: href || null });
            }

            function capturePointerDown(event) {
                const target = findLinkTarget(event.target);
                if (!target || event.button !== 0 || !hasSingleModifier(event)) {
                    pointerDownLink.value = null;
                    pointerDownFlags.value = null;
                    return;
                }

                pointerDownLink.value = target.href;
                pointerDownFlags.value = {
                    altKey: !!event.altKey,
                    ctrlKey: !!event.ctrlKey,
                    shiftKey: !!event.shiftKey,
                    metaKey: !!event.metaKey
                };
            }

            document.addEventListener("keydown", function(event) {
                if (event.metaKey) {
                    isCommandPressed.value = true;
                    if (currentHoveredLink) {
                        sendHover("commandHover", currentHoveredLink);
                    }
                }
            }, true);

            document.addEventListener("keyup", function(event) {
                if (!event.metaKey) {
                    isCommandPressed.value = false;
                    sendHover("commandHover", null);
                }
            }, true);

            function updateHoveredLink(link) {
                const href = link && link.href ? link.href : null;
                if (currentHoveredLink === href) {
                    return;
                }

                currentHoveredLink = href;
                sendHover("linkHover", href);
                if (isCommandPressed.value) {
                    sendHover("commandHover", href);
                } else if (!href) {
                    sendHover("commandHover", null);
                }
            }

            document.addEventListener("mouseover", function(event) {
                updateHoveredLink(findLinkTarget(event.target));
            }, { passive: true, capture: true });

            document.addEventListener("mouseout", function(event) {
                if (!currentHoveredLink) {
                    return;
                }

                const nextTarget = findLinkTarget(event.relatedTarget);
                if (nextTarget && nextTarget.href === currentHoveredLink) {
                    return;
                }

                updateHoveredLink(null);
            }, { passive: true, capture: true });

            document.addEventListener("mousedown", capturePointerDown, true);

            document.addEventListener("click", function(event) {
                const target = findLinkTarget(event.target);
                if (!target || event.button !== 0 || event.defaultPrevented || !hasSingleModifier(event)) {
                    pointerDownLink.value = null;
                    pointerDownFlags.value = null;
                    return;
                }

                const shouldOpenInGlance = matchesGlanceModifier(event);
                const shouldOpenInNewTab = event.metaKey && glanceActivationMethod !== "meta";
                if (!shouldOpenInGlance && !shouldOpenInNewTab) {
                    return;
                }

                event.preventDefault();
                event.stopPropagation();
                if (event.stopImmediatePropagation) {
                    event.stopImmediatePropagation();
                }

                post("commandClick", {
                    href: pointerDownLink.value || target.href,
                    altKey: pointerDownFlags.value ? pointerDownFlags.value.altKey : !!event.altKey,
                    ctrlKey: pointerDownFlags.value ? pointerDownFlags.value.ctrlKey : !!event.ctrlKey,
                    shiftKey: pointerDownFlags.value ? pointerDownFlags.value.shiftKey : !!event.shiftKey,
                    metaKey: pointerDownFlags.value ? pointerDownFlags.value.metaKey : !!event.metaKey
                });
                pointerDownLink.value = null;
                pointerDownFlags.value = null;
                return false;
            }, true);
        })();
        """
    }

    @MainActor
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await broker.execute(action: action, original: message)
            return (json, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}

@MainActor
private final class SumiLinkInteractionSubfeature: NSObject, Subfeature {
    let featureName = "linkInteraction"
    let messageOriginPolicy: MessageOriginPolicy = .all
    weak var broker: UserScriptMessageBroker?
    weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
        super.init()
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case "linkHover":
            return { [weak self] params, _ in
                guard let payload = SumiHrefPayload.decode(from: params) else { return nil }
                self?.tab?.onLinkHover?(payload.href)
                return SumiJSONValue.object(["accepted": .bool(true)])
            }
        case "commandHover":
            return { [weak self] params, _ in
                guard let payload = SumiHrefPayload.decode(from: params) else { return nil }
                self?.tab?.onCommandHover?(payload.href)
                return SumiJSONValue.object(["accepted": .bool(true)])
            }
        case "commandClick":
            return { [weak self] params, _ in
                guard let payload = SumiCommandClickPayload.decode(from: params),
                      let url = URL(string: payload.href)
                else { return nil }
                self?.tab?.handleModifiedLinkClick(url: url, flags: payload.modifierFlags)
                return SumiJSONValue.object(["accepted": .bool(true)])
            }
        default:
            return nil
        }
    }

}

private struct SumiHrefPayload {
    let href: String?

    static func decode(from params: Any) -> SumiHrefPayload? {
        guard let dictionary = params as? [String: Any],
              dictionary.keys.contains("href") else { return nil }
        let value = dictionary["href"]
        if value == nil || value is NSNull {
            return SumiHrefPayload(href: nil)
        }
        guard let href = value as? String else { return nil }
        return SumiHrefPayload(href: href)
    }
}

private struct SumiCommandClickPayload {
    let href: String
    let altKey: Bool
    let ctrlKey: Bool
    let shiftKey: Bool
    let metaKey: Bool

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if altKey { flags.insert(.option) }
        if ctrlKey { flags.insert(.control) }
        if shiftKey { flags.insert(.shift) }
        if metaKey { flags.insert(.command) }
        return flags
    }

    static func decode(from params: Any) -> SumiCommandClickPayload? {
        guard let dictionary = params as? [String: Any],
              let href = dictionary["href"] as? String
        else { return nil }

        return SumiCommandClickPayload(
            href: href,
            altKey: dictionary["altKey"] as? Bool ?? false,
            ctrlKey: dictionary["ctrlKey"] as? Bool ?? false,
            shiftKey: dictionary["shiftKey"] as? Bool ?? false,
            metaKey: dictionary["metaKey"] as? Bool ?? false
        )
    }
}

@MainActor
private final class SumiTabSuspensionUserScript: NSObject, UserScript, UserScriptMessaging, WKScriptMessageHandlerWithReply {
    private let context: String
    let broker: UserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(tab: Tab) {
        self.context = "sumiTabSuspension_\(tab.id.uuidString)"
        self.broker = UserScriptMessageBroker(context: context, requiresRunInPageContentWorld: true)
        self.messageNames = [context]
        self.source = Self.makeSource(context: context)
        super.init()
        registerSubfeature(delegate: SumiTabSuspensionSubfeature(tab: tab))
    }

    private static func makeSource(context: String) -> String {
        """
        (function() {
            if (window.__sumiTabSuspensionInstalled) { return; }
            window.__sumiTabSuspensionInstalled = true;

            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers["\(context)"];
            if (!handler) { return; }

            function reportCanBeSuspended(canBeSuspended) {
                if (typeof canBeSuspended !== "boolean") { return; }
                return handler.postMessage({
                    context: "\(context)",
                    featureName: "tabSuspension",
                    method: "canBeSuspended",
                    params: { canBeSuspended: canBeSuspended }
                });
            }

            window.__sumiTabSuspension = Object.freeze({
                canBeSuspended: reportCanBeSuspended
            });
        })();
        """
    }

    @MainActor
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await broker.execute(action: action, original: message)
            return (json, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}

@MainActor
private final class SumiTabSuspensionSubfeature: NSObject, Subfeature {
    let featureName = "tabSuspension"
    let messageOriginPolicy: MessageOriginPolicy = .all
    weak var broker: UserScriptMessageBroker?
    weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
        super.init()
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard methodName == "canBeSuspended" else { return nil }
        return { [weak self] params, _ in
            guard let payload = SumiTabSuspensionPayload.decode(from: params) else {
                return nil
            }

            self?.tab?.pageSuspensionVeto = payload.canBeSuspended
                ? .none
                : .pageReportedUnableToSuspend
            return SumiJSONValue.object(["accepted": .bool(true)])
        }
    }
}

private struct SumiTabSuspensionPayload {
    let canBeSuspended: Bool

    static func decode(from params: Any) -> SumiTabSuspensionPayload? {
        guard let dictionary = params as? [String: Any],
              let canBeSuspended = dictionary["canBeSuspended"] as? Bool
        else { return nil }

        return SumiTabSuspensionPayload(canBeSuspended: canBeSuspended)
    }
}

@MainActor
private final class SumiIdentityUserScript: NSObject, UserScript, UserScriptMessaging, WKScriptMessageHandlerWithReply {
    private let context: String
    let broker: UserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(tab: Tab) {
        self.context = "sumiIdentity_\(tab.id.uuidString)"
        self.broker = UserScriptMessageBroker(context: context, requiresRunInPageContentWorld: true)
        self.messageNames = [context]
        self.source = Self.makeSource(context: context)
        super.init()
        registerSubfeature(delegate: SumiIdentitySubfeature(tab: tab))
    }

    private static func makeSource(context: String) -> String {
        """
        (function() {
            if (window.__sumiIdentityBrokerInstalled) { return; }
            window.__sumiIdentityBrokerInstalled = true;
            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers["\(context)"];
            if (!handler) { return; }

            window.__sumiRequestIdentity = function(payload) {
                payload = payload || {};
                const requestId = payload.requestId || (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()));
                return handler.postMessage({
                    context: "\(context)",
                    featureName: "identity",
                    method: "request",
                    id: requestId,
                    params: {
                        url: payload.url,
                        interactive: payload.interactive !== false,
                        requestId: requestId
                    }
                });
            };
        })();
        """
    }

    @MainActor
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await broker.execute(action: action, original: message)
            return (json, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}

@MainActor
private final class SumiIdentitySubfeature: NSObject, Subfeature {
    let featureName = "identity"
    let messageOriginPolicy: MessageOriginPolicy = .all
    weak var broker: UserScriptMessageBroker?
    weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
        super.init()
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard methodName == "request" else { return nil }
        return { [weak self] params, _ in
            guard let payload = SumiIdentityRequestPayload.decode(from: params),
                  let url = URL(string: payload.url)
            else { return nil }

            self?.tab?.handleOAuthRequest(
                url: url,
                interactive: payload.interactive,
                requestId: payload.requestId
            )
            return SumiJSONValue.object(["accepted": .bool(true)])
        }
    }
}

private struct SumiIdentityRequestPayload {
    let url: String
    let interactive: Bool
    let requestId: String

    static func decode(from params: Any) -> SumiIdentityRequestPayload? {
        guard let dictionary = params as? [String: Any],
              let url = dictionary["url"] as? String
        else {
            RuntimeDiagnostics.emit("❌ [Tab] Invalid OAuth request: missing or invalid URL")
            return nil
        }

        let rawRequestId = (dictionary["requestId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SumiIdentityRequestPayload(
            url: url,
            interactive: dictionary["interactive"] as? Bool ?? true,
            requestId: rawRequestId?.isEmpty == false ? rawRequestId! : UUID().uuidString
        )
    }
}
