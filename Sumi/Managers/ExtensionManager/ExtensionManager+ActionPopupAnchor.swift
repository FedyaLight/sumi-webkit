import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func captureActionPopupAnchor(
        extensionId: String,
        windowId: UUID,
        profileId: UUID?
    ) -> UUID {
        let captureProfileId =
            profileId
            ?? browserBridgeContext?.extensionWindowState(for: windowId).flatMap {
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

        actionPopupAnchorStore.store(anchor)

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
        let presentationProfileId =
            profileId
            ?? currentProfileId
            ?? browserManager?.currentProfile?.id

        let pendingAnchor = actionPopupAnchorStore.latestAnchor(for: extensionId)

        let targetWindowId =
            pendingAnchor?.windowID
            ?? preferredWindowId
            ?? pendingAnchor.flatMap { browserBridgeContext?.extensionWindowState(for: $0.windowID)?.id }
            ?? browserBridgeContext?.activeExtensionWindowState?.id

        if let pendingAnchor,
           let presentationProfileId,
           pendingAnchor.profileID != presentationProfileId
        {
            actionPopupAnchorStore.consume(sessionToken: pendingAnchor.sessionToken)
            extensionRuntimeTrace(
                "actionPopupAnchor stale session extensionId=\(extensionId) reason=profileMismatch capturedProfile=\(pendingAnchor.profileID.uuidString) resolvedProfile=\(presentationProfileId.uuidString)"
            )
        } else if let pendingAnchor,
                  let buttonView = pendingAnchor.buttonView,
                  isActionPopupAnchorViewReady(buttonView),
                  let window = buttonView.window,
                  let targetWindowId,
                  window === browserBridgeContext?.extensionWindowState(for: targetWindowId)?.window
                     || window === NSApp.keyWindow
                     || window === NSApp.mainWindow
        {
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: true,
                anchorSource: .button,
                windowMatch: window === browserBridgeContext?.extensionWindowState(for: pendingAnchor.windowID)?.window,
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
                === browserBridgeContext?.extensionWindowState(for: targetWindowId)?.window
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
        actionPopupAnchorStore.consume(sessionToken: sessionToken)
    }

    func clearActionPopupAnchors(notMatching profileId: UUID) {
        actionPopupAnchorStore.clearAnchors(notMatching: profileId)
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

        let targetWindow = browserBridgeContext?.extensionWindowState(for: windowId)?.window
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
}
