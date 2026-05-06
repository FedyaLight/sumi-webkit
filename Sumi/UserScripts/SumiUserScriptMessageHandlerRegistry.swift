import Foundation
import WebKit

@MainActor
final class SumiUserScriptMessageHandlerRegistry {
    private struct HandlerRegistration {
        let name: String
        let contentWorld: WKContentWorld
    }

    private final class WeakScriptMessageHandlerBox {
        weak var handler: WKScriptMessageHandler?

        init(handler: WKScriptMessageHandler) {
            self.handler = handler
        }
    }

    private final class PermanentScriptMessageHandler: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
        private var registeredMessageHandlers = [String: WeakScriptMessageHandlerBox]()

        func clear() {
            registeredMessageHandlers.removeAll()
        }

        func isMessageHandlerRegistered(for messageName: String) -> Bool {
            registeredMessageHandlers[messageName] != nil
        }

        func messageHandler(for messageName: String) -> WKScriptMessageHandler? {
            registeredMessageHandlers[messageName]?.handler
        }

        func register(_ handler: WKScriptMessageHandler, for messageName: String) {
            registeredMessageHandlers[messageName] = WeakScriptMessageHandlerBox(handler: handler)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let box = registeredMessageHandlers[message.name],
                  let handler = box.handler
            else {
                return
            }

            handler.userContentController(userContentController, didReceive: message)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) async -> (Any?, String?) {
            guard let box = registeredMessageHandlers[message.name],
                  let handler = box.handler
            else {
                return (nil, "Script message handler is unavailable.")
            }

            guard let replyHandlerTarget = handler as? WKScriptMessageHandlerWithReply else {
                return (nil, "Script message handler does not support replies.")
            }

            return await replyHandlerTarget.userContentController(userContentController, didReceive: message)
        }
    }

    private weak var userContentController: WKUserContentController?
    private let scriptMessageHandler = PermanentScriptMessageHandler()
    private var installedUserScripts = [WKUserScript]()
    private var handlerRegistrations = [HandlerRegistration]()
    private var isCleanedUp = false

    init(userContentController: WKUserContentController) {
        self.userContentController = userContentController
    }

    func replaceUserScripts(with provider: SumiNormalTabUserScripts) async {
        guard !isCleanedUp,
              let userContentController,
              canRemoveInstalledUserScripts(from: userContentController)
        else { return }

        let wkUserScripts = await provider.loadWKUserScripts()
        removeInstalledUserScripts(from: userContentController)
        removeInstalledScriptMessageHandlers(from: userContentController)
        installUserScripts(wkUserScripts, handlers: provider.userScripts, on: userContentController)
    }

    func cleanUpBeforeClosing() {
        guard let userContentController else {
            isCleanedUp = true
            return
        }

        if canRemoveInstalledUserScripts(from: userContentController) {
            removeInstalledUserScripts(from: userContentController)
        }
        removeInstalledScriptMessageHandlers(from: userContentController)
        isCleanedUp = true
    }

    private func installUserScripts(
        _ wkUserScripts: [WKUserScript],
        handlers: [SumiUserScript],
        on userContentController: WKUserContentController
    ) {
        handlers.forEach { addHandler($0, to: userContentController) }
        wkUserScripts.forEach(userContentController.addUserScript)
        installedUserScripts.append(contentsOf: wkUserScripts)
    }

    private func addHandler(
        _ userScript: SumiUserScript,
        to userContentController: WKUserContentController
    ) {
        for messageName in userScript.messageNames {
            assert(
                scriptMessageHandler.messageHandler(for: messageName) == nil
                    || type(of: scriptMessageHandler.messageHandler(for: messageName)!) == type(of: userScript),
                "\(scriptMessageHandler.messageHandler(for: messageName)!) already registered for message \(messageName)"
            )

            defer {
                scriptMessageHandler.register(userScript, for: messageName)
            }
            guard !scriptMessageHandler.isMessageHandlerRegistered(for: messageName) else { continue }

            let contentWorld = userScript.getContentWorld()
            if userScript is WKScriptMessageHandlerWithReply {
                userContentController.addScriptMessageHandler(
                    scriptMessageHandler,
                    contentWorld: contentWorld,
                    name: messageName
                )
            } else {
                userContentController.add(
                    scriptMessageHandler,
                    contentWorld: contentWorld,
                    name: messageName
                )
            }
            handlerRegistrations.append(HandlerRegistration(name: messageName, contentWorld: contentWorld))
        }
    }

    private func removeInstalledScriptMessageHandlers(from userContentController: WKUserContentController) {
        for registration in handlerRegistrations {
            userContentController.removeScriptMessageHandler(
                forName: registration.name,
                contentWorld: registration.contentWorld
            )
        }
        handlerRegistrations.removeAll(keepingCapacity: true)
        scriptMessageHandler.clear()
    }

    private func canRemoveInstalledUserScripts(from userContentController: WKUserContentController) -> Bool {
        guard !installedUserScripts.isEmpty else { return true }
#if os(macOS)
        let supported = userContentController.responds(to: Self.removeUserScriptSelector)
        assertionFailureIfNeeded(
            !supported,
            "WKUserContentController precise user-script removal is unavailable."
        )
        return supported
#else
        assertionFailure("Sumi normal-tab user-script replacement requires precise user-script removal.")
        return false
#endif
    }

    private func removeInstalledUserScripts(from userContentController: WKUserContentController) {
        guard !installedUserScripts.isEmpty else { return }
#if os(macOS)
        for installedUserScript in installedUserScripts {
            userContentController.perform(Self.removeUserScriptSelector, with: installedUserScript)
        }
        installedUserScripts.removeAll(keepingCapacity: true)
#endif
    }

    private func assertionFailureIfNeeded(_ condition: Bool, _ message: String) {
        if condition {
            assertionFailure(message)
        }
    }

#if os(macOS)
    // WebKit exposes no public per-script removal API. Keep the private selector
    // confined to this registry so replacement never removes unrelated scripts.
    private static let removeUserScriptSelector = NSSelectorFromString("_removeUserScript:")
#endif
}
