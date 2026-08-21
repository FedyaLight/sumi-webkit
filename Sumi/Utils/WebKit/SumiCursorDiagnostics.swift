#if DEBUG
import AppKit
import WebKit

/// Debug-only, env-gated cursor pipeline probe used by UI tests to observe
/// WebKit cursor and hover state (XCTest cannot read the system cursor or
/// evaluate page JavaScript in the app process).
/// Enable with SUMI_CURSOR_DIAGNOSTICS=1 and SUMI_CURSOR_DIAGNOSTICS_FILE=<path>.
@MainActor
enum SumiCursorDiagnostics {
    static let isEnabled =
        ProcessInfo.processInfo.environment["SUMI_CURSOR_DIAGNOSTICS"] == "1"

    private static var isStarted = false

    static func startIfNeeded() {
        guard isEnabled, !isStarted else { return }
        isStarted = true
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { dumpState() }
        }
    }

    static func log(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["SUMI_CURSOR_DIAGNOSTICS_FILE"] else {
            return
        }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
        try? handle.close()
    }

    private static func dumpState() {
        guard let contentView = NSApp.keyWindow?.contentView else { return }

        let identity: String
        if NSCursor.current === NSCursor.pointingHand {
            identity = "pointingHand"
        } else {
            identity = "other"
        }

        var queue: [NSView] = [contentView]
        while let view = queue.popLast() {
            if let webView = view as? FocusableWKWebView {
                webView.evaluateJavaScript(
                    "JSON.stringify({hoverLink: !!document.querySelector('a:hover')})"
                ) { result, _ in
                    MainActor.assumeIsolated {
                        log(
                            "url=\(webView.url?.lastPathComponent ?? "-") page=\(result as? String ?? "nil") cursor=\(identity)"
                        )
                    }
                }
            }
            queue.append(contentsOf: view.subviews)
        }
    }
}
#endif
