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

/// Terminal result of a promoted-host compositor handoff.
///
/// A completion is resolved exactly once. `attached` means the compositor took
/// and installed the registered host. `cancelled` means the pending handoff was
/// invalidated before attachment (replacement, stale/removed window, or global
/// runtime teardown).
public enum PromotedHostAttachmentOutcome: Sendable, Equatable {
    case attached
    case cancelled
}

public typealias PromotedHostAttachmentCompletion =
    @MainActor (PromotedHostAttachmentOutcome) -> Void

/// Identity lease for one compositor-container installation.
///
/// A later installation for the same window supersedes this lease. Conditional
/// teardown with the stale lease then becomes a no-op instead of unregistering
/// the replacement controller's container and handoff handler.
public struct WebViewCompositorContainerRegistration: Hashable, Sendable {
    public let windowID: UUID
    fileprivate let id: UUID

    fileprivate init(windowID: UUID) {
        self.windowID = windowID
        self.id = UUID()
    }
}

@MainActor
public final class WebViewCompositorHandoffState {
    private struct ContainerRegistrationRecord {
        let registration: WebViewCompositorContainerRegistration
        weak var view: NSView?
        let immediateVisualHandoffHandler: (@MainActor () -> Bool)?
    }

    private struct PromotionKey: Hashable {
        let tabID: UUID
        let windowID: UUID
    }

    private struct PendingPromotion {
        var host: (any WebRuntimePromotedHost)?
        let containerRegistration: WebViewCompositorContainerRegistration
        let attachmentCompletion: PromotedHostAttachmentCompletion?
    }

    private var containerRegistrationsByWindow: [UUID: ContainerRegistrationRecord] = [:]
    private var pendingPromotions: [PromotionKey: PendingPromotion] = [:]

    public init() {}

    @discardableResult
    public func registerContainerView(
        _ view: NSView,
        for windowID: UUID,
        immediateVisualHandoffHandler: (@MainActor () -> Bool)? = nil
    ) -> WebViewCompositorContainerRegistration {
        let registration = WebViewCompositorContainerRegistration(windowID: windowID)
        let previous = containerRegistrationsByWindow.updateValue(
            ContainerRegistrationRecord(
                registration: registration,
                view: view,
                immediateVisualHandoffHandler: immediateVisualHandoffHandler
            ),
            forKey: windowID
        )
        if previous != nil {
            finishAndRemovePromotions(in: windowID)
        }
        return registration
    }

    @discardableResult
    public func performImmediateVisualHandoffIfPossible(in windowID: UUID) -> Bool {
        guard containerView(for: windowID) != nil else { return false }
        return containerRegistrationsByWindow[windowID]?
            .immediateVisualHandoffHandler?() ?? false
    }

    public func containerView(for windowID: UUID) -> NSView? {
        guard let record = containerRegistrationsByWindow[windowID] else {
            return nil
        }
        if let view = record.view {
            return view
        }
        _ = removeContainerView(record.registration)
        return nil
    }

    public func removeContainerView(for windowID: UUID) {
        containerRegistrationsByWindow.removeValue(forKey: windowID)
        finishAndRemovePromotions(in: windowID)
    }

    public func isCurrentContainerRegistration(
        _ registration: WebViewCompositorContainerRegistration
    ) -> Bool {
        containerRegistrationsByWindow[registration.windowID]?.registration == registration
    }

    @discardableResult
    public func removeContainerView(
        _ registration: WebViewCompositorContainerRegistration
    ) -> Bool {
        guard isCurrentContainerRegistration(registration) else { return false }

        containerRegistrationsByWindow.removeValue(forKey: registration.windowID)
        finishAndRemovePromotions(in: registration.windowID)
        return true
    }

    public func containerViewsByWindow() -> [(UUID, NSView)] {
        var result: [(UUID, NSView)] = []
        var staleRegistrations: [WebViewCompositorContainerRegistration] = []
        for (windowID, record) in containerRegistrationsByWindow {
            if let view = record.view {
                result.append((windowID, view))
            } else {
                staleRegistrations.append(record.registration)
            }
        }
        for registration in staleRegistrations {
            _ = removeContainerView(registration)
        }
        return result
    }

    public func removeAllWindowRegistrations() {
        containerRegistrationsByWindow.removeAll()
        let completions = pendingPromotions.values.compactMap(\.attachmentCompletion)
        pendingPromotions.removeAll()
        completions.forEach { $0(.cancelled) }
    }

    @discardableResult
    public func registerPromotedHost(
        _ host: any WebRuntimePromotedHost,
        for tabID: UUID,
        in windowID: UUID,
        attachmentCompletion: PromotedHostAttachmentCompletion? = nil
    ) -> Bool {
        guard containerView(for: windowID) != nil,
              let containerRegistration = containerRegistrationsByWindow[windowID]?.registration
        else { return false }

        let key = PromotionKey(tabID: tabID, windowID: windowID)
        let previous = pendingPromotions.updateValue(
            PendingPromotion(
                host: host,
                containerRegistration: containerRegistration,
                attachmentCompletion: attachmentCompletion
            ),
            forKey: key
        )
        previous?.attachmentCompletion?(.cancelled)
        return true
    }

    public func takePromotedHost(
        for tabID: UUID,
        in windowID: UUID,
        containerRegistration: WebViewCompositorContainerRegistration,
        expectedWebView: WKWebView
    ) -> (any WebRuntimePromotedHost)? {
        let key = PromotionKey(tabID: tabID, windowID: windowID)
        guard var promotion = pendingPromotions[key],
              containerRegistration.windowID == windowID,
              isCurrentContainerRegistration(containerRegistration),
              promotion.containerRegistration == containerRegistration,
              let host = promotion.host
        else { return nil }
        guard host.webView === expectedWebView else { return nil }

        promotion.host = nil
        if promotion.attachmentCompletion == nil {
            pendingPromotions.removeValue(forKey: key)
        } else {
            pendingPromotions[key] = promotion
        }

        host.prepareForSuperviewTransferPreservingDisplayedContent()
        return host
    }

    public func completePromotedHostAttachment(
        for tabID: UUID,
        in windowID: UUID,
        containerRegistration: WebViewCompositorContainerRegistration
    ) {
        let key = PromotionKey(tabID: tabID, windowID: windowID)
        guard let promotion = pendingPromotions[key],
              containerRegistration.windowID == windowID,
              isCurrentContainerRegistration(containerRegistration),
              promotion.containerRegistration == containerRegistration,
              promotion.host == nil
        else { return }

        pendingPromotions.removeValue(forKey: key)
        promotion.attachmentCompletion?(.attached)
    }

    private func finishAndRemovePromotions(in windowID: UUID) {
        let keys = pendingPromotions.keys.filter { $0.windowID == windowID }
        let completions = keys.compactMap { key in
            pendingPromotions.removeValue(forKey: key)?.attachmentCompletion
        }
        completions.forEach { $0(.cancelled) }
    }
}
