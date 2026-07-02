import Foundation
import WebKit

@MainActor
final class SumiElementZapperSession: NSObject, WKScriptMessageHandler {
    struct Configuration {
        let title: String
        let initialStatus: String
        let selectedStatus: String
        let editedStatus: String
        let createButtonTitle: String
        let timeoutNanoseconds: UInt64

        static let contentBlocker = Configuration(
            title: "Element picker",
            initialStatus: "Click an element to preview, then create the filter.",
            selectedStatus: "Previewing the selected element. Adjust the selector if needed.",
            editedStatus: "Selector edited. Preview it before creating.",
            createButtonTitle: "Create",
            timeoutNanoseconds: 180_000_000_000
        )

        static let boost = Configuration(
            title: "Element picker",
            initialStatus: "Click an element to preview, then zap it.",
            selectedStatus: "Previewing the selected element. Adjust the selector if needed.",
            editedStatus: "Selector edited. Preview it before zapping.",
            createButtonTitle: "Zap",
            timeoutNanoseconds: 180_000_000_000
        )
    }

    private let name = "sumiElementZapper\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private let configuration: Configuration
    private let onSelected: @MainActor (String) -> Void
    private let onCancelled: @MainActor (String) -> Void
    private let onFinish: @MainActor () -> Void
    private var didStart = false
    private var didFinish = false
    private var timeoutTask: Task<Void, Never>?
    private var overlayController: SumiElementZapperOverlayController?

    init(
        webView: WKWebView,
        configuration: Configuration,
        onSelected: @escaping @MainActor (String) -> Void,
        onCancelled: @escaping @MainActor (String) -> Void = { _ in },
        onFinish: @escaping @MainActor () -> Void = {}
    ) {
        self.webView = webView
        self.userContentController = webView.configuration.userContentController
        self.configuration = configuration
        self.onSelected = onSelected
        self.onCancelled = onCancelled
        self.onFinish = onFinish
        super.init()
    }

    func start() async -> Bool {
        guard !didStart, let webView, let userContentController else { return false }
        didStart = true
        userContentController.add(self, contentWorld: .page, name: name)
        installOverlay(in: webView)

        let didInstall = await Self.evaluate(
            SumiElementZapperPageScript.picker(handlerName: name, configuration: configuration),
            in: webView
        )
        guard !didFinish else { return false }
        if didInstall {
            scheduleTimeout()
        } else {
            finish()
        }
        return didInstall
    }

    func stop() {
        stopInPagePicker(reason: "stopped")
        finish()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        guard !didFinish,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }

        switch type {
        case "selected":
            let selector = (body["selector"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !selector.isEmpty else {
                finish()
                return
            }
            onSelected(selector)
            finish()
        case "cancelled":
            let reason = body["reason"] as? String ?? "cancelled"
            onCancelled(reason)
            finish()
        case "state":
            overlayController?.applyState(body)
        default:
            break
        }
    }

    private func scheduleTimeout() {
        let timeoutNanoseconds = configuration.timeoutNanoseconds
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            self?.timeoutIfNeeded()
        }
    }

    private func timeoutIfNeeded() {
        guard !didFinish else { return }
        stopInPagePicker(reason: "timeout")
        finish()
    }

    private func stopInPagePicker(reason: String) {
        guard didStart, let webView else { return }
        webView.evaluateJavaScript(SumiElementZapperPageScript.stop(reason: reason), completionHandler: nil)
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        timeoutTask?.cancel()
        timeoutTask = nil
        overlayController?.remove()
        overlayController = nil
        userContentController?.removeScriptMessageHandler(forName: name, contentWorld: .page)
        onFinish()
    }

    private func installOverlay(in webView: WKWebView) {
        let overlayController = SumiElementZapperOverlayController(
            configuration: configuration,
            onCommand: { [weak self] command in
                self?.sendCommand(command)
            }
        )
        overlayController.install(in: webView)
        self.overlayController = overlayController
    }

    private func sendCommand(_ command: SumiElementZapperOverlayCommand) {
        guard !didFinish, let webView else { return }
        let payload = PageCommand(command)
        let commandLiteral = SumiElementZapperPageScript.jsonLiteral(payload)
        let script = #"""
        (() => {
            if (window.__sumiElementZapper && window.__sumiElementZapper.command) {
                window.__sumiElementZapper.command(\#(commandLiteral));
            }
        })();
        """#
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private struct PageCommand: Encodable {
        let type: String
        let selector: String?

        init(_ command: SumiElementZapperOverlayCommand) {
            switch command {
            case .setSelector(let selector):
                self.type = "setSelector"
                self.selector = selector
            case .togglePreview:
                self.type = "togglePreview"
                self.selector = nil
            case .create:
                self.type = "create"
                self.selector = nil
            case .cancel:
                self.type = "cancel"
                self.selector = nil
            case .selectParent:
                self.type = "selectParent"
                self.selector = nil
            case .selectChild:
                self.type = "selectChild"
                self.selector = nil
            }
        }
    }

    private static func evaluate(_ script: String, in webView: WKWebView) async -> Bool {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }
}
