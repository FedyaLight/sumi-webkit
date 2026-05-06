import AppKit
import Common
import Foundation
import Navigation
import os.log
import WebKit

extension Tab {
    func normalTabCoreUserScripts() -> [SumiUserScript] {
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

        let activeFlags = (flags ?? clickModifierFlags)
            .intersection([.command, .option, .control, .shift])
        return activeFlags == [.option]
    }

    func openURLInGlance(_ url: URL) {
        browserManager?.glanceManager.presentExternalURL(url, from: self)
    }

    func navigationModifierFlags(from navigationAction: WKNavigationAction) -> NSEvent.ModifierFlags {
        let flags = navigationAction.modifierFlags.intersection([.command, .option, .control, .shift])
        return resolvedNavigationModifierFlags(actionFlags: flags)
    }

    func navigationModifierFlags(from navigationAction: NavigationAction) -> NSEvent.ModifierFlags {
        let flags = navigationAction.modifierFlags.intersection([.command, .option, .control, .shift])
        return resolvedNavigationModifierFlags(actionFlags: flags)
    }

    /// Resolves which modifier keys apply to a link or popup navigation when WebKit reports empty or misleading flags,
    /// using (in order) a fresh main-window mouseDown snapshot, WebKit-provided flags, the last interaction event, then tab click state.
    func resolvedNavigationModifierFlags(actionFlags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        if let interactionFlags = recentWebViewMouseDownModifierFlags() {
            return interactionFlags
        }
        if !actionFlags.isEmpty {
            return actionFlags
        }
        if let interactionFlags = recentWebViewInteractionModifierFlags() {
            return interactionFlags
        }
        return clickModifierFlags
    }

    func shouldOpenDynamicallyInGlance(
        url: URL,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard sumiSettings?.glanceEnabled ?? true else { return false }
        guard modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
            return false
        }

        guard let currentHost = self.url.host,
              let newHost = url.host else { return false }

        return currentHost != newHost
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

}

/// Reports hovered `<a href>` for chrome (e.g. link status). Injected in the main frame only to limit work in subframes;
/// links inside iframes will not drive the status line until hovered in the top document.
@MainActor
private final class SumiLinkInteractionUserScript: NSObject, SumiUserScript, @MainActor SumiUserScriptMessaging, WKScriptMessageHandlerWithReply {
    private let context: String
    let broker: SumiUserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(tab: Tab) {
        self.context = "sumiLinkInteraction_\(tab.id.uuidString)"
        self.broker = SumiUserScriptMessageBroker(context: context)
        self.messageNames = [context]
        self.source = Self.makeSource(context: context)
        super.init()
        registerSubfeature(delegate: SumiLinkInteractionSubfeature(tab: tab))
    }

