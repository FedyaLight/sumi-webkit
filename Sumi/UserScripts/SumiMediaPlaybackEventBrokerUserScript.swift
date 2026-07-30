import Foundation
import WebKit

@MainActor
final class SumiMediaPlaybackEventBrokerUserScript: NSObject, SumiPageScript {
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = false
    let messageNames: [String] = []

    let source = """
    (() => {
        const name = "__sumiMediaPlaybackBroker";
        if (window[name]) { return; }

        const subscribers = new Set();
        const subscribe = callback => {
            if (typeof callback !== "function") {
                return () => {};
            }
            subscribers.add(callback);
            return () => subscribers.delete(callback);
        };

        document.addEventListener("play", event => {
            if (!(event.target instanceof HTMLVideoElement)) { return; }
            for (const callback of subscribers) {
                try {
                    callback(event);
                } catch {}
            }
        }, true);

        Object.defineProperty(window, name, {
            value: Object.freeze({ subscribe }),
            writable: false,
            configurable: false
        });
    })();
    """

    func userContentController(
        _: WKUserContentController,
        didReceive _: WKScriptMessage
    ) {}
}
