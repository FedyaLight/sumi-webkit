import Foundation
import UserScript
import WebKit

final class SumiFaviconTransportUserScript: NSObject, UserScript, @MainActor UserScriptMessaging, WKScriptMessageHandlerWithReply {
    let broker: UserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentEnd
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = false
    let messageNames: [String]

    init(context: String = "sumiFavicons") {
        let broker = UserScriptMessageBroker(context: context)
        self.broker = broker
        self.messageNames = [context]
        self.source = Self.makeSource(context: context)
        super.init()
    }

    private static func makeSource(context: String) -> String {
        """
        (() => {
          const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers["\(context)"];
          if (!handler || window.__sumiDDGFaviconTransportInstalled) { return; }
          window.__sumiDDGFaviconTransportInstalled = true;

          let lastSignature = { value: null };

          const collectFavicons = () => {
            const head = document.head;
            if (!head) { return []; }

            const selectors = [
              "link[href][rel='favicon']",
              "link[href][rel*='icon']",
              "link[href][rel='apple-touch-icon']",
              "link[href][rel='apple-touch-icon-precomposed']"
            ];

            return Array.from(head.querySelectorAll(selectors.join(',')))
              .filter((element) => element instanceof HTMLLinkElement)
              .map((link) => ({
                href: link.href || '',
                rel: link.getAttribute('rel') || '',
                type: link.type || ''
              }))
              .filter((link) => link.href.length > 0 && link.rel.length > 0);
          };

          const postPayload = () => {
            const favicons = collectFavicons();
            const signature = JSON.stringify([document.URL, favicons]);
            if (signature === lastSignature.value) { return; }
            lastSignature.value = signature;

            handler.postMessage({
              context: "\(context)",
              featureName: "favicon",
              method: "faviconFound",
              params: {
                documentUrl: document.URL,
                favicons
              }
            });
          };

          const observe = () => {
            const head = document.head;
            if (!head || !window.MutationObserver) { return; }

            let pending = false;
            const schedule = () => {
              if (pending) { return; }
              pending = true;
              setTimeout(() => {
                pending = false;
                postPayload();
              }, 50);
            };

            const observer = new MutationObserver((mutations) => {
              for (const mutation of mutations) {
                if (mutation.type === 'attributes' && mutation.target instanceof HTMLLinkElement) {
                  schedule();
                  return;
                }
                if (mutation.type === 'childList') {
                  for (const addedNode of mutation.addedNodes) {
                    if (addedNode instanceof HTMLLinkElement) {
                      schedule();
                      return;
                    }
                  }
                  for (const removedNode of mutation.removedNodes) {
                    if (removedNode instanceof HTMLLinkElement) {
                      schedule();
                      return;
                    }
                  }
                }
              }
            });

            observer.observe(head, {
              childList: true,
              subtree: true,
              attributes: true,
              attributeFilter: ["rel", "href", "type"]
            });
          };

          const start = () => {
            postPayload();
            observe();
          };

          if (document.readyState === "loading") {
            window.addEventListener("DOMContentLoaded", start, { once: true });
          } else {
            start();
          }
        })();
        """
    }

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
final class SumiDDGFaviconUserScripts: UserScriptsProvider {
    let transportScript: SumiFaviconTransportUserScript
    let faviconScript = FaviconUserScript()
    lazy var userScripts: [UserScript] = [transportScript]

    init() {
        let transportScript = SumiFaviconTransportUserScript()
        self.transportScript = transportScript
        transportScript.registerSubfeature(delegate: faviconScript)
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        scripts.reserveCapacity(userScripts.count)
        for userScript in userScripts {
            let script = await userScript.makeWKUserScript()
            scripts.append(script.wkUserScript)
        }
        return scripts
    }
}
