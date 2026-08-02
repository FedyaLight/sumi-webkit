import Foundation
import SumiWebRuntime
import WebKit

/// Main-frame isolated-world sensor. It alone receives the native token for a
/// committed document and publishes the page's declared suspension veto as
/// exact replica evidence.
@MainActor
final class SumiDocumentSuspensionSensorUserScript: NSObject, SumiPageScript,
    WKScriptMessageHandlerWithReply {
    private let context: String
    private weak var committedDocumentRuntime: TabCommittedDocumentRuntime?

    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let messageNames: [String]

    init(
        tabID: UUID,
        committedDocumentRuntime: TabCommittedDocumentRuntime
    ) {
        context = "sumiDocumentSuspensionSensor"
        self.committedDocumentRuntime = committedDocumentRuntime
        messageNames = [context]
        source = Self.makeSource(context: context)
        super.init()
    }

    private static func makeSource(context: String) -> String {
        """
        (() => {
            if (window.__sumiDocumentSuspensionSensor) { return; }
            const handler = window.webkit?.messageHandlers?.["\(context)"];
            if (!handler) { return; }

            const sensorDocumentIdentity = globalThis.crypto?.randomUUID?.()
                || `${Date.now()}:${Math.random()}:${Math.random()}`;
            let documentLeaseToken = null;
            let documentLeaseEpoch = null;
            let sequence = 0;
            let pageDocumentIdentity = null;
            let pageSequence = 0;
            let pageAllowsSuspension = true;

            async function publishCurrentState() {
                if (!documentLeaseToken) { return false; }
                sequence += 1;
                try {
                    const reply = await handler.postMessage({
                        context: "\(context)",
                        method: "documentState",
                        params: {
                            documentIdentity: sensorDocumentIdentity,
                            documentLeaseToken,
                            sequence,
                            documentURL: document.URL,
                            canBeSuspended: pageAllowsSuspension
                        }
                    });
                    return reply?.accepted === true;
                } catch (_) {
                    return false;
                }
            }

            async function setPageState(identity, nextSequence, canBeSuspended) {
                if (
                    typeof identity !== "string"
                    || !identity
                    || !Number.isSafeInteger(nextSequence)
                    || nextSequence < 1
                    || typeof canBeSuspended !== "boolean"
                ) {
                    return false;
                }
                if (pageDocumentIdentity && pageDocumentIdentity !== identity) {
                    return false;
                }
                if (nextSequence <= pageSequence) { return false; }
                pageDocumentIdentity = identity;
                pageSequence = nextSequence;
                pageAllowsSuspension = canBeSuspended;
                return await publishCurrentState();
            }

            async function activateCommittedDocument(token, epochText) {
                if (
                    typeof token !== "string"
                    || !token
                    || typeof epochText !== "string"
                    || !/^[0-9]+$/.test(epochText)
                ) {
                    return false;
                }
                const epoch = BigInt(epochText);
                if (documentLeaseEpoch !== null) {
                    if (epoch < documentLeaseEpoch) { return false; }
                    if (
                        epoch === documentLeaseEpoch
                        && token !== documentLeaseToken
                    ) {
                        return false;
                    }
                }
                documentLeaseEpoch = epoch;
                documentLeaseToken = token;
                return await publishCurrentState();
            }

            Object.defineProperty(window, "__sumiDocumentSuspensionSensor", {
                value: Object.freeze({
                    activateCommittedDocument,
                    setPageState
                }),
                writable: false,
                configurable: false
            });
        })();
        """
    }

    static func activateCommittedDocument(
        on webView: WKWebView,
        token: String,
        epoch: UInt64,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        webView.callAsyncJavaScript(
            """
            return await window.__sumiDocumentSuspensionSensor
                ?.activateCommittedDocument(token, epoch) ?? false;
            """,
            arguments: [
                "token": token,
                "epoch": String(epoch),
            ],
            in: nil,
            in: .defaultClient,
            completionHandler: { result in
                let activated: Bool
                switch result {
                case .success(let value):
                    activated = value as? Bool == true
                case .failure:
                    activated = false
                }
                Task { @MainActor in
                    completion(activated)
                }
            }
        )
    }

    func userContentController(
        _ _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let accepted = accept(message)
        return (["accepted": accepted], nil)
    }

    func userContentController(
        _ _: WKUserContentController,
        didReceive _: WKScriptMessage
    ) {}

    private func accept(_ message: WKScriptMessage) -> Bool {
        guard message.name == context,
              message.frameInfo.isMainFrame,
              let webView = message.webView,
              let committedDocumentRuntime,
              let payload = Payload(message: message, context: context),
              let lease = committedDocumentRuntime.lease(for: webView),
              payload.matches(lease: lease),
              message.frameInfo.sumiWebKitRequestURL.map({
                  payload.matches(url: $0, lease: lease)
              }) ?? false else {
            return false
        }

        return committedDocumentRuntime.recordSuspensionReport(
            payload.report,
            from: webView,
            matching: lease
        )
    }
}

private extension SumiDocumentSuspensionSensorUserScript {
    @MainActor
    struct Payload {
        let documentURL: URL
        let report: TabDocumentSuspensionReport

        init?(message: WKScriptMessage, context: String) {
            guard let body = message.body as? [String: Any],
                  body["context"] as? String == context,
                  body["method"] as? String == "documentState",
                  let params = body["params"] as? [String: Any],
                  let documentIdentity = params["documentIdentity"] as? String,
                  let documentLeaseToken =
                    params["documentLeaseToken"] as? String,
                  let sequenceNumber = params["sequence"] as? NSNumber,
                  let documentURLString = params["documentURL"] as? String,
                  let documentURL = URL(string: documentURLString),
                  let canBeSuspended = params["canBeSuspended"] as? Bool else {
                return nil
            }
            let sequenceValue = sequenceNumber.doubleValue
            guard sequenceValue.isFinite,
                  sequenceValue >= 1,
                  sequenceValue.rounded(.towardZero) == sequenceValue,
                  sequenceValue <= 9_007_199_254_740_991 else {
                return nil
            }
            self.documentURL = documentURL
            self.report = TabDocumentSuspensionReport(
                documentNonce: documentIdentity,
                documentLeaseToken: documentLeaseToken,
                sequence: UInt64(sequenceValue),
                canBeSuspended: canBeSuspended
            )
        }

        func matches(lease: TabMainFrameDocumentLease) -> Bool {
            matches(url: documentURL, lease: lease)
        }

        func matches(url: URL, lease: TabMainFrameDocumentLease) -> Bool {
            WebRuntimeNavigationIdentity(url)
                == WebRuntimeNavigationIdentity(lease.committedURL)
                || WebRuntimeNavigationIdentity(url)
                    == WebRuntimeNavigationIdentity(lease.presentationURL)
        }
    }
}
