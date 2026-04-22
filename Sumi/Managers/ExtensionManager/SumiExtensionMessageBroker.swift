//
//  SumiExtensionMessageBroker.swift
//  Sumi
//
//  DDG-style structured message broker for extension bridge scripts.
//  Routes incoming WKScriptMessage payloads by { featureName, method }
//  to registered SumiExtensionSubfeature handlers. Replaces the ad-hoc
//  kind-based switch/case in handleExternallyConnectableNativeMessage.
//

import Foundation
import ObjectiveC.runtime
import WebKit

// MARK: - Message origin policy

@available(macOS 15.5, *)
enum SumiExtensionMessageOriginPolicy {
    case all
    case only(allowedOrigins: Set<String>)
}

// MARK: - Parsed message

@available(macOS 15.5, *)
struct SumiExtensionBridgeMessage {
    let rawMessage: WKScriptMessage
}

// MARK: - Subfeature protocol

@available(macOS 15.5, *)
@MainActor
protocol SumiExtensionSubfeature: AnyObject {
    var featureName: String { get }
    var messageOriginPolicy: SumiExtensionMessageOriginPolicy { get }

    typealias Handler = (
        _ message: SumiExtensionBridgeMessage,
        _ replyHandler: @escaping (Any?, String?) -> Void
    ) -> Void

    func handler(forMethodNamed method: String) -> Handler?
}

// MARK: - Broker action

@available(macOS 15.5, *)
private enum BrokerAction {
    case respond(handler: SumiExtensionSubfeature.Handler, message: SumiExtensionBridgeMessage)
    case notify(handler: SumiExtensionSubfeature.Handler, message: SumiExtensionBridgeMessage)
    case error(String)
}

// MARK: - Broker

@available(macOS 15.5, *)
@MainActor
final class SumiExtensionMessageBroker: NSObject, WKScriptMessageHandlerWithReply {
    private static var associationKey: UInt8 = 0

    let context: String
    private var subfeatures: [String: SumiExtensionSubfeature] = [:]

    init(context: String) {
        self.context = context
        super.init()
    }

    func registerSubfeature(_ subfeature: SumiExtensionSubfeature) {
        subfeatures[subfeature.featureName] = subfeature
    }

    // MARK: - Install into WKUserContentController

    static func installIfNeeded(
        _ broker: SumiExtensionMessageBroker,
        into controller: WKUserContentController
    ) {
        let worlds: [WKContentWorld] = [.page, .defaultClient]
        if let existing = objc_getAssociatedObject(controller, &associationKey)
            as? SumiExtensionMessageBroker
        {
            existing.subfeatures = broker.subfeatures
            return
        }

        for world in worlds {
            controller.addScriptMessageHandler(
                broker,
                contentWorld: world,
                name: broker.context
            )
        }
        objc_setAssociatedObject(
            controller,
            &associationKey,
            broker,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func removeIfInstalled(
        from controller: WKUserContentController,
        context: String
    ) {
        let worlds: [WKContentWorld] = [.page, .defaultClient]
        for world in worlds {
            controller.removeScriptMessageHandler(
                forName: context,
                contentWorld: world
            )
        }
        objc_setAssociatedObject(
            controller,
            &associationKey,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    // MARK: - WKScriptMessageHandlerWithReply

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        let action = resolveAction(for: message)
        switch action {
        case .respond(let handler, let bridgeMessage):
            handler(bridgeMessage, replyHandler)
        case .notify(let handler, let bridgeMessage):
            handler(bridgeMessage) { _, _ in }
            replyHandler(nil, nil)
        case .error(let errorMessage):
            replyHandler(nil, errorMessage)
        }
    }

    // MARK: - Routing

    private func resolveAction(for message: WKScriptMessage) -> BrokerAction {
        guard message.name == context else {
            return .error("Unknown handler: \(message.name)")
        }

        guard let body = message.body as? [String: Any] else {
            return .error("Invalid message payload")
        }

        guard let featureName = body["featureName"] as? String else {
            return .error("Missing featureName in message")
        }

        let method = body["method"] as? String ?? featureName
        let id = body["id"] as? String

        guard let subfeature = subfeatures[featureName] else {
            return .error("No handler for feature: \(featureName)")
        }

        if !validateOrigin(message: message, policy: subfeature.messageOriginPolicy) {
            return .error("Message origin rejected by policy")
        }

        guard let handler = subfeature.handler(forMethodNamed: method) else {
            return .error("No handler for method: \(featureName).\(method)")
        }

        let bridgeMessage = SumiExtensionBridgeMessage(rawMessage: message)

        if id != nil {
            return .respond(handler: handler, message: bridgeMessage)
        }
        return .notify(handler: handler, message: bridgeMessage)
    }

    private func validateOrigin(
        message: WKScriptMessage,
        policy: SumiExtensionMessageOriginPolicy
    ) -> Bool {
        switch policy {
        case .all:
            return true
        case .only(let allowedOrigins):
            guard let url = message.frameInfo.request.url,
                  let scheme = url.scheme,
                  let host = url.host
            else {
                return false
            }
            let origin = url.port.map { "\(scheme)://\(host):\($0)" }
                ?? "\(scheme)://\(host)"
            return allowedOrigins.contains(origin)
        }
    }
}
