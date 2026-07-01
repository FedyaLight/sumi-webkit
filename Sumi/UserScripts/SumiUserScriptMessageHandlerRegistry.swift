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
    private weak var installedProvider: SumiNormalTabUserScripts?
    private var installedProviderRevision: Int?
    private var handlerRegistrations = [HandlerRegistration]()
    private var isCleanedUp = false

    init(userContentController: WKUserContentController) {
        self.userContentController = userContentController
    }

    func replaceUserScripts(with provider: SumiNormalTabUserScripts) async {
        guard !isCleanedUp,
              let userContentController
        else { return }
        guard !hasInstalledUserScripts(for: provider) else { return }

        let wkUserScripts = await provider.loadWKUserScripts()
        guard removeInstalledUserScripts(from: userContentController) else { return }
        removeInstalledScriptMessageHandlers(from: userContentController)
        installUserScripts(
            wkUserScripts,
            handlers: provider.userScripts,
            provider: provider,
            on: userContentController
        )
    }

    func installInitialUserScripts(with provider: SumiNormalTabUserScripts) {
        guard !isCleanedUp,
              let userContentController
        else { return }
        guard !hasInstalledUserScripts(for: provider) else { return }

        let wkUserScripts = provider.userScripts.map {
            SumiUserScriptBuilder.makeWKUserScript(from: $0)
        }
        guard removeInstalledUserScripts(from: userContentController) else { return }
        removeInstalledScriptMessageHandlers(from: userContentController)
        installUserScripts(
            wkUserScripts,
            handlers: provider.userScripts,
            provider: provider,
            on: userContentController
        )
    }

    func hasInstalledUserScripts(for provider: SumiNormalTabUserScripts) -> Bool {
        installedProvider === provider
            && installedProviderRevision == provider.scriptsRevision
            && installedUserScripts.count == provider.userScripts.count
    }

    func cleanUpBeforeClosing() {
        guard let userContentController else {
            isCleanedUp = true
            return
        }

        _ = removeInstalledUserScripts(from: userContentController)
        removeInstalledScriptMessageHandlers(from: userContentController)
        installedProvider = nil
        installedProviderRevision = nil
        isCleanedUp = true
    }

    private func installUserScripts(
        _ wkUserScripts: [WKUserScript],
        handlers: [SumiUserScript],
        provider: SumiNormalTabUserScripts,
        on userContentController: WKUserContentController
    ) {
        handlers.forEach { addHandler($0, to: userContentController) }
        wkUserScripts.forEach(userContentController.addUserScript)
        installedUserScripts.append(contentsOf: wkUserScripts)
        installedProvider = provider
        installedProviderRevision = provider.scriptsRevision
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
        installedProvider = nil
        installedProviderRevision = nil
    }

    @discardableResult
    private func removeInstalledUserScripts(from userContentController: WKUserContentController) -> Bool {
        guard !installedUserScripts.isEmpty else { return true }
#if os(macOS)
        guard userContentController.responds(to: Self.removeUserScriptSelector) else {
            RuntimeDiagnostics.debug(
                "WKUserContentController precise user-script removal is unavailable; normal-tab script replacement skipped.",
                category: "UserScripts"
            )
            return false
        }

        for installedUserScript in installedUserScripts {
            userContentController.perform(Self.removeUserScriptSelector, with: installedUserScript)
        }
        installedUserScripts.removeAll(keepingCapacity: true)
        return true
#else
        assertionFailure("Sumi normal-tab user-script replacement requires script removal.")
        return false
#endif
    }

#if os(macOS)
    // WebKit exposes no public per-script removal API. Keep the private selector
    // confined to this registry so replacement never removes unrelated scripts.
    private static let removeUserScriptSelector = NSSelectorFromString("_removeUserScript:")
#endif
}
