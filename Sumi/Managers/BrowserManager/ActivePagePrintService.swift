import AppKit
import WebKit

/// Runs the AppKit print operation for a web page. The operation is started on
/// the next main-loop turn and attached to the WebView's window when it still
/// has one, so a page torn down between the command and the sheet falls back to
/// a windowless run instead of presenting on a dead window.
@MainActor
enum ActivePagePrintService {
    @discardableResult
    static func print(_ webView: WKWebView) -> Bool {
        let printInfo =
            NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        let operation = webView.printOperation(with: printInfo)
        DispatchQueue.main.async { [weak webView] in
            if let window = webView?.window {
                operation.runModal(
                    for: window,
                    delegate: nil,
                    didRun: nil,
                    contextInfo: nil
                )
            } else {
                operation.run()
            }
        }
        return true
    }
}
