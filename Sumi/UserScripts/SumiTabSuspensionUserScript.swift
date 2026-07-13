import Foundation
import WebKit

/// Page-world compatibility API. It can express only the page's own veto;
/// native document tokens and PiP observation live in isolated-world sensors.
@MainActor
final class SumiTabSuspensionUserScript: NSObject, SumiPageScript,
    WKScriptMessageHandlerWithReply
{
    private let context: String

    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(tabID: UUID) {
        context = "sumiTabSuspension_\(tabID.uuidString)"
        messageNames = [context]
        source = Self.makeSource(context: context)
        super.init()
    }

    private static func makeSource(context: String) -> String {
        """
        (() => {
            if (window.__sumiTabSuspensionInstalled) { return; }
            Object.defineProperty(window, "__sumiTabSuspensionInstalled", {
                value: true,
                writable: false,
                configurable: false
            });

            const handler = window.webkit?.messageHandlers?.["\(context)"];
            if (!handler) { return; }

            const documentIdentity = globalThis.crypto?.randomUUID?.()
                || `${Date.now()}:${Math.random()}:${Math.random()}`;
            let sequence = 0;
            let pageAllowsSuspension = true;

            function publishCurrentState() {
                sequence += 1;
                const reply = handler.postMessage({
                    context: "\(context)",
                    method: "pageState",
                    params: {
                        documentIdentity,
                        sequence,
                        canBeSuspended: pageAllowsSuspension
                    }
                });
                return reply && typeof reply.catch === "function"
                    ? reply.catch(() => ({ accepted: false }))
                    : reply;
            }

            function publishCurrentStateWithoutReply() {
                const reply = publishCurrentState();
                if (reply && typeof reply.catch === "function") {
                    reply.catch(() => {});
                }
            }

            function reportCanBeSuspended(canBeSuspended) {
                if (typeof canBeSuspended !== "boolean") { return; }
                pageAllowsSuspension = canBeSuspended;
                return publishCurrentState();
            }

            Object.defineProperty(window, "__sumiTabSuspension", {
                value: Object.freeze({
                    canBeSuspended: reportCanBeSuspended
                }),
                writable: false,
                configurable: false
            });

            if (document.readyState === "loading") {
                document.addEventListener(
                    "DOMContentLoaded",
                    publishCurrentStateWithoutReply,
                    { once: true }
                );
            } else {
                queueMicrotask(publishCurrentStateWithoutReply);
            }
            window.addEventListener("pageshow", event => {
                if (event.persisted) { publishCurrentStateWithoutReply(); }
            });
        })();
        """
    }

    func userContentController(
        _ _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard message.name == context,
              message.frameInfo.isMainFrame,
              let webView = message.webView,
              let payload = Payload(message: message, context: context) else {
            return (["accepted": false], nil)
        }

        let accepted: Bool
        do {
            accepted = try await webView.callAsyncJavaScript(
                """
                return await window.__sumiDocumentSuspensionSensor
                    ?.setPageState(documentIdentity, sequence, canBeSuspended)
                    ?? false;
                """,
                arguments: [
                    "documentIdentity": payload.documentIdentity,
                    "sequence": payload.sequence,
                    "canBeSuspended": payload.canBeSuspended,
                ],
                in: message.frameInfo,
                contentWorld: .defaultClient
            ) as? Bool == true
        } catch {
            accepted = false
        }
        return (["accepted": accepted], nil)
    }

    func userContentController(
        _ _: WKUserContentController,
        didReceive _: WKScriptMessage
    ) {}
}

private extension SumiTabSuspensionUserScript {
    @MainActor
    struct Payload {
        let documentIdentity: String
        let sequence: Double
        let canBeSuspended: Bool

        init?(message: WKScriptMessage, context: String) {
            guard let body = message.body as? [String: Any],
                  body["context"] as? String == context,
                  body["method"] as? String == "pageState",
                  let params = body["params"] as? [String: Any],
                  let documentIdentity = params["documentIdentity"] as? String,
                  documentIdentity.isEmpty == false,
                  documentIdentity.utf8.count <= 256,
                  let sequenceNumber = params["sequence"] as? NSNumber,
                  let canBeSuspended = params["canBeSuspended"] as? Bool else {
                return nil
            }
            let sequence = sequenceNumber.doubleValue
            guard sequence.isFinite,
                  sequence >= 1,
                  sequence.rounded(.towardZero) == sequence,
                  sequence <= 9_007_199_254_740_991 else {
                return nil
            }
            self.documentIdentity = documentIdentity
            self.sequence = sequence
            self.canBeSuspended = canBeSuspended
        }
    }
}
