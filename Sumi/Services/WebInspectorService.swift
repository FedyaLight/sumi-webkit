import AppKit
import WebKit

@MainActor
final class WebInspectorService {
    private let isEnabled: @MainActor () -> Bool
    private let presentInstructions: @MainActor () -> Void

    init(
        isEnabled: @escaping @MainActor () -> Bool = {
            RuntimeDiagnostics.isDeveloperInspectionEnabled
        },
        presentInstructions: @escaping @MainActor () -> Void = {
            let alert = NSAlert()
            alert.messageText = "Open Web Inspector"
            alert.informativeText = "To open the Web Inspector:\n\n"
                + "1. Right-click on the page and select 'Inspect Element'\n\n"
                + "Or enable the Develop menu in Safari Settings → Advanced, then use Develop → [Your App]"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    ) {
        self.isEnabled = isEnabled
        self.presentInstructions = presentInstructions
    }

    var canInspect: Bool {
        isEnabled()
    }

    @discardableResult
    func inspect(_ webView: WKWebView) -> Bool {
        guard canInspect else {
            RuntimeDiagnostics.emit("Developer inspection is disabled for this runtime.")
            return false
        }
        webView.isInspectable = true
        presentInstructions()
        return true
    }
}
