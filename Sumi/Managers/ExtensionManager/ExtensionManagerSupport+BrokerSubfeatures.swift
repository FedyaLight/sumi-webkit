//
//  ExtensionManagerSupport+BrokerSubfeatures.swift
//  Sumi
//
//  Subfeature adapters that route SumiExtensionMessageBroker messages
//  to the existing ExtensionManager handlers for externally_connectable.
//

import Foundation
import WebKit

// MARK: - Page-world subfeature (sendMessage + connect from web pages)

@available(macOS 15.5, *)
@MainActor
final class ExternallyConnectablePageSubfeature: SumiExtensionSubfeature {
    let featureName = "runtime"
    let messageOriginPolicy: SumiExtensionMessageOriginPolicy = .all

    weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func handler(forMethodNamed method: String) -> Handler? {
        switch method {
        case "runtime.sendMessage", "sendMessage":
            return { [weak self] params, message, replyHandler in
                self?.manager?.handleExternallyConnectableNativeMessage(
                    message.rawMessage,
                    replyHandler: replyHandler
                )
            }
        case "runtime.connect.open", "runtime.connect.postMessage",
             "runtime.connect.disconnect":
            return { [weak self] params, message, replyHandler in
                self?.manager?.handleExternallyConnectableNativeMessage(
                    message.rawMessage,
                    replyHandler: replyHandler
                )
            }
        default:
            return nil
        }
    }
}

// MARK: - Isolated-world subfeature (connect adapter events from content scripts)

@available(macOS 15.5, *)
@MainActor
final class ExternallyConnectableIsolatedSubfeature: SumiExtensionSubfeature {
    let featureName = "runtime.connect.event"
    let messageOriginPolicy: SumiExtensionMessageOriginPolicy = .all

    weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func handler(forMethodNamed method: String) -> Handler? {
        switch method {
        case "runtime.connect.event.message", "runtime.connect.event.disconnect":
            return { [weak self] params, message, replyHandler in
                self?.manager?.handleExternallyConnectableNativeMessage(
                    message.rawMessage,
                    replyHandler: replyHandler
                )
            }
        default:
            return nil
        }
    }
}
