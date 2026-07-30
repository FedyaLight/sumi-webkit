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
    private var installedStaticUserScripts = [WKUserScript]()
    private var installedNavigationUserScripts = [WKUserScript]()
    private weak var installedProvider: SumiNormalTabUserScripts?
    private var installedStaticProviderRevision: Int?
    private var installedProviderRevision: Int?
    private var installedNavigationScriptsHaveHandlers = false
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

        if installedProvider === provider,
           installedStaticProviderRevision == provider.staticScriptsRevision,
           installedNavigationScriptsHaveHandlers == false,
           provider.navigationScriptsHaveMessageHandlers == false {
            let scripts = provider.preparedNavigationWKUserScripts()
            guard removeInstalledNavigationUserScripts(
                from: userContentController
            ) else { return }
            scripts.forEach(userContentController.addUserScript)
            installedNavigationUserScripts = scripts
            installedProviderRevision = provider.scriptsRevision
            return
        }

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

        let wkUserScripts = provider.preparedWKUserScripts()
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
            && installedStaticProviderRevision == provider.staticScriptsRevision
            && installedProviderRevision == provider.scriptsRevision
            && installedStaticUserScripts.count
                + installedNavigationUserScripts.count
                == provider.userScripts.count
    }

    func cleanUpBeforeClosing() {
        guard let userContentController else {
            isCleanedUp = true
            return
        }

        _ = removeInstalledUserScripts(from: userContentController)
        removeInstalledScriptMessageHandlers(from: userContentController)
        installedProvider = nil
        installedStaticProviderRevision = nil
        installedProviderRevision = nil
        isCleanedUp = true
    }

    private func installUserScripts(
        _ wkUserScripts: [WKUserScript],
        handlers: [SumiPageScript],
        provider: SumiNormalTabUserScripts,
        on userContentController: WKUserContentController
    ) {
        handlers.forEach { addHandler($0, to: userContentController) }
        let staticCount = provider.staticUserScripts.count
        let staticScripts = Array(wkUserScripts.prefix(staticCount))
        let navigationScripts = Array(wkUserScripts.dropFirst(staticCount))
        staticScripts.forEach(userContentController.addUserScript)
        navigationScripts.forEach(userContentController.addUserScript)
        installedStaticUserScripts = staticScripts
        installedNavigationUserScripts = navigationScripts
        installedProvider = provider
        installedStaticProviderRevision = provider.staticScriptsRevision
        installedProviderRevision = provider.scriptsRevision
        installedNavigationScriptsHaveHandlers =
            provider.navigationScriptsHaveMessageHandlers
    }

    private func addHandler(
        _ userScript: SumiPageScript,
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
        installedStaticProviderRevision = nil
        installedProviderRevision = nil
        installedNavigationScriptsHaveHandlers = false
    }

    @discardableResult
    private func removeInstalledUserScripts(from userContentController: WKUserContentController) -> Bool {
        let scripts =
            installedStaticUserScripts + installedNavigationUserScripts
        guard removeUserScripts(scripts, from: userContentController) else {
            return false
        }
        installedStaticUserScripts.removeAll(keepingCapacity: true)
        installedNavigationUserScripts.removeAll(keepingCapacity: true)
        return true
    }

    @discardableResult
    private func removeInstalledNavigationUserScripts(
        from userContentController: WKUserContentController
    ) -> Bool {
        guard removeUserScripts(
            installedNavigationUserScripts,
            from: userContentController
        ) else { return false }
        installedNavigationUserScripts.removeAll(keepingCapacity: true)
        return true
    }

    private func removeUserScripts(
        _ scripts: [WKUserScript],
        from userContentController: WKUserContentController
    ) -> Bool {
        guard scripts.isEmpty == false else { return true }
#if os(macOS)
        guard userContentController.responds(to: Self.removeUserScriptSelector) else {
            RuntimeDiagnostics.debug(
                "WKUserContentController precise user-script removal is unavailable; normal-tab script replacement skipped.",
                category: "UserScripts"
            )
            return false
        }

        for installedUserScript in scripts {
            userContentController.perform(Self.removeUserScriptSelector, with: installedUserScript)
        }
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
