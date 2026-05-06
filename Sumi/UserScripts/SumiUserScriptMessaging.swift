import Foundation
import os.log
import WebKit

struct SumiUserScriptRequestMessage {
    let context: String
    let featureName: String
    let id: String
    let params: Any
}

protocol SumiUserScriptSubfeature {
    typealias Handler = (_ params: Any, _ original: WKScriptMessage) async throws -> Encodable?

    var featureName: String { get }
    var messageOriginPolicy: SumiUserScriptMessageOriginPolicy { get }

    func handler(forMethodNamed methodName: String) -> Handler?
    func with(broker: SumiUserScriptMessageBroker)
}

extension SumiUserScriptSubfeature {
    func with(broker: SumiUserScriptMessageBroker) {
        _ = broker
    }
}

protocol SumiUserScriptMessaging: SumiUserScript {
    var broker: SumiUserScriptMessageBroker { get }
}

extension SumiUserScriptMessaging {
    func registerSubfeature(delegate: SumiUserScriptSubfeature) {
        delegate.with(broker: broker)
        broker.registerSubfeature(delegate: delegate)
    }
}

final class SumiUserScriptMessageBroker: NSObject {
    enum Action {
        case respond(handler: SumiUserScriptSubfeature.Handler, request: SumiUserScriptRequestMessage)
        case notify(handler: SumiUserScriptSubfeature.Handler, params: Any)
        case error(SumiUserScriptBrokerError)
    }

    private var callbacks: [String: SumiUserScriptSubfeature] = [:]

    init(context: String) {
        _ = context
        super.init()
    }

    func registerSubfeature(delegate: SumiUserScriptSubfeature) {
        callbacks[delegate.featureName] = delegate
    }

    @MainActor
    func messageHandlerFor(_ message: WKScriptMessage) -> Action {
        guard let dict = message.body as? [String: Any],
              let featureName = dict["featureName"] as? String,
              let context = dict["context"] as? String,
              let method = dict["method"] as? String
        else {
            return .error(.invalidParams)
        }

        guard let delegate = callbacks[featureName] else {
            return .error(.notFoundFeature(featureName))
        }

        let messageHost = message.frameInfo.securityOrigin.host
        guard delegate.messageOriginPolicy.isAllowed(messageHost) else {
            return .error(.policyRestriction)
        }

        guard let handler = delegate.handler(forMethodNamed: method) else {
            return .error(.notFoundHandler(feature: featureName, method: method))
        }

        let methodParams = dict["params"] ?? [String: Any]()
        if let id = dict["id"] as? String {
            return .respond(
                handler: handler,
                request: SumiUserScriptRequestMessage(
                    context: context,
                    featureName: featureName,
                    id: id,
                    params: methodParams
                )
            )
        }

        return .notify(handler: handler, params: methodParams)
    }
}

enum SumiUserScriptBrokerError: Error {
    case invalidParams
    case notFoundFeature(String)
    case notFoundHandler(feature: String, method: String)
    case policyRestriction
}

extension SumiUserScriptBrokerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidParams:
            return "The incoming message was not valid - one or more of 'featureName', 'method'  or 'context' was missing"
        case .notFoundFeature(let feature):
            return "feature named `\(feature)` was not found"
        case .notFoundHandler(let feature, let method):
            return "the incoming message is ignored because the feature `\(feature)` couldn't provide a handler for method `\(method)`"
        case .policyRestriction:
            return "invalid origin"
        }
    }
}

enum SumiUserScriptHostnameMatchingRule {
    case exact(hostname: String)
    case exactOrSubdomain(hostname: String)
}

enum SumiUserScriptMessageOriginPolicy {
    case all
    case only(rules: [SumiUserScriptHostnameMatchingRule])

    func isAllowed(_ origin: String) -> Bool {
        switch self {
        case .all:
            return true
        case .only(let rules):
            return rules.contains { rule in
                switch rule {
                case .exact(let hostname):
                    return hostname == origin
                case .exactOrSubdomain(let hostname):
                    return origin == hostname || origin.hasSuffix(".\(hostname)")
                }
            }
        }
    }
}
