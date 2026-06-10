import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    private static let actionPopupAnchorSessionTTL: TimeInterval = 30
    private static let maxPendingActionPopupAnchors = 16

    func captureActionPopupAnchor(
        extensionId: String,
        windowId: UUID,
        profileId: UUID?
    ) -> UUID {
        pruneExpiredActionPopupAnchors()

        let captureProfileId =
            profileId
            ?? browserManager?.windowRegistry?.windows[windowId].flatMap {
                self.resolvedProfileId(for: $0)
            }
            ?? currentProfileId
            ?? browserManager?.currentProfile?.id

        guard let captureProfileId else {
            let sessionToken = UUID()
            extensionRuntimeTrace(
                "actionPopupAnchor capture skipped extensionId=\(extensionId) reason=missingProfile"
            )
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

        pendingActionPopupAnchors[anchor.sessionToken] = anchor
        latestActionPopupAnchorSessionByExtensionID[extensionId] = anchor.sessionToken
        enforcePendingActionPopupAnchorLimit()

        extensionRuntimeTrace(
            "actionPopupAnchor captured extensionId=\(extensionId) profileId=\(captureProfileId.uuidString) windowId=\(windowId.uuidString) sessionToken=\(anchor.sessionToken.uuidString) hasButtonView=\(buttonView != nil) hasRect=\(validatedRectInWindow != nil)"
        )
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
        pruneExpiredActionPopupAnchors()

        let presentationProfileId =
            profileId
            ?? currentProfileId
            ?? browserManager?.currentProfile?.id

        let sessionToken = latestActionPopupAnchorSessionByExtensionID[extensionId]
        let pendingAnchor = sessionToken.flatMap { pendingActionPopupAnchors[$0] }

        let targetWindowId =
            pendingAnchor?.windowID
            ?? preferredWindowId
            ?? pendingAnchor.flatMap { browserManager?.windowRegistry?.windows[$0.windowID]?.id }
            ?? browserManager?.windowRegistry?.activeWindow?.id

        if let pendingAnchor,
           let presentationProfileId,
           pendingAnchor.profileID != presentationProfileId
        {
            clearPendingActionPopupAnchor(sessionToken: pendingAnchor.sessionToken)
            extensionRuntimeTrace(
                "actionPopupAnchor stale session extensionId=\(extensionId) reason=profileMismatch capturedProfile=\(pendingAnchor.profileID.uuidString) resolvedProfile=\(presentationProfileId.uuidString)"
            )
        } else if let pendingAnchor,
                  let buttonView = pendingAnchor.buttonView,
                  isActionPopupAnchorViewReady(buttonView),
                  let window = buttonView.window,
                  let targetWindowId,
                  window === browserManager?.windowRegistry?.windows[targetWindowId]?.window
                     || window === NSApp.keyWindow
                     || window === NSApp.mainWindow
        {
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: true,
                anchorSource: .button,
                windowMatch: window === browserManager?.windowRegistry?.windows[pendingAnchor.windowID]?.window,
                profileMatch: presentationProfileId.map { pendingAnchor.profileID == $0 } ?? true,
                sessionToken: pendingAnchor.sessionToken
            )
            extensionRuntimeTrace(
                "actionPopupAnchor resolved extensionId=\(extensionId) \(resolution.traceLine)"
            )
            return (buttonView, .button, resolution)
        } else if let pendingAnchor,
                  pendingAnchor.buttonView != nil,
                  pendingAnchor.validatedRectInWindow != nil
        {
            extensionRuntimeTrace(
                "actionPopupAnchor stale session extensionId=\(extensionId) sessionToken=\(pendingAnchor.sessionToken.uuidString)"
            )
        }

        if let targetWindowId,
           let currentView = liveActionAnchorView(for: extensionId, windowId: targetWindowId),
           isActionPopupAnchorViewReady(currentView)
        {
            let windowMatch =
                currentView.window
                === browserManager?.windowRegistry?.windows[targetWindowId]?.window
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: true,
                anchorSource: .current,
                windowMatch: windowMatch,
                profileMatch: presentationProfileId.map {
                    pendingAnchor?.profileID == $0
                } ?? true,
                sessionToken: pendingAnchor?.sessionToken
            )
            extensionRuntimeTrace(
                "actionPopupAnchor re-resolved extensionId=\(extensionId) \(resolution.traceLine)"
            )
            return (currentView, .current, resolution)
        }

        if let targetWindowId,
           let fallbackView = urlHubFallbackAnchorView(for: targetWindowId),
           isActionPopupAnchorViewReady(fallbackView)
        {
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: true,
                anchorSource: .fallback,
                windowMatch: true,
                profileMatch: presentationProfileId.map {
                    pendingAnchor?.profileID == $0
                } ?? true,
                sessionToken: pendingAnchor?.sessionToken
            )
            extensionRuntimeTrace(
                "actionPopupAnchor urlHubFallback extensionId=\(extensionId) windowId=\(targetWindowId.uuidString) \(resolution.traceLine)"
            )
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
        extensionRuntimeTrace(
            "actionPopupAnchor unresolved extensionId=\(extensionId) \(resolution.traceLine)"
        )
        return nil
    }

    func consumePendingActionPopupAnchor(sessionToken: UUID?) {
        guard let sessionToken else { return }
        clearPendingActionPopupAnchor(sessionToken: sessionToken)
    }

    func clearActionPopupAnchors(notMatching profileId: UUID) {
        let staleTokens = pendingActionPopupAnchors.compactMap { token, anchor in
            anchor.profileID == profileId ? nil : token
        }
        for token in staleTokens {
            clearPendingActionPopupAnchor(sessionToken: token)
        }
    }

    func presentResolvedExtensionActionPopup(
        _ popover: NSPopover,
        for extensionId: String,
        profileId: UUID?,
        preferredWindowId: UUID? = nil
    ) -> ExtensionActionPopupAnchorResolution {
        prepareExtensionActionPopupPresentation(popover)

        guard let resolved = resolveActionPopupAnchor(
            for: extensionId,
            profileId: profileId,
            preferredWindowId: preferredWindowId
        ) else {
            return .unresolved
        }

        showExtensionActionPopup(
            popover,
            relativeTo: resolved.anchorView,
            preferredEdge: .maxY
        )
        consumePendingActionPopupAnchor(
            sessionToken: resolved.resolution.sessionToken
        )
        return resolved.resolution
    }

    private func liveActionAnchorView(
        for extensionId: String,
        windowId: UUID
    ) -> NSView? {
        guard var anchors = actionAnchors[extensionId] else { return nil }
        anchors.removeAll { $0.view == nil || $0.view?.window == nil }
        actionAnchors[extensionId] = anchors.isEmpty ? nil : anchors

        let targetWindow = browserManager?.windowRegistry?.windows[windowId]?.window
        if let targetWindow,
           let match = anchors.first(where: {
               $0.window === targetWindow && isActionPopupAnchorViewReady($0.view)
           }),
           let view = match.view
        {
            return view
        }

        return anchors.first(where: {
            isActionPopupAnchorViewReady($0.view)
        })?.view
    }

    private func urlHubFallbackAnchorView(for windowId: UUID) -> NSView? {
        browserManager?.urlBarHubPopoverPresenter.anchorView(for: windowId)
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

        let anchorRect = extensionActionPopupAnchorRect(for: view)
        return view.convert(anchorRect, to: window.contentView)
    }

    private func pruneExpiredActionPopupAnchors() {
        let now = Date()
        let expiredTokens = pendingActionPopupAnchors.compactMap { token, anchor -> UUID? in
            now.timeIntervalSince(anchor.capturedAt) > Self.actionPopupAnchorSessionTTL
                ? token
                : nil
        }
        for token in expiredTokens {
            clearPendingActionPopupAnchor(sessionToken: token)
        }
    }

    private func clearPendingActionPopupAnchor(sessionToken: UUID) {
        guard let anchor = pendingActionPopupAnchors.removeValue(forKey: sessionToken) else {
            return
        }
        if latestActionPopupAnchorSessionByExtensionID[anchor.extensionID] == sessionToken {
            latestActionPopupAnchorSessionByExtensionID.removeValue(forKey: anchor.extensionID)
        }
    }

    private func enforcePendingActionPopupAnchorLimit() {
        guard pendingActionPopupAnchors.count > Self.maxPendingActionPopupAnchors else {
            return
        }

        let sortedTokens = pendingActionPopupAnchors.values
            .sorted { $0.capturedAt < $1.capturedAt }
            .map(\.sessionToken)

        let overflow = pendingActionPopupAnchors.count - Self.maxPendingActionPopupAnchors
        for token in sortedTokens.prefix(overflow) {
            clearPendingActionPopupAnchor(sessionToken: token)
        }
    }
}
