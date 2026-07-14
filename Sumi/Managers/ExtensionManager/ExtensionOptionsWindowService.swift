import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowService {
    private let registry = ExtensionOptionsWindowRegistry()

    var windows: [String: NSWindow] {
        registry.windows
    }

    var extensionIDs: Set<String> {
        registry.extensionIDs
    }

    func receipt(
        for extensionID: String
    ) -> ExtensionOptionsWindowReceipt? {
        registry.receipt(for: extensionID)
    }

    func closeWindow(for extensionId: String) {
        guard let receipt = receipt(for: extensionId) else { return }
        retire(receipt, shouldOrderOut: true)
    }

    func closeAllWindows() {
        Array(registry.extensionIDs).forEach { extensionID in
            closeWindow(for: extensionID)
        }
    }

    func closeWindows(backedBy profileIDs: Set<UUID>) {
        registry.receipts(backedBy: profileIDs).forEach {
            retire($0, shouldOrderOut: true)
        }
    }

    func retire(
        _ receipt: ExtensionOptionsWindowReceipt,
        window: NSWindow? = nil,
        webView: WKWebView? = nil,
        shouldOrderOut: Bool
    ) {
        guard let registration = registry.retire(receipt) else {
            // A callback from a superseded registration owns only the physical
            // objects carried by that callback. It cannot retire the current
            // registration for the same extension.
            if let webView, registry.owns(webView) == false {
                SumiAuxiliaryWebViewShutdown.perform(on: webView)
            }
            return
        }
        let resolvedWindow = window ?? registration.window
        registration.delegate?.isCleaningUp = true
        let resolvedWebView = webView ?? registration.webView
        if let resolvedWebView {
            SumiAuxiliaryWebViewShutdown.perform(on: resolvedWebView)
        }

        if shouldOrderOut {
            resolvedWindow.orderOut(nil)
        }
        resolvedWindow.contentViewController = nil
        resolvedWindow.contentView = nil
        resolvedWindow.delegate = nil
    }

    func presentOptionsPageWindow(
        invocation: ExtensionOptionsWindowCallbackComposition.Invocation,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let receipt = invocation.receipt
        let runtime = invocation.runtime
        guard runtime.isCurrent(receipt) else {
            completionHandler(CancellationError())
            return
        }
        if runtime.websiteDataMutationAdmissionIsBlocked(
            receipt.evidence.profileID
        ) {
            Task { @MainActor [weak self] in
                guard let self,
                      runtime.isCurrent(receipt),
                      await runtime.waitForWebsiteDataMutationAdmission(
                          receipt.evidence.profileID
                      ),
                      runtime.isCurrent(receipt)
                else {
                    completionHandler(CancellationError())
                    return
                }
                self.presentResolvedOptionsPageWindow(
                    receipt: receipt,
                    runtime: runtime,
                    completionHandler: completionHandler
                )
            }
            return
        }
        presentResolvedOptionsPageWindow(
            receipt: receipt,
            runtime: runtime,
            completionHandler: completionHandler
        )
    }

    private func presentResolvedOptionsPageWindow(
        receipt: ExtensionOptionsWindowPresentationReceipt,
        runtime: ExtensionOptionsWindowCallbackRuntime,
        completionHandler: @escaping (Error?) -> Void
    ) {
        ExtensionOptionsWindowPresentationTransaction(
            service: self,
            receipt: receipt,
            runtime: runtime
        ).commit(completionHandler: completionHandler)
    }

    @discardableResult
    func trackPresentedWindow(
        _ window: NSWindow,
        webView: WKWebView? = nil,
        delegate: ExtensionOptionsWindowDelegate?,
        for extensionId: String,
        profileID: UUID? = nil
    ) -> ExtensionOptionsWindowReceipt {
        let registration = registry.register(
            window: window,
            webView: webView,
            delegate: delegate,
            extensionID: extensionId,
            profileID: profileID
        )
        if let superseded = registration.superseded {
            cleanup(
                superseded,
                preserving: registry.registration(for: extensionId),
                shouldOrderOut: true
            )
        }
        return registration.receipt
    }

    private func cleanup(
        _ registration: ExtensionOptionsWindowRegistry.Registration,
        preserving current: ExtensionOptionsWindowRegistry.Registration?,
        shouldOrderOut: Bool
    ) {
        registration.delegate?.isCleaningUp = true
        if let webView = registration.webView,
           current?.webView !== webView {
            SumiAuxiliaryWebViewShutdown.perform(on: webView)
        }
        guard current?.window !== registration.window else { return }
        if shouldOrderOut {
            registration.window.orderOut(nil)
        }
        registration.window.contentViewController = nil
        registration.window.contentView = nil
        registration.window.delegate = nil
    }
}
