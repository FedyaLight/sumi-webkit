import Foundation
import os.log
import WebKit

final class SumiFaviconTransportUserScript: NSObject, SumiUserScript, @MainActor SumiUserScriptMessaging, WKScriptMessageHandlerWithReply {
    let broker: SumiUserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentEnd
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
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
          if (!handler || window.__sumiFaviconTransportInstalled) { return; }
          window.__sumiFaviconTransportInstalled = true;

          let lastSignature = "";
          const faviconRelTokens = (rel) => (rel || "")
            .split(/\\s+/)
            .map((token) => token.toLowerCase())
            .filter((token) => token.length > 0);
          const isFaviconRel = (rel) => {
            const tokens = faviconRelTokens(rel);
            return tokens.includes("icon")
              || tokens.includes("apple-touch-icon")
              || tokens.includes("apple-touch-icon-precomposed")
              || tokens.includes("mask-icon")
              || tokens.includes("manifest");
          };
          let collectLinks = () => {
            const head = document.head;
            if (!head) { return []; }
            return Array.from(head.querySelectorAll("link[href][rel]"))
              .filter((element) => element instanceof HTMLLinkElement)
              .map((link) => ({
                href: link.href || "",
                rel: link.getAttribute("rel") || "",
                type: link.getAttribute("type") || "",
                sizes: link.getAttribute("sizes") || "",
                media: link.getAttribute("media") || ""
              }))
              .filter((link) => link.href.length > 0 && isFaviconRel(link.rel));
          };

          const postPayload = () => {
            const links = collectLinks();
            const signature = JSON.stringify([document.URL, document.baseURI, links]);
            if (signature === lastSignature) { return; }
            lastSignature = signature;
            handler.postMessage({
              context: "\(context)",
              featureName: "favicon",
              method: "faviconFound",
              params: {
                documentUrl: document.URL,
                baseUrl: document.baseURI,
                favicons: links
              }
            });
          };

          let pending = false;
          const schedule = () => {
            if (pending) { return; }
            pending = true;
            setTimeout(() => {
              pending = false;
              postPayload();
            }, 120);
          };

