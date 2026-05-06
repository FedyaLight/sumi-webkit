import Common
import Foundation
import os.log
import WebKit

final class SumiFaviconTransportUserScript: NSObject, SumiUserScript, @MainActor SumiUserScriptMessaging, WKScriptMessageHandlerWithReply {
    let broker: SumiUserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentEnd
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = false
    let messageNames: [String]

    init(context: String = "sumiFavicons") {
        let broker = SumiUserScriptMessageBroker(context: context)
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

    @MainActor
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await executeDDGFaviconBrokerAction(action, original: message)
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
final class SumiDDGFaviconUserScripts: SumiUserScriptsProvider {
    let transportScript: SumiFaviconTransportUserScript
    let faviconScript = SumiDDGFaviconUserScript()
    lazy var userScripts: [SumiUserScript] = [transportScript]

    init() {
        let transportScript = SumiFaviconTransportUserScript()
        self.transportScript = transportScript
        transportScript.registerSubfeature(delegate: SumiDDGFaviconSubfeature(faviconScript: faviconScript))
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        scripts.reserveCapacity(userScripts.count)
        for userScript in userScripts {
            scripts.append(SumiUserScriptBuilder.makeWKUserScript(from: userScript))
        }
        return scripts
    }
}

protocol SumiDDGFaviconUserScriptDelegate: AnyObject {
    @MainActor
    func faviconUserScript(
        _ faviconUserScript: SumiDDGFaviconUserScript,
        didFindFaviconLinks faviconLinks: [SumiDDGFaviconUserScript.FaviconLink],
        for documentUrl: URL,
        in webView: WKWebView?
    )
}

final class SumiDDGFaviconUserScript: NSObject {
    struct FaviconsFoundPayload: Codable, Equatable {
        let documentUrl: URL
        let favicons: [FaviconLink]
    }

    struct FaviconLink: Codable, Equatable {
        let href: URL
        let rel: String
        let type: String?

        init(href: URL, rel: String, type: String? = nil) {
            self.href = href
            self.rel = rel
            self.type = type
        }
    }

    weak var delegate: SumiDDGFaviconUserScriptDelegate?

    enum MessageNames: String, CaseIterable {
        case faviconFound
    }
}

@MainActor
private func executeDDGFaviconBrokerAction(
    _ action: SumiUserScriptMessageBroker.Action,
    original: WKScriptMessage
) async throws -> String {
    switch action {
    case .notify(let handler, let params):
        let params = SumiDDGFaviconMessageParams(from: params)
        do {
            _ = try await handler(params, original)
        } catch {
            Logger.general.error("UserScriptMessaging: unhandled exception \(error.localizedDescription, privacy: .public)")
        }
        return "{}"

    case .respond(let handler, let request):
        let params = SumiDDGFaviconMessageParams(from: request.params)
        let request = SumiDDGFaviconRequestEnvelope(request: request)
        do {
            guard let result = try await handler(params, original) else {
                return SumiDDGFaviconMessageErrorResponse(
                    request: request,
                    message: "could not access encodable result"
                ).toJSON()
            }

            return SumiDDGFaviconMessageResponse(request: request, result: result).toJSON()
                ?? SumiDDGFaviconMessageErrorResponse(
                    request: request,
                    message: "could not convert result to json"
                ).toJSON()
        } catch {
            return SumiDDGFaviconMessageErrorResponse(
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

@MainActor
private final class SumiDDGFaviconSubfeature: NSObject, @MainActor SumiUserScriptSubfeature {
    let featureName: String = "favicon"
    let messageOriginPolicy: SumiUserScriptMessageOriginPolicy = .all

    private let faviconScript: SumiDDGFaviconUserScript

    init(faviconScript: SumiDDGFaviconUserScript) {
        self.faviconScript = faviconScript
        super.init()
    }

    func handler(forMethodNamed methodName: String) -> SumiUserScriptSubfeature.Handler? {
        switch SumiDDGFaviconUserScript.MessageNames(rawValue: methodName) {
        case .faviconFound:
            return { [weak self] params, original in
                try await self?.faviconFound(params: params, original: original)
            }
        default:
            return nil
        }
    }

    private func faviconFound(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let faviconsPayload = SumiDDGFaviconMessagePayload.decode(from: params) else { return nil }

        faviconScript.delegate?.faviconUserScript(
            faviconScript,
            didFindFaviconLinks: faviconsPayload.favicons,
            for: faviconsPayload.documentUrl,
            in: original.webView
        )
        return nil
    }
}

private struct SumiDDGFaviconRequestEnvelope: Sendable {
    let context: String
    let featureName: String
    let id: String

    init(request: SumiUserScriptRequestMessage) {
        self.context = request.context
        self.featureName = request.featureName
        self.id = request.id
    }
}

private struct SumiDDGFaviconMessageParams: Sendable {
    let documentUrl: URL?
    let favicons: [FaviconLink]

    init(from params: Any) {
        if let params = params as? SumiDDGFaviconMessageParams {
            self = params
            return
        }

        guard let faviconsPayload: SumiDDGFaviconUserScript.FaviconsFoundPayload = DecodableHelper.decode(from: params) else {
            self.documentUrl = nil
            self.favicons = []
            return
        }

        self.documentUrl = faviconsPayload.documentUrl
        self.favicons = faviconsPayload.favicons.map(FaviconLink.init(faviconLink:))
    }

    struct FaviconLink: Sendable {
        let href: URL
        let rel: String
        let type: String?

        init(faviconLink: SumiDDGFaviconUserScript.FaviconLink) {
            self.href = faviconLink.href
            self.rel = faviconLink.rel
            self.type = faviconLink.type
        }
    }
}

private struct SumiDDGFaviconMessagePayload {
    let documentUrl: URL
    let favicons: [SumiDDGFaviconUserScript.FaviconLink]

    static func decode(from params: Any) -> SumiDDGFaviconMessagePayload? {
        guard let params = params as? SumiDDGFaviconMessageParams,
              let documentUrl = params.documentUrl
        else {
            return nil
        }

        return SumiDDGFaviconMessagePayload(
            documentUrl: documentUrl,
            favicons: params.favicons.map {
                SumiDDGFaviconUserScript.FaviconLink(href: $0.href, rel: $0.rel, type: $0.type)
            }
        )
    }
}

private struct SumiDDGFaviconMessageResponse: Encodable {
    let request: SumiDDGFaviconRequestEnvelope
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

private struct SumiDDGFaviconMessageErrorResponse: Encodable {
    let context: String
    let featureName: String
    let id: String
    private let error: MessageError

    init(request: SumiDDGFaviconRequestEnvelope, message: String) {
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
