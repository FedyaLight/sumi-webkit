import Foundation
import Common
import os.log
import UserScript
import WebKit

private enum SumiInstalledUserScriptFeature {
    static let gm = "gm"
}

private enum SumiInstalledUserScriptJSONValue: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SumiInstalledUserScriptJSONValue])
    case object([String: SumiInstalledUserScriptJSONValue])

    init(foundationObject value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .int(value)
        case let value as Double:
            self = Self.number(from: value)
        case let value as Float:
            self = Self.number(from: Double(value))
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = Self.number(from: value.doubleValue)
            }
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(SumiInstalledUserScriptJSONValue.init(foundationObject:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(SumiInstalledUserScriptJSONValue.init(foundationObject:)))
        default:
            self = .string(String(describing: value!))
        }
    }

    private static func number(from value: Double) -> SumiInstalledUserScriptJSONValue {
        if value.isFinite,
           value >= Double(Int.min),
           value <= Double(Int.max),
           value.rounded() == value {
            return .int(Int(value))
        }
        return .double(value)
    }

    var foundationObject: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.foundationObject)
        case .object(let values):
            return values.mapValues(\.foundationObject)
        }
    }
}

private struct SumiInstalledUserScriptMessageParams: Sendable {
    let callbackId: String
    let args: [String: SumiInstalledUserScriptJSONValue]

    init(from params: Any) {
        if let params = params as? SumiInstalledUserScriptMessageParams {
            self = params
            return
        }

        let dictionary = params as? [String: Any] ?? [:]
        self.callbackId = dictionary["callbackId"] as? String ?? ""
        let args = dictionary["args"] as? [String: Any] ?? [:]
        self.args = args.mapValues(SumiInstalledUserScriptJSONValue.init(foundationObject:))
    }

    var foundationArgs: [String: Any] {
        args.mapValues(\.foundationObject)
    }
}

private struct SumiGMMessagePayload {
    let callbackId: String
    let args: [String: Any]

    static func decode(from params: Any) -> SumiGMMessagePayload? {
        if let params = params as? SumiInstalledUserScriptMessageParams {
            return SumiGMMessagePayload(callbackId: params.callbackId, args: params.foundationArgs)
        }

        guard let dictionary = params as? [String: Any] else { return nil }
        let callbackId = dictionary["callbackId"] as? String ?? ""
        let args = dictionary["args"] as? [String: Any] ?? [:]
        return SumiGMMessagePayload(callbackId: callbackId, args: args)
    }
}

@MainActor
final class SumiInstalledUserScriptAdapter: NSObject, UserScript, @MainActor UserScriptMessaging, WKScriptMessageHandlerWithReply {
    let broker: UserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime
    let forMainFrameOnly: Bool
    let requiresRunInPageContentWorld: Bool
    let messageNames: [String]
    let bridge: UserScriptGMBridge?

    init(
        script: SumiInstalledUserScript,
        profileId: UUID?,
        isEphemeral: Bool,
        tabHandler: SumiScriptsTabHandler?,
        downloadManager: DownloadManager?,
        notificationPermissionBridge: SumiNotificationPermissionBridge?,
        notificationTabContextProvider: (@MainActor (WKWebView?) -> SumiWebNotificationTabContext?)?
    ) {
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

        self.broker = UserScriptMessageBroker(context: context)
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
            super.init()
            registerSubfeature(delegate: subfeature)
        } else {
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
            let json = try await executeInstalledUserScriptBrokerAction(action, original: message)
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
private func executeInstalledUserScriptBrokerAction(
    _ action: UserScriptMessageBroker.Action,
    original: WKScriptMessage
) async throws -> String {
    switch action {
    case .notify(let handler, let params):
        let params = SumiInstalledUserScriptMessageParams(from: params)
        do {
            _ = try await handler(params, original)
        } catch {
            Logger.general.error("UserScriptMessaging: unhandled exception \(error.localizedDescription, privacy: .public)")
        }
        return "{}"

    case .respond(let handler, let request):
        let params = SumiInstalledUserScriptMessageParams(from: request.params)
        do {
            guard let result = try await handler(params, original) else {
                return SumiInstalledUserScriptMessageErrorResponse(
                    request: request,
                    message: "could not access encodable result"
                ).toJSON()
            }

            return SumiInstalledUserScriptMessageResponse(request: request, result: result).toJSON()
                ?? SumiInstalledUserScriptMessageErrorResponse(
                    request: request,
                    message: "could not convert result to json"
                ).toJSON()
        } catch {
            return SumiInstalledUserScriptMessageErrorResponse(
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

private struct SumiInstalledUserScriptMessageResponse: Encodable {
    let request: RequestMessage
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

private struct SumiInstalledUserScriptMessageErrorResponse: Encodable {
    let context: String
    let featureName: String
    let id: String
    private let error: MessageError

    init(request: RequestMessage, message: String) {
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
private final class SumiGMSubfeature: NSObject, @MainActor Subfeature {
    let featureName = SumiInstalledUserScriptFeature.gm
    let messageOriginPolicy: MessageOriginPolicy = .all

    private let bridge: UserScriptGMBridge

    init(bridge: UserScriptGMBridge) {
        self.bridge = bridge
        super.init()
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
