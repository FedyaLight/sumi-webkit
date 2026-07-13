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
        tab: Tab? = nil
    ) -> UUID? {
        let captureProfileId =
            profileId
            ?? windowQuery()?.extensionWindowState(for: windowId).flatMap {
                resolvedProfileId($0)
            }
            ?? fallbackProfileId()

        guard let captureProfileId else {
            trace {
                "actionPopupAnchor capture skipped extensionId=\(extensionId) reason=missingProfile"
            }
            return nil
        }

        guard let windowState = windowQuery()?.extensionWindowState(
                  for: windowId
              ),
              windowMatchesProfile(windowState, captureProfileId),
              tab.map({
                  windowQuery()?.extensionTab(withID: $0.id, in: windowState)
                      === $0
                      && windowQuery()?.currentExtensionTab(in: windowState)
                          === $0
              }) ?? true
        else {
            return nil
        }

        let buttonView = liveActionAnchorView(
            for: extensionId,
            windowId: windowId
        )

        let anchor = ExtensionActionPopupAnchor(
            extensionID: extensionId,
            profileID: captureProfileId,
            windowID: windowId,
            tabID: tab?.id,
            windowState: windowState,
            tab: tab,
            tabProfileAssignmentRevision: tab?.profileAssignment.changeRevision,
            tabDocumentProof: tab?.committedDocumentRuntime.authorityProof,
            buttonView: buttonView
        )

        actionPopupAnchorStore.store(anchor)

        trace {
            "actionPopupAnchor captured extensionId=\(extensionId) profileId=\(captureProfileId.uuidString) windowId=\(windowId.uuidString) tabId=\(tab?.id.uuidString ?? "nil") sessionToken=\(anchor.sessionToken.uuidString) hasButtonView=\(buttonView != nil)"
        }
        return anchor.sessionToken
    }

    func presentResolvedExtensionActionPopup(
        _ popover: NSPopover,
        target: ExtensionActionPopupPresentationTarget,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> ExtensionActionPopupAnchorResolution {
        guard isCurrent() else { return .unresolved }
        let anchor = target.anchor
        guard let resolved = resolveExactTarget(
            target,
            anchor: anchor
        ), isCurrent() else {
            return .unresolved
        }

        let appearance = resolved.anchorView.window.flatMap { anchorWindow in
            windowPresentation()?.extensionActionPopupAppearance(
               forAnchorWindow: anchorWindow,
               fallback: anchorWindow.effectiveAppearance
            )
        }
        guard isCurrent() else { return .unresolved }
        if let appearance {
            popover.appearance = appearance
        }
        guard isCurrent() else { return .unresolved }

        ExtensionActionPopupPresentation.show(
            popover,
            relativeTo: resolved.anchorView,
            preferredEdge: .maxY
        )
        return resolved.resolution
    }

    private func resolveExactTarget(
        _ target: ExtensionActionPopupPresentationTarget,
        anchor: ExtensionActionPopupAnchor?
    ) -> (
        anchorView: NSView,
        source: ExtensionActionPopupAnchorSource,
        resolution: ExtensionActionPopupAnchorResolution
    )? {
        guard let windowState = windowQuery()?.extensionWindowState(
                  for: target.windowID
              ),
              windowState === target.source.windowState,
              windowMatchesProfile(windowState, target.profileID),
              let appKitWindow = windowQuery()?.appKitWindow(for: windowState)
        else {
            return nil
        }

        if let anchor,
           let buttonView = anchor.buttonView,
           isActionPopupAnchorViewReady(buttonView),
           buttonView.window === appKitWindow {
            return (
                buttonView,
                .button,
                .init(
                    anchorResolved: true,
                    anchorSource: .button,
                    windowMatch: true,
                    profileMatch: true,
                    sessionToken: anchor.sessionToken
                )
            )
        }
        if let currentView = liveActionAnchorView(
            for: target.extensionID,
            windowId: target.windowID
        ), currentView.window === appKitWindow {
            return (
                currentView,
                .current,
                .init(
                    anchorResolved: true,
                    anchorSource: .current,
                    windowMatch: true,
                    profileMatch: true,
                    sessionToken: anchor?.sessionToken
                )
            )
        }
        if let fallbackView = urlHubFallbackAnchorView(
            for: target.windowID
        ), fallbackView.window === appKitWindow,
           isActionPopupAnchorViewReady(fallbackView) {
            return (
                fallbackView,
                .fallback,
                .init(
                    anchorResolved: true,
                    anchorSource: .fallback,
                    windowMatch: true,
                    profileMatch: true,
                    sessionToken: anchor?.sessionToken
                )
            )
        }
        return nil
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

    private func isActionPopupAnchorViewReady(_ view: NSView?) -> Bool {
        guard let view else { return false }
        return PopoverPresenterChromeSupport.isAnchorViewReady(
            view,
            checkHiddenAncestors: true
        )
    }

}