    private static func makeSource(context: String) -> String {
        """
        (function() {
            if (window.__sumiLinkInteractionInstalled) { return; }
            window.__sumiLinkInteractionInstalled = true;

            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers["\(context)"];
            if (!handler) { return; }

            let currentHoveredLink = null;

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
                    if (t.nodeType === 1 && t.tagName === "A" && t.href) {
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
                if (currentHoveredLink === href) {
                    return;
                }

                currentHoveredLink = href;
                sendHover("linkHover", href);
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
            let json = try await executeTabScriptBrokerAction(action, original: message)
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
private final class SumiLinkInteractionSubfeature: NSObject, @MainActor SumiUserScriptSubfeature {
    let featureName = "linkInteraction"
    let messageOriginPolicy: SumiUserScriptMessageOriginPolicy = .all
    weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
        super.init()
    }

    func handler(forMethodNamed methodName: String) -> SumiUserScriptSubfeature.Handler? {
        switch methodName {
        case "linkHover":
            return { [weak self] params, _ in
                guard let payload = SumiHrefPayload.decode(from: params) else { return nil }
                self?.tab?.onLinkHover?(payload.href)
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
        if let params = params as? SumiTabScriptMessageParams {
            guard params.hasHref else { return nil }
            return SumiHrefPayload(href: params.href)
        }

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

@MainActor
private final class SumiTabSuspensionUserScript: NSObject, SumiUserScript, @MainActor SumiUserScriptMessaging, WKScriptMessageHandlerWithReply {
    private let context: String
    let broker: SumiUserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(tab: Tab) {
        self.context = "sumiTabSuspension_\(tab.id.uuidString)"
        self.broker = SumiUserScriptMessageBroker(context: context)
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
            let json = try await executeTabScriptBrokerAction(action, original: message)
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
private final class SumiTabSuspensionSubfeature: NSObject, @MainActor SumiUserScriptSubfeature {
    let featureName = "tabSuspension"
    let messageOriginPolicy: SumiUserScriptMessageOriginPolicy = .all
    weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
        super.init()
    }

    func handler(forMethodNamed methodName: String) -> SumiUserScriptSubfeature.Handler? {
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
        if let params = params as? SumiTabScriptMessageParams,
           let canBeSuspended = params.canBeSuspended {
            return SumiTabSuspensionPayload(canBeSuspended: canBeSuspended)
        }

        guard let dictionary = params as? [String: Any],
              let canBeSuspended = dictionary["canBeSuspended"] as? Bool
        else { return nil }

        return SumiTabSuspensionPayload(canBeSuspended: canBeSuspended)
    }
}

@MainActor
private final class SumiIdentityUserScript: NSObject, SumiUserScript, @MainActor SumiUserScriptMessaging, WKScriptMessageHandlerWithReply {
    private let context: String
    let broker: SumiUserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(tab: Tab) {
        self.context = "sumiIdentity_\(tab.id.uuidString)"
        self.broker = SumiUserScriptMessageBroker(context: context)
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
            let json = try await executeTabScriptBrokerAction(action, original: message)
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
private func executeTabScriptBrokerAction(
    _ action: SumiUserScriptMessageBroker.Action,
    original: WKScriptMessage
) async throws -> String {
    switch action {
    case .notify(let handler, let params):
        let params = SumiTabScriptMessageParams(from: params)
        do {
            _ = try await handler(params, original)
        } catch {
            Logger.general.error("UserScriptMessaging: unhandled exception \(error.localizedDescription, privacy: .public)")
        }
        return "{}"

    case .respond(let handler, let request):
        let params = SumiTabScriptMessageParams(from: request.params)
        do {
            guard let result = try await handler(params, original) else {
                return SumiTabScriptMessageErrorResponse(
                    request: request,
                    message: "could not access encodable result"
                ).toJSON()
            }

            return SumiTabScriptMessageResponse(request: request, result: result).toJSON()
                ?? SumiTabScriptMessageErrorResponse(
                    request: request,
                    message: "could not convert result to json"
                ).toJSON()
        } catch {
            return SumiTabScriptMessageErrorResponse(
                request: request,
                message: error.localizedDescription
            ).toJSON()
        }

    case .error(let error):
        throw NSError(
            domain: "UserScriptMessaging",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }
}

private struct SumiTabScriptMessageParams: Sendable {
    let href: String?
    let hasHref: Bool
    let canBeSuspended: Bool?
    let url: String?
    let interactive: Bool?
    let requestId: String?

    init(from params: Any) {
        if let params = params as? SumiTabScriptMessageParams {
            self = params
            return
        }

        let dictionary = params as? [String: Any] ?? [:]
        let hrefValue = dictionary["href"]

        self.href = hrefValue as? String
        self.hasHref = dictionary.keys.contains("href")
        self.canBeSuspended = dictionary["canBeSuspended"] as? Bool
        self.url = dictionary["url"] as? String
        self.interactive = dictionary["interactive"] as? Bool
        self.requestId = dictionary["requestId"] as? String
    }
}

private struct SumiTabScriptMessageResponse: Encodable {
    let request: SumiUserScriptRequestMessage
    let result: Encodable

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request.context, forKey: .context)
        try container.encode(request.featureName, forKey: .featureName)
        try container.encode(request.id, forKey: .id)
        try result.encode(to: container.superEncoder(forKey: .result))
    }

    func toJSON() -> String? {
        guard let jsonData = try? JSONEncoder().encode(self) else { return nil }
        return String(data: jsonData, encoding: .utf8)
    }

    private enum CodingKeys: String, CodingKey {
        case context
        case featureName
        case id
        case result
    }
}

private struct SumiTabScriptMessageErrorResponse: Encodable {
    let context: String
    let featureName: String
    let id: String
    private let error: MessageError

    init(request: SumiUserScriptRequestMessage, message: String) {
        self.context = request.context
        self.featureName = request.featureName
        self.id = request.id
        self.error = MessageError(message: message)
    }

    func toJSON() -> String {
        guard let jsonData = try? JSONEncoder().encode(self),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return #"{"error":{"message":"could not convert result to json"}}"#
        }
        return jsonString
    }

    private struct MessageError: Encodable {
        let message: String
    }
}

@MainActor
private final class SumiIdentitySubfeature: NSObject, @MainActor SumiUserScriptSubfeature {
    let featureName = "identity"
    let messageOriginPolicy: SumiUserScriptMessageOriginPolicy = .all
    weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
        super.init()
    }

    func handler(forMethodNamed methodName: String) -> SumiUserScriptSubfeature.Handler? {
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
        if let params = params as? SumiTabScriptMessageParams {
            guard let url = params.url else {
                RuntimeDiagnostics.emit("❌ [Tab] Invalid OAuth request: missing or invalid URL")
                return nil
            }

            let rawRequestId = params.requestId?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SumiIdentityRequestPayload(
                url: url,
                interactive: params.interactive ?? true,
                requestId: rawRequestId?.isEmpty == false ? rawRequestId! : UUID().uuidString
            )
        }

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
