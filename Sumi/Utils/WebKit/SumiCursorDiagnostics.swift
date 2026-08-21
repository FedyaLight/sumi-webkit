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
        do {
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try handle.close()
        } catch {
            assertionFailure("Cursor diagnostics write failed: \(error)")
        }
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
                webView.callAsyncJavaScript(
                    "return !!document.querySelector('a:hover');",
                    arguments: [:],
                    in: nil,
                    in: .defaultClient
                ) { result in
                    MainActor.assumeIsolated {
                        let hoverLink: Bool
                        switch result {
                        case .success(let value):
                            hoverLink = value as? Bool == true
                        case .failure:
                            hoverLink = false
                        }
                        log(
                            "url=\(webView.url?.lastPathComponent ?? "-") hoverLink=\(hoverLink) cursor=\(identity)"
                        )
                    }
                }
            }
            queue.append(contentsOf: view.subviews)
        }
    }
}
#endif
