import Foundation
import os.log
import WebKit

@available(macOS 15.5, *)
@MainActor
final class SumiExternallyConnectableUserScript: NSObject, SumiUserScript, @MainActor SumiUserScriptMessaging, WKScriptMessageHandlerWithReply {
    let broker: SumiUserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = false
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(manager: ExtensionManager, policies: [ExternallyConnectablePolicy]) {
        let context = ExtensionManager.externallyConnectableNativeBridgeHandlerName
        self.broker = SumiUserScriptMessageBroker(context: context)
        self.messageNames = [context]
        self.source = policies
            .sorted { $0.extensionId < $1.extensionId }
            .map { policy in
                let marker = manager.pageBridgeMarker(for: policy.extensionId)
                return ExtensionManager.pageWorldExternallyConnectableBridgeScript(
                    configJSON: ExtensionManager.pageWorldExternallyConnectableBridgeConfigJSON(
                        policy: policy,
                        bridgeMarker: marker
                    ),
                    bridgeMarker: marker
                )
            }
            .joined(separator: "\n")
        super.init()
        registerSubfeature(delegate: ExternallyConnectablePageSubfeature(manager: manager))
    }

    @MainActor
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await executeExternallyConnectableBrokerAction(action, original: message)
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

@available(macOS 15.5, *)
private struct SumiExternallyConnectableMessageParams: Sendable {
    private let value: SumiExternallyConnectableJSONValue

    init(from params: Any) {
        if let params = params as? SumiExternallyConnectableMessageParams {
            self = params
            return
        }

        self.value = SumiExternallyConnectableJSONValue(foundationObject: params)
    }

}

@available(macOS 15.5, *)
private enum SumiExternallyConnectableJSONValue: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SumiExternallyConnectableJSONValue])
    case object([String: SumiExternallyConnectableJSONValue])

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
            self = .array(value.map(SumiExternallyConnectableJSONValue.init(foundationObject:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(SumiExternallyConnectableJSONValue.init(foundationObject:)))
        default:
            self = .string(String(describing: value!))
        }
    }

    private static func number(from value: Double) -> SumiExternallyConnectableJSONValue {
        if value.isFinite,
           value >= Double(Int.min),
           value <= Double(Int.max),
           value.rounded() == value {
            return .int(Int(value))
        }
        return .double(value)
    }

}

@available(macOS 15.5, *)
@MainActor
private func executeExternallyConnectableBrokerAction(
    _ action: SumiUserScriptMessageBroker.Action,
    original: WKScriptMessage
) async throws -> String {
    switch action {
    case .notify(let handler, let params):
        let params = SumiExternallyConnectableMessageParams(from: params)
        do {
            _ = try await handler(params, original)
        } catch {
            Logger.sumiGeneral.error("UserScriptMessaging: unhandled exception \(error.localizedDescription, privacy: .public)")
        }
        return "{}"

    case .respond(let handler, let request):
        let params = SumiExternallyConnectableMessageParams(from: request.params)
        do {
            guard let result = try await handler(params, original) else {
                return SumiExternallyConnectableMessageErrorResponse(
                    request: request,
                    message: "could not access encodable result"
                ).toJSON()
            }

            return SumiExternallyConnectableMessageResponse(request: request, result: result).toJSON()
                ?? SumiExternallyConnectableMessageErrorResponse(
                    request: request,
                    message: "could not convert result to json"
                ).toJSON()
        } catch {
            return SumiExternallyConnectableMessageErrorResponse(
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

@available(macOS 15.5, *)
private struct SumiExternallyConnectableMessageResponse: Encodable {
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

@available(macOS 15.5, *)
private struct SumiExternallyConnectableMessageErrorResponse: Encodable {
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
