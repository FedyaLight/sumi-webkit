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
    struct Dependencies {
        let actionAnchorStore: ExtensionActionAnchorStore
        let actionPopupAnchorStore: ExtensionActionPopupAnchorStore
        let browserBridgeContext: @MainActor () -> (any ExtensionBrowserBridgeContext)?
        let fallbackProfileId: @MainActor () -> UUID?
        let resolvedProfileId: @MainActor (BrowserWindowState) -> UUID?
        let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
        let trace: @MainActor (() -> String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func captureActionPopupAnchor(
        extensionId: String,
        windowId: UUID,
        profileId: UUID?
    ) -> UUID {
        let captureProfileId =
            profileId
            ?? dependencies.browserBridgeContext()?.extensionWindowState(for: windowId).flatMap {
                dependencies.resolvedProfileId($0)
            }
            ?? dependencies.fallbackProfileId()

        guard let captureProfileId else {
            let sessionToken = UUID()
            dependencies.trace {
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

        dependencies.actionPopupAnchorStore.store(anchor)

        dependencies.trace {
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
            ?? dependencies.fallbackProfileId()

        var pendingAnchor: ExtensionActionPopupAnchor? =
            dependencies.actionPopupAnchorStore.latestAnchor(for: extensionId)

        if let staleAnchor = pendingAnchor,
           let presentationProfileId,
           staleAnchor.profileID != presentationProfileId {
            dependencies.actionPopupAnchorStore.consume(sessionToken: staleAnchor.sessionToken)
            dependencies.trace {
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
            targetWindow.map { dependencies.windowMatchesProfile($0, profileId) } ?? false
        } ?? true

        if presentationProfileId != nil, targetWindowId == nil {
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: false,
                anchorSource: pendingAnchor == nil ? nil : .stale,
                windowMatch: false,
                profileMatch: false,
                sessionToken: pendingAnchor?.sessionToken
            )
            dependencies.trace {
                "actionPopupAnchor unresolved extensionId=\(extensionId) reason=profileWindowUnavailable \(resolution.traceLine)"
            }
            return nil
        } else if let pendingAnchor,
                  let buttonView = pendingAnchor.buttonView,
                  isActionPopupAnchorViewReady(buttonView),
                  let window = buttonView.window,
                  let targetWindow,
                  window === targetWindow.window {
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: true,
                anchorSource: .button,
                windowMatch: window === targetWindow.window,
                profileMatch: presentationProfileId.map { pendingAnchor.profileID == $0 } ?? true,
                sessionToken: pendingAnchor.sessionToken
            )
            dependencies.trace {
                "actionPopupAnchor resolved extensionId=\(extensionId) \(resolution.traceLine)"
            }
            return (buttonView, .button, resolution)
        } else if let pendingAnchor,
                  pendingAnchor.buttonView != nil,
                  pendingAnchor.validatedRectInWindow != nil {
            dependencies.trace {
                "actionPopupAnchor stale session extensionId=\(extensionId) sessionToken=\(pendingAnchor.sessionToken.uuidString)"
            }
        }

        if let targetWindowId,
           let currentView = liveActionAnchorView(for: extensionId, windowId: targetWindowId),
           isActionPopupAnchorViewReady(currentView) {
            let windowMatch =
                currentView.window
                === targetWindow?.window
            let resolution = ExtensionActionPopupAnchorResolution(
                anchorResolved: true,
                anchorSource: .current,
                windowMatch: windowMatch,
                profileMatch: targetWindowProfileMatches,
                sessionToken: pendingAnchor?.sessionToken
            )
            dependencies.trace {
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
            dependencies.trace {
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
        dependencies.trace {
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

        ExtensionActionPopupPresentationOwner.show(
            popover,
            relativeTo: resolved.anchorView,
            preferredEdge: .maxY
        )
        dependencies.actionPopupAnchorStore.consume(
            sessionToken: resolved.resolution.sessionToken
        )
        return resolved.resolution
    }

    private func liveActionAnchorView(
        for extensionId: String,
        windowId: UUID
    ) -> NSView? {
        let targetWindow = dependencies.browserBridgeContext()?
            .extensionWindowState(for: windowId)?.window
        return dependencies.actionAnchorStore.liveAnchorView(
            for: extensionId,
            matching: targetWindow,
            isReady: { isActionPopupAnchorViewReady($0) }
        )
    }

    private func urlHubFallbackAnchorView(for windowId: UUID) -> NSView? {
        dependencies.browserBridgeContext()?.extensionURLHubFallbackAnchorView(for: windowId)
    }

    private func resolveActionPopupTargetWindow(
        pendingAnchor: ExtensionActionPopupAnchor?,
        preferredWindowId: UUID?,
        profileId: UUID?
    ) -> BrowserWindowState? {
        let candidates = [
            pendingAnchor?.windowID,
            preferredWindowId,
            dependencies.browserBridgeContext()?.activeExtensionWindowState?.id,
        ]
        for candidateId in candidates.compactMap(\.self) {
            guard let windowState = dependencies.browserBridgeContext()?
                .extensionWindowState(for: candidateId) else {
                continue
            }
            guard profileId.map({ dependencies.windowMatchesProfile(windowState, $0) }) ?? true else {
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

@available(macOS 15.5, *)
extension ExtensionActionPopupAnchorResolutionOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            actionAnchorStore: manager.actionAnchorStore,
            actionPopupAnchorStore: manager.actionPopupAnchorStore,
            browserBridgeContext: { [weak manager] in
                manager?.browserBridgeContext
            },
            fallbackProfileId: { [weak manager] in
                manager?.fallbackProfileId
            },
            resolvedProfileId: { [weak manager] windowState in
                manager?.resolvedProfileId(for: windowState)
            },
            windowMatchesProfile: { [weak manager] windowState, profileId in
                manager?.windowMatchesProfile(windowState, profileId: profileId) ?? false
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message())
            }
        )
    }
}