          const observeHead = () => {
            const head = document.head;
            if (!head || !window.MutationObserver) { return; }
            const observer = new MutationObserver((mutations) => {
              for (const mutation of mutations) {
                if (mutation.type === "attributes" && mutation.target instanceof HTMLLinkElement) {
                  schedule();
                  return;
                }
                if (mutation.type === "childList") {
                  for (const node of mutation.addedNodes) {
                    if (node instanceof HTMLLinkElement || (node.querySelector && node.querySelector("link[href][rel]"))) {
                      schedule();
                      return;
                    }
                  }
                  for (const node of mutation.removedNodes) {
                    if (node instanceof HTMLLinkElement || (node.querySelector && node.querySelector("link[href][rel]"))) {
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
              attributeFilter: ["rel", "href", "type", "sizes", "media"]
            });
          };

          const wrapHistoryMethod = (name) => {
            const original = history[name];
            if (typeof original !== "function" || original.__sumiFaviconWrapped) { return; }
            const wrapped = function() {
              const result = original.apply(this, arguments);
              schedule();
              return result;
            };
            wrapped.__sumiFaviconWrapped = true;
            history[name] = wrapped;
          };

          const start = () => {
            postPayload();
            observeHead();
            wrapHistoryMethod("pushState");
            wrapHistoryMethod("replaceState");
            window.addEventListener("popstate", schedule, { passive: true });
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
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await executeSumiFaviconBrokerAction(action, original: message)
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
final class SumiFaviconUserScripts {
    let transportScript: SumiFaviconTransportUserScript
    let faviconScript = SumiFaviconUserScript()
    lazy var userScripts: [SumiUserScript] = [transportScript]

    init() {
        let transportScript = SumiFaviconTransportUserScript()
        self.transportScript = transportScript
        transportScript.registerSubfeature(delegate: SumiFaviconSubfeature(faviconScript: faviconScript))
    }
}

protocol SumiFaviconUserScriptDelegate: AnyObject {
    @MainActor
    func faviconUserScript(
        _ faviconUserScript: SumiFaviconUserScript,
        didFindFaviconLinks faviconLinks: [SumiFaviconUserScript.FaviconLink],
        documentUrl: URL,
        baseURL: URL?,
        in webView: WKWebView?
    )
}

final class SumiFaviconUserScript: NSObject {
    struct FaviconsFoundPayload: Codable, Equatable {
        let documentUrl: URL
        let baseUrl: URL?
        let favicons: [FaviconLink]
    }

    struct FaviconLink: Codable, Equatable {
        let href: URL
        let rel: String
        let type: String?
        let sizes: String?
        let media: String?

        init(
            href: URL,
            rel: String,
            type: String? = nil,
            sizes: String? = nil,
            media: String? = nil
        ) {
            self.href = href
            self.rel = rel
            self.type = type
            self.sizes = sizes
            self.media = media
        }

        var discoveredLink: SumiFaviconDiscoveredLink {
            SumiFaviconDiscoveredLink(
                href: href.absoluteString,
                rel: rel,
                type: type,
                sizes: sizes,
                media: media
            )
        }
    }

    weak var delegate: SumiFaviconUserScriptDelegate?

    enum MessageNames: String, CaseIterable {
        case faviconFound
    }
}

@MainActor
private func executeSumiFaviconBrokerAction(
    _ action: SumiUserScriptMessageBroker.Action,
    original: WKScriptMessage
) async throws -> String {
    switch action {
    case .notify(let handler, let params):
        let params = SumiFaviconMessageParams(from: params)
        do {
            _ = try await handler(params, original)
        } catch {
            Logger.sumiGeneral.error("UserScriptMessaging: unhandled exception \(error.localizedDescription, privacy: .public)")
        }
        return "{}"

    case .respond(let handler, let request):
        let params = SumiFaviconMessageParams(from: request.params)
        let request = SumiFaviconRequestEnvelope(request: request)
        do {
            guard let result = try await handler(params, original) else {
                return SumiFaviconMessageErrorResponse(
                    request: request,
                    message: "could not access encodable result"
                ).toJSON()
            }

            return SumiFaviconMessageResponse(request: request, result: result).toJSON()
                ?? SumiFaviconMessageErrorResponse(
                    request: request,
                    message: "could not convert result to json"
                ).toJSON()
        } catch {
            return SumiFaviconMessageErrorResponse(
                request: request,
                message: error.localizedDescription
            ).toJSON()
        }

    case .error(let error):
        throw error.asNSError
    }
}

@MainActor
private final class SumiFaviconSubfeature: NSObject, @MainActor SumiUserScriptSubfeature {
    let featureName: String = "favicon"
    let messageOriginPolicy: SumiUserScriptMessageOriginPolicy = .all

    private let faviconScript: SumiFaviconUserScript

    init(faviconScript: SumiFaviconUserScript) {
        self.faviconScript = faviconScript
        super.init()
    }

    func handler(forMethodNamed methodName: String) -> SumiUserScriptSubfeature.Handler? {
        switch SumiFaviconUserScript.MessageNames(rawValue: methodName) {
        case .faviconFound:
            return { [weak self] params, original in
                try await self?.faviconFound(params: params, original: original)
            }
        default:
            return nil
        }
    }

    private func faviconFound(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let faviconsPayload = SumiFaviconMessagePayload.decode(from: params) else { return nil }

        faviconScript.delegate?.faviconUserScript(
            faviconScript,
            didFindFaviconLinks: faviconsPayload.favicons,
            documentUrl: faviconsPayload.documentUrl,
            baseURL: faviconsPayload.baseURL,
            in: original.webView
        )
        return nil
    }
}

private struct SumiFaviconRequestEnvelope: Sendable {
    let context: String
    let featureName: String
    let id: String

    init(request: SumiUserScriptRequestMessage) {
        self.context = request.context
        self.featureName = request.featureName
        self.id = request.id
    }
}

private struct SumiFaviconMessageParams: Sendable {
    let documentUrl: URL?
    let baseURL: URL?
    let favicons: [FaviconLink]

    init(from params: Any) {
        if let params = params as? SumiFaviconMessageParams {
            self = params
            return
        }

        guard let faviconsPayload: SumiFaviconUserScript.FaviconsFoundPayload = SumiDecodableHelper.decode(from: params) else {
            self.documentUrl = nil
            self.baseURL = nil
            self.favicons = []
            return
        }

        self.documentUrl = faviconsPayload.documentUrl
        self.baseURL = faviconsPayload.baseUrl
        self.favicons = faviconsPayload.favicons.map(FaviconLink.init(faviconLink:))
    }

    struct FaviconLink: Sendable {
        let href: URL
        let rel: String
        let type: String?
        let sizes: String?
        let media: String?

        init(faviconLink: SumiFaviconUserScript.FaviconLink) {
            self.href = faviconLink.href
            self.rel = faviconLink.rel
            self.type = faviconLink.type
            self.sizes = faviconLink.sizes
            self.media = faviconLink.media
        }
    }
}

private struct SumiFaviconMessagePayload {
    let documentUrl: URL
    let baseURL: URL?
    let favicons: [SumiFaviconUserScript.FaviconLink]

    static func decode(from params: Any) -> SumiFaviconMessagePayload? {
        guard let params = params as? SumiFaviconMessageParams,
              let documentUrl = params.documentUrl
        else {
            return nil
        }

        return SumiFaviconMessagePayload(
            documentUrl: documentUrl,
            baseURL: params.baseURL,
            favicons: params.favicons.map {
                SumiFaviconUserScript.FaviconLink(
                    href: $0.href,
                    rel: $0.rel,
                    type: $0.type,
                    sizes: $0.sizes,
                    media: $0.media
                )
            }
        )
    }
}

private struct SumiFaviconMessageResponse: Encodable {
    let request: SumiFaviconRequestEnvelope
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

private struct SumiFaviconMessageErrorResponse: Encodable {
    let context: String
    let featureName: String
    let id: String
    private let error: MessageError

    init(request: SumiFaviconRequestEnvelope, message: String) {
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
