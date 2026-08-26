import WebKit

@MainActor
final class WebInspectorService {
    private let isEnabled: @MainActor () -> Bool
    private let openInspector: @MainActor (WKWebView) -> Bool

    init(
        isEnabled: @escaping @MainActor () -> Bool = {
            RuntimeDiagnostics.isDeveloperInspectionEnabled
        },
        openInspector: @escaping @MainActor (WKWebView) -> Bool = {
            WebInspectorService.openInspector($0)
        }
    ) {
        self.isEnabled = isEnabled
        self.openInspector = openInspector
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
        return openInspector(webView)
    }

    private static func openInspector(_ webView: WKWebView) -> Bool {
        let inspectorSelector = NSSelectorFromString("_inspector")
        let showSelector = NSSelectorFromString("show")
        guard
            let inspector = webView.perform(inspectorSelector)?.takeUnretainedValue() as? NSObject,
            inspector.responds(to: showSelector)
        else {
            RuntimeDiagnostics.emit("Web Inspector is unavailable for this WebKit runtime.")
            return false
        }
        inspector.perform(showSelector)
        return true
    }
}
