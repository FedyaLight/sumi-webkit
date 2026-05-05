import Foundation
import UserScript
import WebKit

@available(macOS 15.5, *)
@MainActor
final class SumiExternallyConnectableUserScript: NSObject, UserScript, @MainActor UserScriptMessaging, WKScriptMessageHandlerWithReply {
    let broker: UserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = false
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(manager: ExtensionManager, policies: [ExternallyConnectablePolicy]) {
        let context = ExtensionManager.externallyConnectableNativeBridgeHandlerName
        self.broker = UserScriptMessageBroker(context: context)
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
