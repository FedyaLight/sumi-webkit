//
//  WebViewCompositorHandoffState.swift
//  SumiWebRuntime
//
//  Owns compositor container registration and Glance promoted-host handoff.
//  Hosts are typed as WebRuntimePromotedHost so the package never edges the
//  app-target SumiWebViewContainerView.
//

import AppKit
import Foundation
import WebKit

@MainActor
public final class WebViewCompositorHandoffState {
    private struct WeakNSView { weak var view: NSView? }

    private var containerViews: [UUID: WeakNSView] = [:]
    private var immediateVisualHandoffHandlersByWindow: [UUID: @MainActor () -> Bool] = [:]
    private var promotedHostsByTabAndWindow: [UUID: [UUID: any WebRuntimePromotedHost]] = [:]
    private var promotedHostAttachmentCompletionsByTabAndWindow: [UUID: [UUID: @MainActor () -> Void]] = [:]

    public init() {}

    public func setContainerView(_ view: NSView?, for windowID: UUID) {
        if let view {
            containerViews[windowID] = WeakNSView(view: view)
        } else {
            containerViews.removeValue(forKey: windowID)
        }
    }

    public func setImmediateVisualHandoffHandler(
        _ handler: (@MainActor () -> Bool)?,
        for windowID: UUID
    ) {
        immediateVisualHandoffHandlersByWindow[windowID] = handler
    }

    @discardableResult
    public func performImmediateVisualHandoffIfPossible(in windowID: UUID) -> Bool {
        immediateVisualHandoffHandlersByWindow[windowID]?() ?? false
    }

    public func containerView(for windowID: UUID) -> NSView? {
        if let view = containerViews[windowID]?.view {
            return view
        }
        containerViews.removeValue(forKey: windowID)
        immediateVisualHandoffHandlersByWindow.removeValue(forKey: windowID)
        return nil
    }

    public func removeContainerView(for windowID: UUID) {
        containerViews.removeValue(forKey: windowID)
        immediateVisualHandoffHandlersByWindow.removeValue(forKey: windowID)
    }

    public func containerViewsByWindow() -> [(UUID, NSView)] {
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

    public func removeAllWindowRegistrations() {
        containerViews.removeAll()
        immediateVisualHandoffHandlersByWindow.removeAll()
    }

    public func registerPromotedHost(
        _ host: any WebRuntimePromotedHost,
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

    public func takePromotedHost(
        for tabID: UUID,
        in windowID: UUID,
        expectedWebView: WKWebView
    ) -> (any WebRuntimePromotedHost)? {
        guard let host = promotedHostsByTabAndWindow[tabID]?[windowID] else { return nil }
        guard host.webView === expectedWebView else { return nil }

        promotedHostsByTabAndWindow[tabID]?[windowID] = nil
        if promotedHostsByTabAndWindow[tabID]?.isEmpty == true {
            promotedHostsByTabAndWindow[tabID] = nil
        }

        host.prepareForSuperviewTransferPreservingDisplayedContent()
        return host
    }

    public func completePromotedHostAttachment(for tabID: UUID, in windowID: UUID) {
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
