import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowPresentationTransaction {
    private unowned let service: ExtensionOptionsWindowService
    private let receipt: ExtensionOptionsWindowPresentationReceipt
    private let runtime: ExtensionOptionsWindowCallbackRuntime

    init(
        service: ExtensionOptionsWindowService,
        receipt: ExtensionOptionsWindowPresentationReceipt,
        runtime: ExtensionOptionsWindowCallbackRuntime
    ) {
        self.service = service
        self.receipt = receipt
        self.runtime = runtime
    }

    func commit(completionHandler: @escaping (Error?) -> Void) {
        guard runtime.isCurrent(receipt) else {
            completionHandler(CancellationError())
            return
        }

        let webView = WKWebView(
            frame: .zero,
            configuration: receipt.configuration
        )
        var window: NSWindow?
        var registration: ExtensionOptionsWindowReceipt?
        var committed = false
        defer {
            if committed == false {
                if let registration {
                    service.retire(
                        registration,
                        window: window,
                        webView: webView,
                        shouldOrderOut: true
                    )
                } else {
                    SumiAuxiliaryWebViewShutdown.perform(on: webView)
                    window?.orderOut(nil)
                    window?.contentView = nil
                    window?.delegate = nil
                }
            }
        }

        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            webView.isInspectable = true
        }
        webView.allowsBackForwardNavigationGestures = true
        guard runtime.isCurrent(receipt) else {
            completionHandler(CancellationError())
            return
        }
        webView.load(URLRequest(url: receipt.optionsURL))
        guard runtime.isCurrent(receipt) else {
            completionHandler(CancellationError())
            return
        }

        let createdWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window = createdWindow
        createdWindow.title = "\(receipt.displayName) – Options"
        let container = NSView(frame: createdWindow.contentView?.bounds ?? .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        createdWindow.contentView = container
        createdWindow.center()
        guard runtime.isCurrent(receipt) else {
            completionHandler(CancellationError())
            return
        }

        let delegate = ExtensionOptionsWindowDelegate(
            service: service,
            webView: webView,
            window: createdWindow
        )
        webView.uiDelegate = delegate
        createdWindow.delegate = delegate
        guard runtime.isCurrent(receipt) else {
            completionHandler(CancellationError())
            return
        }
        let tracked = service.trackPresentedWindow(
            createdWindow,
            webView: webView,
            delegate: delegate,
            for: receipt.evidence.extensionID,
            profileID: receipt.evidence.profileID
        )
        registration = tracked
        delegate.bind(tracked)
        createdWindow.orderFront(nil)
        guard runtime.isCurrent(receipt) else {
            completionHandler(CancellationError())
            return
        }
        committed = true
        completionHandler(nil)
    }
}
