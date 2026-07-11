//
//  ExtensionActionPopupAnchorResolver.swift
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
final class ExtensionActionPopupAnchorResolver {
    private let actionAnchorStore: ExtensionActionAnchorStore
    private let actionPopupAnchorStore: ExtensionActionPopupAnchorStore
    private let windowQuery: @MainActor () -> (any ExtensionWindowQuery)?
    private let windowPresentation:
        @MainActor () -> (any ExtensionWindowPresentation)?
    private let fallbackProfileId: @MainActor () -> UUID?
    private let resolvedProfileId: @MainActor (BrowserWindowState) -> UUID?
    private let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
    private let trace: @MainActor (() -> String) -> Void

    init(
        actionAnchorStore: ExtensionActionAnchorStore,
        actionPopupAnchorStore: ExtensionActionPopupAnchorStore,
        windowQuery: @escaping @MainActor () -> (any ExtensionWindowQuery)?,
        windowPresentation:
            @escaping @MainActor () -> (any ExtensionWindowPresentation)?,
        fallbackProfileId: @escaping @MainActor () -> UUID?,
        resolvedProfileId: @escaping @MainActor (BrowserWindowState) -> UUID?,
        windowMatchesProfile: @escaping @MainActor (BrowserWindowState, UUID) -> Bool,
        trace: @escaping @MainActor (() -> String) -> Void
    ) {
        self.actionAnchorStore = actionAnchorStore
        self.actionPopupAnchorStore = actionPopupAnchorStore
        self.windowQuery = windowQuery
        self.windowPresentation = windowPresentation
        self.fallbackProfileId = fallbackProfileId
        self.resolvedProfileId = resolvedProfileId
        self.windowMatchesProfile = windowMatchesProfile
        self.trace = trace
    }

    func captureActionPopupAnchor(
        extensionId: String,
        windowId: UUID,
        profileId: UUID?,
        tabId: UUID? = nil
    ) -> UUID {
        let captureProfileId =
            profileId
            ?? windowQuery()?.extensionWindowState(for: windowId).flatMap {
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
            tabID: tabId,
            buttonView: buttonView,
            validatedRectInWindow: validatedRectInWindow
        )

        actionPopupAnchorStore.store(anchor)

        trace {
            "actionPopupAnchor captured extensionId=\(extensionId) profileId=\(captureProfileId.uuidString) windowId=\(windowId.uuidString) tabId=\(tabId?.uuidString ?? "nil") sessionToken=\(anchor.sessionToken.uuidString) hasButtonView=\(buttonView != nil) hasRect=\(validatedRectInWindow != nil)"
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
                  let targetAppKitWindow = windowQuery()?.appKitWindow(for: targetWindow),
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
                === targetWindow.flatMap({ windowQuery()?.appKitWindow(for: $0) })
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
        ExtensionActionPopupPresentation.prepare(popover)

        guard let resolved = resolveActionPopupAnchor(
            for: extensionId,
            profileId: profileId,
            preferredWindowId: preferredWindowId
        ) else {
            return .unresolved
        }

        if let anchorWindow = resolved.anchorView.window,
           let appearance = windowPresentation()?.extensionActionPopupAppearance(
               forAnchorWindow: anchorWindow,
               fallback: anchorWindow.effectiveAppearance
           ) {
            popover.appearance = appearance
        }

        ExtensionActionPopupPresentation.show(
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
        let targetWindow = windowQuery().flatMap { query in
            query.extensionWindowState(for: windowId).flatMap(
                query.appKitWindow(for:)
            )
        }
        return actionAnchorStore.liveAnchorView(
            for: extensionId,
            matching: targetWindow,
            isReady: { isActionPopupAnchorViewReady($0) }
        )
    }

    private func urlHubFallbackAnchorView(for windowId: UUID) -> NSView? {
        windowPresentation()?.extensionURLHubFallbackAnchorView(for: windowId)
    }

    private func resolveActionPopupTargetWindow(
        pendingAnchor: ExtensionActionPopupAnchor?,
        preferredWindowId: UUID?,
        profileId: UUID?
    ) -> BrowserWindowState? {
        let candidates = [
            pendingAnchor?.windowID,
            preferredWindowId,
            windowQuery()?.activeExtensionWindowState?.id,
        ]
        for candidateId in candidates.compactMap(\.self) {
            guard let windowState = windowQuery()?
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

        let anchorRect = ExtensionActionPopupPresentation.anchorRect(for: view)
        return view.convert(anchorRect, to: window.contentView)
    }
}

@available(macOS 15.5, *)
extension ExtensionActionPopupAnchorResolver {
    convenience init(manager: ExtensionManager) {
        self.init(
            actionAnchorStore: manager.actionAnchorStore,
            actionPopupAnchorStore: manager.actionPopupAnchorStore,
            windowQuery: { [weak manager] in
                manager?.extensionWindowQuery
            },
            windowPresentation: { [weak manager] in
                manager?.extensionWindowPresentation
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
                manager?.runtimeDiagnostics.trace(message())
            }
        )
    }
}
