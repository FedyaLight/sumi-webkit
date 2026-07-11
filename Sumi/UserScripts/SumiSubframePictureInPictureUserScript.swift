import Foundation
import SumiWebRuntime
import WebKit

/// Tiny all-frame isolated-world bootstrap. It pays one `play` listener in a
/// subframe, then lazily installs a PiP-only sensor into that exact frame. The
/// page world cannot access either its handler or the main-document token.
@MainActor
final class SumiSubframePictureInPictureUserScript: NSObject, SumiUserScript,
    WKScriptMessageHandlerWithReply
{
    private let bootstrapContext: String
    private let reportContext: String
    private weak var committedDocumentRuntime: TabCommittedDocumentRuntime?

    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = false
    let messageNames: [String]

    init(
        tabID: UUID,
        committedDocumentRuntime: TabCommittedDocumentRuntime
    ) {
        bootstrapContext = "sumiSubframePiPBootstrap_\(tabID.uuidString)"
        reportContext = "sumiSubframePiPReport_\(tabID.uuidString)"
        self.committedDocumentRuntime = committedDocumentRuntime
        messageNames = [bootstrapContext, reportContext]
        source = Self.makeBootstrapSource(context: bootstrapContext)
        super.init()
    }

    private static func makeBootstrapSource(context: String) -> String {
        """
        (() => {
            if (
                window.top === window
                || window.__sumiSubframePictureInPictureBootstrap
            ) {
                return;
            }
            window.__sumiSubframePictureInPictureBootstrap = true;
            let requested = false;
            function handleVideoPlay(event) {
                if (requested || !(event.target instanceof HTMLVideoElement)) {
                    return;
                }
                requested = true;
                document.removeEventListener("play", handleVideoPlay, true);
                const reply = window.webkit?.messageHandlers?.["\(context)"]
                    ?.postMessage({ method: "activate" });
                if (reply && typeof reply.catch === "function") {
                    reply.catch(() => {});
                }
            }
            document.addEventListener("play", handleVideoPlay, true);
        })();
        """
    }

    private static let sensorSource = """
    if (window.__sumiSubframePictureInPictureSensor) {
        return await window.__sumiSubframePictureInPictureSensor
            .activate(mainDocumentToken);
    }

    const handler = window.webkit?.messageHandlers?.[reportContext];
    if (!handler) { return false; }
    const frameDocumentIdentity = globalThis.crypto?.randomUUID?.()
        || `${Date.now()}:${Math.random()}:${Math.random()}`;
    let documentLeaseToken = null;
    let sequence = 0;
    let isPictureInPictureActive = Array.from(
        document.querySelectorAll("video")
    ).some(video =>
        video.webkitPresentationMode === "picture-in-picture"
    ) || !!document.pictureInPictureElement;

    async function publish() {
        if (!documentLeaseToken) { return false; }
        sequence += 1;
        try {
            const reply = await handler.postMessage({
                context: reportContext,
                method: "pictureInPictureState",
                params: {
                    documentIdentity: frameDocumentIdentity,
                    documentLeaseToken,
                    sequence,
                    documentURL: document.URL,
                    isActive: isPictureInPictureActive
                }
            });
            return reply?.accepted === true;
        } catch (_) {
            return false;
        }
    }

    function publishWithoutReply() {
        publish().catch(() => {});
    }

    async function activate(token) {
        if (typeof token !== "string" || !token) { return false; }
        documentLeaseToken = token;
        return await publish();
    }

    function handlePictureInPictureChange(event) {
        const video = event.target instanceof HTMLVideoElement
            ? event.target
            : null;
        if (event.type === "enterpictureinpicture") {
            isPictureInPictureActive = true;
        } else if (event.type === "leavepictureinpicture") {
            isPictureInPictureActive =
                !!document.pictureInPictureElement
                || video?.webkitPresentationMode === "picture-in-picture";
        } else {
            isPictureInPictureActive =
                !!document.pictureInPictureElement
                || video?.webkitPresentationMode === "picture-in-picture";
        }
        publishWithoutReply();
    }
    for (const eventName of [
        "enterpictureinpicture",
        "leavepictureinpicture",
        "webkitpresentationmodechanged"
    ]) {
        document.addEventListener(
            eventName,
            handlePictureInPictureChange,
            true
        );
    }
    window.addEventListener("pagehide", () => {
        const wasActive = isPictureInPictureActive;
        isPictureInPictureActive =
            !!document.pictureInPictureElement
            || Array.from(document.querySelectorAll("video")).some(video =>
                video.webkitPresentationMode === "picture-in-picture"
            );
        if (isPictureInPictureActive === wasActive) { return; }
        publishWithoutReply();
    });

    Object.defineProperty(
        window,
        "__sumiSubframePictureInPictureSensor",
        {
            value: Object.freeze({ activate }),
            writable: false,
            configurable: false
        }
    );
    return await activate(mainDocumentToken);
    """

    func userContentController(
        _ _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        if message.name == bootstrapContext {
            let started = startSensorInstallation(from: message)
            return (["accepted": started], nil)
        }
        let accepted = acceptPictureInPictureReport(message)
        return (["accepted": accepted], nil)
    }

    func userContentController(
        _ _: WKUserContentController,
        didReceive _: WKScriptMessage
    ) {}

    private func startSensorInstallation(
        from message: WKScriptMessage
    ) -> Bool {
        guard message.frameInfo.isMainFrame == false,
              let webView = message.webView,
              let committedDocumentRuntime,
              let lease = committedDocumentRuntime.lease(for: webView),
              let token = committedDocumentRuntime
                .suspensionActivationToken(for: webView)
        else { return false }
        installSensor(
            in: message.frameInfo,
            webView: webView,
            committedDocumentRuntime: committedDocumentRuntime,
            lease: lease,
            token: token,
            attempt: 1
        )
        return true
    }

    private func installSensor(
        in frame: WKFrameInfo,
        webView: WKWebView,
        committedDocumentRuntime: TabCommittedDocumentRuntime,
        lease: TabMainFrameDocumentLease,
        token: String,
        attempt: Int
    ) {
        webView.callAsyncJavaScript(
            Self.sensorSource,
            arguments: [
                "mainDocumentToken": token,
                "reportContext": reportContext,
            ],
            in: frame,
            in: .defaultClient,
            completionHandler: {
                [weak self, weak webView, weak committedDocumentRuntime] result in
                let installed: Bool
                switch result {
                case .success(let value):
                    installed = value as? Bool == true
                case .failure:
                    installed = false
                }
                guard installed == false, attempt < 3 else { return }
                Task { @MainActor in
                    await Task.yield()
                    guard let self,
                          let webView,
                          let committedDocumentRuntime,
                          self.matchesCurrentDocument(
                              lease,
                              token: token,
                              webView: webView,
                              committedDocumentRuntime: committedDocumentRuntime
                          ) else { return }
                    self.installSensor(
                        in: frame,
                        webView: webView,
                        committedDocumentRuntime: committedDocumentRuntime,
                        lease: lease,
                        token: token,
                        attempt: attempt + 1
                    )
                }
            }
        )
    }

    private func matchesCurrentDocument(
        _ lease: TabMainFrameDocumentLease,
        token: String,
        webView: WKWebView,
        committedDocumentRuntime: TabCommittedDocumentRuntime
    ) -> Bool {
        guard let currentLease = committedDocumentRuntime.lease(
            for: webView
        ),
              currentLease.revision == lease.revision,
              currentLease.documentGeneration == lease.documentGeneration,
              currentLease.participantID == lease.participantID,
              committedDocumentRuntime.suspensionActivationToken(
                for: webView
              ) == token else {
            return false
        }
        return true
    }

    private func acceptPictureInPictureReport(
        _ message: WKScriptMessage
    ) -> Bool {
        guard message.name == reportContext,
              message.frameInfo.isMainFrame == false,
              let webView = message.webView,
              let committedDocumentRuntime,
              let payload = Payload(message: message, context: reportContext),
              let frameURL = message.frameInfo.sumiWebKitRequestURL,
              WebRuntimeNavigationIdentity(frameURL)
                == WebRuntimeNavigationIdentity(payload.documentURL),
              let lease = committedDocumentRuntime.lease(for: webView) else {
            return false
        }

        return committedDocumentRuntime.recordSubframePictureInPictureReport(
            payload.report,
            from: webView,
            matching: lease
        )
    }
}

private extension SumiSubframePictureInPictureUserScript {
    @MainActor
    struct Payload {
        let documentURL: URL
        let report: TabSubframePictureInPictureReport

        init?(message: WKScriptMessage, context: String) {
            guard let body = message.body as? [String: Any],
                  body["context"] as? String == context,
                  body["method"] as? String == "pictureInPictureState",
                  let params = body["params"] as? [String: Any],
                  let documentIdentity = params["documentIdentity"] as? String,
                  documentIdentity.isEmpty == false,
                  documentIdentity.utf8.count <= 256,
                  let documentLeaseToken =
                    params["documentLeaseToken"] as? String,
                  let sequenceNumber = params["sequence"] as? NSNumber,
                  let documentURLString = params["documentURL"] as? String,
                  let documentURL = URL(string: documentURLString),
                  let isActive = params["isActive"] as? Bool else {
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
            self.report = TabSubframePictureInPictureReport(
                documentNonce: documentIdentity,
                documentLeaseToken: documentLeaseToken,
                sequence: UInt64(sequenceValue),
                isActive: isActive
            )
        }
    }
}
