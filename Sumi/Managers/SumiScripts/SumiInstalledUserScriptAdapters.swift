import Foundation
import UserScript
import WebKit

private enum SumiInstalledUserScriptFeature {
    static let gm = "gm"
}

private struct SumiGMMessagePayload {
    let callbackId: String
    let args: [String: Any]

    static func decode(from params: Any) -> SumiGMMessagePayload? {
        guard let dictionary = params as? [String: Any] else { return nil }
        let callbackId = dictionary["callbackId"] as? String ?? ""
        let args = dictionary["args"] as? [String: Any] ?? [:]
        return SumiGMMessagePayload(callbackId: callbackId, args: args)
    }
}

@MainActor
final class SumiInstalledUserScriptAdapter: NSObject, UserScript, UserScriptMessaging, WKScriptMessageHandlerWithReply {
    let script: SumiInstalledUserScript
    let broker: UserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime
    let forMainFrameOnly: Bool
    let requiresRunInPageContentWorld: Bool
    let messageNames: [String]
    let bridge: UserScriptGMBridge?

    private let gmSubfeature: SumiGMSubfeature?

    init(
        script: SumiInstalledUserScript,
        profileId: UUID?,
        isEphemeral: Bool,
        tabHandler: SumiScriptsTabHandler?,
        downloadManager: DownloadManager?,
        notificationPermissionBridge: SumiNotificationPermissionBridge?,
        notificationTabContextProvider: (@MainActor (WKWebView?) -> SumiWebNotificationTabContext?)?
    ) {
        self.script = script

        let context = "sumiGM_\(script.id.uuidString)"
        let injectInto = Self.effectiveInjectionScope(for: script)
        let requiresPageWorld = injectInto != .content
        let contentWorld: WKContentWorld = requiresPageWorld ? .page : .defaultClient
        let bridge: UserScriptGMBridge?

        if script.requiresContentWorldIsolation || !script.metadata.grants.isEmpty {
            bridge = UserScriptGMBridge(
                script: script,
                profileId: isEphemeral ? nil : profileId,
                contentWorld: contentWorld,
                tabOpenHandler: tabHandler,
                downloadManager: downloadManager,
                notificationPermissionBridge: notificationPermissionBridge,
                notificationTabContextProvider: notificationTabContextProvider
            )
        } else {
            bridge = nil
        }

        self.broker = UserScriptMessageBroker(
            context: context,
            requiresRunInPageContentWorld: requiresPageWorld
        )
        self.bridge = bridge
        self.messageNames = bridge == nil ? [] : [context]
        self.injectionTime = script.injectionTime
        self.forMainFrameOnly = script.forMainFrameOnly
        self.requiresRunInPageContentWorld = requiresPageWorld
        self.source = UserScriptInjector.userScriptMarker + "\n" + script.assembledCode(
            gmShim: bridge?.generateJSShim() ?? ""
        )

        if let bridge {
            let subfeature = SumiGMSubfeature(bridge: bridge)
            self.gmSubfeature = subfeature
            super.init()
            registerSubfeature(delegate: subfeature)
        } else {
            self.gmSubfeature = nil
            super.init()
        }
    }

    private static func effectiveInjectionScope(for script: SumiInstalledUserScript) -> UserScriptInjectInto {
        var scope = script.metadata.injectInto

        if scope == .auto && script.requiresContentWorldIsolation {
            scope = .content
        }

        if scope == .page && script.requiresContentWorldIsolation {
            RuntimeDiagnostics.debug(
                "Warning: '\(script.name)' has @grant values but @inject-into page; GM APIs will not work",
                category: "SumiScripts"
            )
        }

        return scope
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
final class SumiInstalledUserStyleAdapter: NSObject, UserScript {
    let source: String
    let injectionTime: WKUserScriptInjectionTime
    let forMainFrameOnly: Bool
    let requiresRunInPageContentWorld = true
    let messageNames: [String] = []

    init(script: SumiInstalledUserScript) {
        let escapedCSS = script.code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        self.source = """
        \(UserScriptInjector.userScriptMarker)
        (function() {
            var tag = document.createElement('style');
            tag.textContent = `\(escapedCSS)`;
            tag.setAttribute('data-sumi-userscript', '\(script.filename)');
            (document.head || document.documentElement).appendChild(tag);
        })();
        """
        self.injectionTime = script.injectionTime
        self.forMainFrameOnly = script.forMainFrameOnly
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}

@MainActor
private final class SumiGMSubfeature: NSObject, Subfeature {
    let featureName = SumiInstalledUserScriptFeature.gm
    let messageOriginPolicy: MessageOriginPolicy = .all
    weak var broker: UserScriptMessageBroker?

    private let bridge: UserScriptGMBridge

    init(bridge: UserScriptGMBridge) {
        self.bridge = bridge
        super.init()
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case "GM.getValue", "GM.getValues", "GM.setValue", "GM.setValues",
             "GM.deleteValue", "GM.deleteValues", "GM.listValues",
             "GM.getTab", "GM.saveTab", "GM.getResourceText", "GM.getResourceUrl",
             "GM_addStyle", "GM.setClipboard", "window.close", "window.focus",
             "GM_openInTab", "GM_notification", "GM_registerMenuCommand",
             "GM_unregisterMenuCommand", "GM_xmlhttpRequest",
             "GM_xmlhttpRequest_abort", "GM_download", "__sumi_runtimeError":
            return { [weak self] params, original in
                try await self?.handle(method: methodName, params: params, original: original)
            }
        default:
            return nil
        }
    }

    private func handle(method: String, params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let payload = SumiGMMessagePayload.decode(from: params) else {
            throw SumiGMSubfeatureError.malformedPayload
        }

        if method == "__sumi_runtimeError" {
            NotificationCenter.default.post(
                name: .sumiUserScriptRuntimeError,
                object: bridge,
                userInfo: [
                    "scriptId": bridge.script.id.uuidString,
                    "scriptFilename": bridge.script.filename,
                    "kind": payload.args["kind"] as? String ?? "error",
                    "message": payload.args["message"] as? String ?? "",
                    "location": payload.args["location"] as? String ?? "",
                    "stack": payload.args["stack"] as? String ?? ""
                ]
            )
            return SumiJSONValue.object(["accepted": .bool(true)])
        }

        UserScriptGMDispatch.route(
            bridge: bridge,
            method: method,
            args: payload.args,
            callbackId: payload.callbackId,
            webView: original.webView,
            original: original
        )
        return SumiJSONValue.object(["accepted": .bool(true)])
    }
}

private enum SumiGMSubfeatureError: LocalizedError {
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .malformedPayload:
            return "Malformed Sumi GM payload"
        }
    }
}
