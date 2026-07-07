import Foundation
import WebKit

/// Tiny per-subframe bootstrap for the background video optimizer.
///
/// The full optimizer source is only worth parsing in frames that actually
/// play video. Subframes get this stub instead: it captures optimizer
/// commands broadcast from the parent frame, keeps forwarding them to nested
/// frames, and on the first `<video>` "play" asks native code to inject the
/// full optimizer into exactly that frame.
@MainActor
final class SumiBackgroundVideoOptimizationSubframeStubUserScript: NSObject, SumiUserScript {
    static let bootstrapMessageName = "sumiBackgroundVideoOptimizerBootstrap"

    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = false
    let messageNames: [String] = [
        SumiBackgroundVideoOptimizationSubframeStubUserScript.bootstrapMessageName,
    ]

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let webView = message.webView else { return }
        webView.evaluateJavaScript(
            SumiBackgroundVideoOptimizationUserScript.fullSource,
            in: message.frameInfo,
            in: .defaultClient,
            completionHandler: nil
        )
    }

    let source = """
    (() => {
        const apiName = "__sumiBackgroundVideoOptimizer";
        const stubStateName = "__sumiBGVStubState";
        if (window.top === window || window[apiName] || window[stubStateName]) {
            return;
        }

        const commandType = "__sumiBackgroundVideoOptimizationCommand";
        const stubState = { cmd: null };
        window[stubStateName] = stubState;

        window.addEventListener("message", (event) => {
            if (window[apiName]) {
                // The full optimizer took over; it handles commands and
                // re-broadcasts to child frames itself.
                return;
            }
            const data = event.data;
            if (!data || data.commandType !== commandType) {
                return;
            }
            stubState.cmd = {
                mode: data.mode,
                graceMs: data.graceMs
            };
            // Keep the broadcast chain alive for nested frames that still run
            // only the stub.
            for (let index = 0; index < window.frames.length; index += 1) {
                try {
                    window.frames[index].postMessage(data, "*");
                } catch {}
            }
        });

        let bootstrapRequested = false;
        document.addEventListener("play", (event) => {
            if (window[apiName] || bootstrapRequested) {
                return;
            }
            if (!(event.target instanceof HTMLVideoElement)) {
                return;
            }
            bootstrapRequested = true;
            try {
                window.webkit.messageHandlers.sumiBackgroundVideoOptimizerBootstrap.postMessage({});
            } catch {}
        }, true);
    })();
    """
}
