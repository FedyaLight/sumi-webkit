//
//  ExtensionActionPopupAnchorResolutionOwner.swift
//  Sumi
//
//  Owns capture and resolution of extension action popup anchors: pending
//  anchor sessions, live toolbar buttons, and URL-hub fallback anchoring.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupAnchorResolutionOwner {
    private let actionAnchorStore: ExtensionActionAnchorStore
    private let actionPopupAnchorStore: ExtensionActionPopupAnchorStore
    private let browserBridgeContext: @MainActor () -> (any ExtensionBrowserBridgeContext)?
    private let fallbackProfileId: @MainActor () -> UUID?
    private let resolvedProfileId: @MainActor (BrowserWindowState) -> UUID?
    private let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
    private let trace: @MainActor (() -> String) -> Void

    init(
        actionAnchorStore: ExtensionActionAnchorStore,
        actionPopupAnchorStore: ExtensionActionPopupAnchorStore,
        browserBridgeContext: @escaping @MainActor () -> (any ExtensionBrowserBridgeContext)?,
        fallbackProfileId: @escaping @MainActor () -> UUID?,
        resolvedProfileId: @escaping @MainActor (BrowserWindowState) -> UUID?,
        windowMatchesProfile: @escaping @MainActor (BrowserWindowState, UUID) -> Bool,
        trace: @escaping @MainActor (() -> String) -> Void
    ) {
        self.actionAnchorStore = actionAnchorStore
        self.actionPopupAnchorStore = actionPopupAnchorStore
        self.browserBridgeContext = browserBridgeContext
        self.fallbackProfileId = fallbackProfileId
        self.resolvedProfileId = resolvedProfileId
        self.windowMatchesProfile = windowMatchesProfile
        self.trace = trace
    }

    func captureActionPopupAnchor(
        extensionId: String,
        windowId: UUID,
        profileId: UUID?
    ) -> UUID {
        let captureProfileId =
            profileId
            ?? browserBridgeContext()?.extensionWindowState(for: windowId).flatMap {
                resolvedProfileId($0)
            }
            ?? fallbackProfileId()

        guard let captureProfileId else {
            let sessionToken = UUID()
            trace {
                "actionPopupAnchor capture skipped extensionId=\(extensionId) reason=missingProfile"
            }
            return sessionToken
        }

        let buttonView = liveActionAnchorView(
            for: extensionId,
            windowId: windowId
        )
        let validatedRectInWindow = snapshotAnchorRectInWindow(for: buttonView)

        let anchor = ExtensionActionPopupAnchor(
            extensionID: extensionId,
            profileID: captureProfileId,
            windowID: windowId,
            buttonView: buttonView,
            validatedRectInWindow: validatedRectInWindow
        )

        actionPopupAnchorStore.store(anchor)

        trace {
            "actionPopupAnchor captured extensionId=\(extensionId) profileId=\(captureProfileId.uuidString) windowId=\(windowId.uuidString) sessionToken=\(anchor.sessionToken.uuidString) hasButtonView=\(buttonView != nil) hasRect=\(validatedRectInWindow != nil)"
        }
        return anchor.sessionToken
    }

    func resolveActionPopupAnchor(
        for extensionId: String,
        profileId: UUID?,
        preferredWindowId: UUID? = nil
    ) -> (
        anchorView: NSView,
        source: ExtensionActionPopupAnchorSource,
        resolution: ExtensionActionPopupAnchorResolution
    )? {
        let presentationProfileId =
            profileId
            ?? fallbackProfileId()

        var pendingAnchor: ExtensionActionPopupAnchor? =
            actionPopupAnchorStore.latestAnchor(for: extensionId)

        if let staleAnchor = pendingAnchor,
           let presentationProfileId,
           staleAnchor.profileID != presentationProfileId {
            actionPopupAnchorStore.consume(sessionToken: staleAnchor.sessionToken)
            trace {
                "actionPopupAnchor stale session extensionId=\(extensionId) reason=profileMismatch capturedProfile=\(staleAnchor.profileID.uuidString) resolvedProfile=\(presentationProfileId.uuidString)"
            }
            pendingAnchor = nil
        }

        let targetWindow = resolveActionPopupTargetWindow(
            pendingAnchor: pendingAnchor,
            preferredWindowId: preferredWindowId,
            profileId: presentationProfileId
        )
        let targetWindowId = targetWindow?.id
        let targetWindowProfileMatches = presentationProfileId.map { profileId in
            targetWindow.map { windowMatchesProfile($0, profileId) } ?? false
        } ?? true

        if presentationProfileId != nil, targetWindowId == nil {
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: false,
                anchorSource: pendingAnchor == nil ? nil : .stale,
                windowMatch: false,
                profileMatch: false,
                sessionToken: pendingAnchor?.sessionToken
            )
            trace {
                "actionPopupAnchor unresolved extensionId=\(extensionId) reason=profileWindowUnavailable \(resolution.traceLine)"
            }
            return nil
        } else if let pendingAnchor,
                  let buttonView = pendingAnchor.buttonView,
                  isActionPopupAnchorViewReady(buttonView),
                  let window = buttonView.window,
                  let targetWindow,
                  let targetAppKitWindow = browserBridgeContext()?.appKitWindow(for: targetWindow),
                  window === targetAppKitWindow {
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: true,
                anchorSource: .button,
                windowMatch: window === targetAppKitWindow,
                profileMatch: presentationProfileId.map { pendingAnchor.profileID == $0 } ?? true,
                sessionToken: pendingAnchor.sessionToken
            )
            trace {
                "actionPopupAnchor resolved extensionId=\(extensionId) \(resolution.traceLine)"
            }
            return (buttonView, .button, resolution)
        } else if let pendingAnchor,
                  pendingAnchor.buttonView != nil,
                  pendingAnchor.validatedRectInWindow != nil {
            trace {
                "actionPopupAnchor stale session extensionId=\(extensionId) sessionToken=\(pendingAnchor.sessionToken.uuidString)"
            }
        }

        if let targetWindowId,
           let currentView = liveActionAnchorView(for: extensionId, windowId: targetWindowId),
           isActionPopupAnchorViewReady(currentView) {
            let windowMatch =
                currentView.window
                === targetWindow.flatMap({ browserBridgeContext()?.appKitWindow(for: $0) })
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: true,
                anchorSource: .current,
                windowMatch: windowMatch,
                profileMatch: targetWindowProfileMatches,
                sessionToken: pendingAnchor?.sessionToken
            )
            trace {
                "actionPopupAnchor re-resolved extensionId=\(extensionId) \(resolution.traceLine)"
            }
            return (currentView, .current, resolution)
        }

        if let targetWindowId,
           let fallbackView = urlHubFallbackAnchorView(for: targetWindowId),
           isActionPopupAnchorViewReady(fallbackView) {
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: true,
                anchorSource: .fallback,
                windowMatch: true,
                profileMatch: targetWindowProfileMatches,
                sessionToken: pendingAnchor?.sessionToken
            )
            trace {
                "actionPopupAnchor urlHubFallback extensionId=\(extensionId) windowId=\(targetWindowId.uuidString) \(resolution.traceLine)"
            }
            return (fallbackView, .fallback, resolution)
        }

        let resolution = ExtensionActionPopupAnchorResolution(
            anchorResolved: false,
            anchorSource: pendingAnchor == nil ? nil : .stale,
            windowMatch: false,
            profileMatch: presentationProfileId.map {
                pendingAnchor?.profileID == $0
            } ?? false,
            sessionToken: pendingAnchor?.sessionToken
        )
        trace {
            "actionPopupAnchor unresolved extensionId=\(extensionId) \(resolution.traceLine)"
        }
        return nil
    }

    func presentResolvedExtensionActionPopup(
        _ popover: NSPopover,
        for extensionId: String,
        profileId: UUID?,
        preferredWindowId: UUID? = nil
    ) -> ExtensionActionPopupAnchorResolution {
        ExtensionActionPopupPresentationOwner.prepare(popover)

        guard let resolved = resolveActionPopupAnchor(
            for: extensionId,
            profileId: profileId,
            preferredWindowId: preferredWindowId
        ) else {
            return .unresolved
        }

        if let anchorWindow = resolved.anchorView.window,
           let appearance = browserBridgeContext()?.extensionActionPopupAppearance(
               forAnchorWindow: anchorWindow,
               fallback: anchorWindow.effectiveAppearance
           ) {
            popover.appearance = appearance
        }

        ExtensionActionPopupPresentationOwner.show(
            popover,
            relativeTo: resolved.anchorView,
            preferredEdge: .maxY
        )
        actionPopupAnchorStore.consume(
            sessionToken: resolved.resolution.sessionToken
        )
        return resolved.resolution
    }

    private func liveActionAnchorView(
        for extensionId: String,
        windowId: UUID
    ) -> NSView? {
        let targetWindow = browserBridgeContext().flatMap { context in
            context.extensionWindowState(for: windowId).flatMap(context.appKitWindow(for:))
        }
        return actionAnchorStore.liveAnchorView(
            for: extensionId,
            matching: targetWindow,
            isReady: { isActionPopupAnchorViewReady($0) }
        )
    }

    private func urlHubFallbackAnchorView(for windowId: UUID) -> NSView? {
        browserBridgeContext()?.extensionURLHubFallbackAnchorView(for: windowId)
    }

    private func resolveActionPopupTargetWindow(
        pendingAnchor: ExtensionActionPopupAnchor?,
        preferredWindowId: UUID?,
        profileId: UUID?
    ) -> BrowserWindowState? {
        let candidates = [
            pendingAnchor?.windowID,
            preferredWindowId,
            browserBridgeContext()?.activeExtensionWindowState?.id,
        ]
        for candidateId in candidates.compactMap(\.self) {
            guard let windowState = browserBridgeContext()?
                .extensionWindowState(for: candidateId) else {
                continue
            }
            guard profileId.map({ windowMatchesProfile(windowState, $0) }) ?? true else {
                continue
            }
            return windowState
        }
        return nil
    }

    private func isActionPopupAnchorViewReady(_ view: NSView?) -> Bool {
        guard let view else { return false }
        return PopoverPresenterChromeSupport.isAnchorViewReady(
            view,
            checkHiddenAncestors: true
        )
    }

    private func snapshotAnchorRectInWindow(for view: NSView?) -> CGRect? {
        guard let view,
              let window = view.window,
              isActionPopupAnchorViewReady(view)
        else {
            return nil
        }

        let anchorRect = ExtensionActionPopupPresentationOwner.anchorRect(for: view)
        return view.convert(anchorRect, to: window.contentView)
    }
}
