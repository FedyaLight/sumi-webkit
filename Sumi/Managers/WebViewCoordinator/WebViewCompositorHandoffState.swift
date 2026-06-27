import AppKit
import WebKit

@MainActor
final class WebViewCompositorHandoffState {
    private struct WeakNSView { weak var view: NSView? }

    private var containerViews: [UUID: WeakNSView] = [:]
    private var immediateVisualHandoffHandlersByWindow: [UUID: @MainActor () -> Bool] = [:]
    private var promotedHostsByTabAndWindow: [UUID: [UUID: SumiWebViewContainerView]] = [:]
    private var promotedHostAttachmentCompletionsByTabAndWindow: [UUID: [UUID: (@MainActor () -> Void)]] = [:]

    func setContainerView(_ view: NSView?, for windowID: UUID) {
        if let view {
            containerViews[windowID] = WeakNSView(view: view)
        } else {
            containerViews.removeValue(forKey: windowID)
        }
    }

    func setImmediateVisualHandoffHandler(
        _ handler: (@MainActor () -> Bool)?,
        for windowID: UUID
    ) {
        immediateVisualHandoffHandlersByWindow[windowID] = handler
    }

    @discardableResult
    func performImmediateVisualHandoffIfPossible(in windowID: UUID) -> Bool {
        immediateVisualHandoffHandlersByWindow[windowID]?() ?? false
    }

    func containerView(for windowID: UUID) -> NSView? {
        if let view = containerViews[windowID]?.view {
            return view
        }
        containerViews.removeValue(forKey: windowID)
        immediateVisualHandoffHandlersByWindow.removeValue(forKey: windowID)
        return nil
    }

    func removeContainerView(for windowID: UUID) {
        containerViews.removeValue(forKey: windowID)
        immediateVisualHandoffHandlersByWindow.removeValue(forKey: windowID)
    }

    func containerViewsByWindow() -> [(UUID, NSView)] {
        var result: [(UUID, NSView)] = []
        var staleWindowIDs: [UUID] = []
        for (windowID, entry) in containerViews {
            if let view = entry.view {
                result.append((windowID, view))
            } else {
                staleWindowIDs.append(windowID)
            }
        }
        for windowID in staleWindowIDs {
            containerViews.removeValue(forKey: windowID)
            immediateVisualHandoffHandlersByWindow.removeValue(forKey: windowID)
        }
        return result
    }

    func removeAllWindowRegistrations() {
        containerViews.removeAll()
        immediateVisualHandoffHandlersByWindow.removeAll()
    }

    func registerPromotedHost(
        _ host: SumiWebViewContainerView,
        for tabID: UUID,
        in windowID: UUID,
        attachmentCompletion: (@MainActor () -> Void)? = nil
    ) {
        promotedHostsByTabAndWindow[tabID, default: [:]][windowID] = host
        if let attachmentCompletion {
            promotedHostAttachmentCompletionsByTabAndWindow[tabID, default: [:]][windowID] = attachmentCompletion
        } else {
            promotedHostAttachmentCompletionsByTabAndWindow[tabID]?[windowID] = nil
            if promotedHostAttachmentCompletionsByTabAndWindow[tabID]?.isEmpty == true {
                promotedHostAttachmentCompletionsByTabAndWindow[tabID] = nil
            }
        }
    }

    func takePromotedHost(
        for tabID: UUID,
        in windowID: UUID,
        expectedWebView: WKWebView
    ) -> SumiWebViewContainerView? {
        guard let host = promotedHostsByTabAndWindow[tabID]?[windowID] else { return nil }
        guard host.webView === expectedWebView else { return nil }

        promotedHostsByTabAndWindow[tabID]?[windowID] = nil
        if promotedHostsByTabAndWindow[tabID]?.isEmpty == true {
            promotedHostsByTabAndWindow[tabID] = nil
        }

        host.prepareForSuperviewTransferPreservingDisplayedContent()
        return host
    }

    func completePromotedHostAttachment(for tabID: UUID, in windowID: UUID) {
        guard let completion = promotedHostAttachmentCompletionsByTabAndWindow[tabID]?[windowID] else {
            return
        }

        promotedHostAttachmentCompletionsByTabAndWindow[tabID]?[windowID] = nil
        if promotedHostAttachmentCompletionsByTabAndWindow[tabID]?.isEmpty == true {
            promotedHostAttachmentCompletionsByTabAndWindow[tabID] = nil
        }
        completion()
    }
}
