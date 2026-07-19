import AppKit
import Foundation
import WebKit
@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowPresentationTransaction {
    private unowned let service: ExtensionOptionsWindowService
    private let receipt: ExtensionOptionsWindowPresentationReceipt
    private let runtime: ExtensionOptionsWindowCallbackRuntime
    private let claim: ExtensionOptionsWindowPresentationClaim
    init(
        service: ExtensionOptionsWindowService,
        receipt: ExtensionOptionsWindowPresentationReceipt,
        runtime: ExtensionOptionsWindowCallbackRuntime,
        claim: ExtensionOptionsWindowPresentationClaim
    ) {
        self.service = service
        self.receipt = receipt
        self.runtime = runtime
        self.claim = claim
    }
    func commit(completionHandler: @escaping (Error?) -> Void) {
        guard isCurrent else {
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
        let createdWindow = service.makePresentationWindow()
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
        guard isCurrent else {
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
        guard isCurrent else {
            completionHandler(CancellationError())
            return
        }
        guard let tracked = service.trackPresentedWindow(
            createdWindow,
            webView: webView,
            delegate: delegate,
            for: receipt.evidence.extensionID,
            profileID: receipt.evidence.profileID,
            claim: claim
        ) else {
            completionHandler(CancellationError())
            return
        }
        registration = tracked
        guard isCurrent,
              service.receipt(for: receipt.evidence.extensionID) == tracked
        else {
            completionHandler(CancellationError())
            return
        }
        delegate.bind(tracked)
        // Keep the two AppKit operations explicit.  Besides matching the
        // native window lifecycle (order first, then make key), this lets a
        // reentrant close/replacement callback run between the two phases and
        // invalidates the presentation claim before loading can commit.
        createdWindow.orderFront(nil)
        createdWindow.makeKey()
        webView.load(URLRequest(url: receipt.optionsURL))
        guard isCurrent,
              service.receipt(for: receipt.evidence.extensionID) == tracked
        else {
            completionHandler(CancellationError())
            return
        }
        committed = true
        completionHandler(nil)
    }
    private var isCurrent: Bool {
        service.presentationIsCurrent(
            claim,
            receipt: receipt,
            runtime: runtime
        )
    }
}
