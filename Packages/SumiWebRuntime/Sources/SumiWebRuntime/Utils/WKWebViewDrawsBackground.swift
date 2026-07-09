import OSLog
import WebKit

/// `drawsBackground` is a private WKWebView property (no public equivalent on macOS) used to
/// suppress the opaque white compositor background during host attachment transitions.
/// KVC `setValue(_:forKey:)` resolves it through `setDrawsBackground:`/`_setDrawsBackground:`;
/// probing those selectors first turns a potential `NSUnknownKeyException` crash on a future
/// macOS that drops the property into a logged no-op (the cost is only a possible white flash).
private let drawsBackgroundSetterIsAvailable: Bool = [
    Selector(("setDrawsBackground:")),
    Selector(("_setDrawsBackground:")),
].contains { WKWebView.instancesRespond(to: $0) }

private let drawsBackgroundLog = Logger.sumi(category: "WebViewDrawsBackground")

extension WKWebView {
    func sumiSetDrawsBackground(_ drawsBackground: Bool) {
        guard drawsBackgroundSetterIsAvailable else {
            drawsBackgroundLog.error(
                "WKWebView no longer responds to a drawsBackground setter; skipping background transition tweak."
            )
            return
        }
        setValue(drawsBackground, forKey: "drawsBackground")
    }
}
