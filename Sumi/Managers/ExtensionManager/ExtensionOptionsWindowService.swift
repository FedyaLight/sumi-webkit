import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowService {
    typealias WindowFactory = @MainActor () -> NSWindow

    private let registry = ExtensionOptionsWindowRegistry()
    private let windowFactory: WindowFactory
    init(
        windowFactory: @escaping WindowFactory = {
            NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
        }
    ) {
        self.windowFactory = windowFactory
    }
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
        guard let receipt = receipt(for: extensionId) else {
            registry.invalidatePresentationClaim(for: extensionId)
            return
        }
        retire(receipt, shouldOrderOut: true)
    }
    func closeAllWindows() {
        registry.invalidateAllPresentationClaims()
        Array(registry.extensionIDs).forEach { extensionID in
            closeWindow(for: extensionID)
        }
    }
    func closeWindows(backedBy profileIDs: Set<UUID>) {
        registry.invalidatePresentationClaims(backedBy: profileIDs)
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
            if let window, registry.owns(window) == false {
                if shouldOrderOut {
                    window.orderOut(nil)
                }
                window.contentViewController = nil
                window.contentView = nil
                window.delegate = nil
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
        ExtensionOptionsWindowPresentationCoordinator.present(
            service: self,
            invocation: invocation,
            completionHandler: completionHandler
        )
    }

    func issuePresentationClaim(
        for extensionID: String,
        profileID: UUID?
    ) -> ExtensionOptionsWindowPresentationClaim {
        registry.issuePresentationClaim(
            for: extensionID,
            profileID: profileID
        )
    }

    func presentationIsCurrent(
        _ claim: ExtensionOptionsWindowPresentationClaim,
        receipt: ExtensionOptionsWindowPresentationReceipt,
        runtime: ExtensionOptionsWindowCallbackRuntime
    ) -> Bool {
        registry.isCurrent(claim) && runtime.isCurrent(receipt)
    }

    func makePresentationWindow() -> NSWindow {
        windowFactory()
    }

    @discardableResult
    func trackPresentedWindow(
        _ window: NSWindow,
        webView: WKWebView? = nil,
        delegate: ExtensionOptionsWindowDelegate?,
        for extensionId: String,
        profileID: UUID? = nil
    ) -> ExtensionOptionsWindowReceipt {
        let claim = issuePresentationClaim(
            for: extensionId,
            profileID: profileID
        )
        guard let receipt = trackPresentedWindow(
            window,
            webView: webView,
            delegate: delegate,
            for: extensionId,
            profileID: profileID,
            claim: claim
        ) else {
            preconditionFailure("Fresh options presentation claim was rejected")
        }
        return receipt
    }

    @discardableResult
    func trackPresentedWindow(
        _ window: NSWindow,
        webView: WKWebView? = nil,
        delegate: ExtensionOptionsWindowDelegate?,
        for extensionId: String,
        profileID: UUID? = nil,
        claim: ExtensionOptionsWindowPresentationClaim
    ) -> ExtensionOptionsWindowReceipt? {
        guard let registration = registry.register(
            window: window,
            webView: webView,
            delegate: delegate,
            extensionID: extensionId,
            profileID: profileID,
            claim: claim
        ) else { return nil }
        if let superseded = registration.superseded {
            cleanup(superseded, shouldOrderOut: true)
        }
        return registration.receipt
    }

    private func cleanup(
        _ registration: ExtensionOptionsWindowRegistry.Registration,
        shouldOrderOut: Bool
    ) {
        registration.delegate?.isCleaningUp = true
        if let webView = registration.webView,
           registry.owns(webView) == false {
            SumiAuxiliaryWebViewShutdown.perform(on: webView)
        }
        guard registry.owns(registration.window) == false else { return }
        if shouldOrderOut {
            registration.window.orderOut(nil)
        }
        registration.window.contentViewController = nil
        registration.window.contentView = nil
        registration.window.delegate = nil
    }
}
