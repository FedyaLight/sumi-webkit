//
//  ExtensionWindowFocusResolutionOwner.swift
//  Sumi
//
//  Owns resolving which browser windows an extension context can see:
//  the focused window, the ordered set of open windows, and the
//  extension-owned mini windows for a given owner extension.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowFocusResolutionOwner {
    private let browserBridgeContext: @MainActor () -> (any ExtensionBrowserBridgeContext)?
    private let profileIdForContext: @MainActor (WKWebExtensionContext) -> UUID?
    private let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?
    private let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
    private let windowAdapter: @MainActor (UUID) -> ExtensionWindowAdapter?
    private let allMiniWindowAdapters: @MainActor () -> [ExtensionMiniWindowAdapter]
    private let resolvedProfileIdForTab: @MainActor (Tab) -> UUID?

    init(
        browserBridgeContext: @escaping @MainActor () -> (any ExtensionBrowserBridgeContext)?,
        profileIdForContext: @escaping @MainActor (WKWebExtensionContext) -> UUID?,
        extensionIDForContext: @escaping @MainActor (WKWebExtensionContext) -> String?,
        windowMatchesProfile: @escaping @MainActor (BrowserWindowState, UUID) -> Bool,
        windowAdapter: @escaping @MainActor (UUID) -> ExtensionWindowAdapter?,
        miniWindowAdapters: @escaping @MainActor () -> [ExtensionMiniWindowAdapter],
        resolvedProfileIdForTab: @escaping @MainActor (Tab) -> UUID?
    ) {
        self.browserBridgeContext = browserBridgeContext
        self.profileIdForContext = profileIdForContext
        self.extensionIDForContext = extensionIDForContext
        self.windowMatchesProfile = windowMatchesProfile
        self.windowAdapter = windowAdapter
        self.allMiniWindowAdapters = miniWindowAdapters
        self.resolvedProfileIdForTab = resolvedProfileIdForTab
    }

    func focusedWindow(
        for extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard let browserContext = browserBridgeContext() else { return nil }
        let contextProfileId = profileIdForContext(extensionContext)
        let ownerExtensionId = extensionIDForContext(extensionContext)
        let ownerMiniWindowAdapters: [ExtensionMiniWindowAdapter] = {
            guard let ownerExtensionId else { return [] }
            return miniWindowAdapters(
                ownerExtensionID: ownerExtensionId,
                profileId: contextProfileId
            )
        }()

        if let keyWindow = NSApp.keyWindow,
           let session = browserContext.auxiliaryWindowSession(for: keyWindow),
           let miniWindowAdapter = session.miniWindowAdapter,
           ownerMiniWindowAdapters.contains(where: { $0.sessionId == miniWindowAdapter.sessionId }) {
            browserContext.recordAuxiliaryWindowSessionFocus(session.id)
            return miniWindowAdapter
        }

        if let miniWindowAdapter = ownerMiniWindowAdapters.first {
            browserContext.recordAuxiliaryWindowSessionFocus(miniWindowAdapter.sessionId)
            return miniWindowAdapter
        }

        if let keyWindow = NSApp.keyWindow,
           let mainWindowState = browserContext.extensionWindowState(forAppKitWindow: keyWindow),
           contextProfileId.map({ windowMatchesProfile(mainWindowState, $0) }) ?? true {
            return windowAdapter(mainWindowState.id)
        }

        if let activeWindow = browserContext.activeExtensionWindowState,
           contextProfileId.map({ windowMatchesProfile(activeWindow, $0) }) ?? true {
            return windowAdapter(activeWindow.id)
        }
        return nil
    }

    func openWindows(
        for extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        guard let browserContext = browserBridgeContext(),
              let contextProfileId = profileIdForContext(extensionContext)
        else { return [] }

        let ownerMiniWindowAdapters: [ExtensionMiniWindowAdapter] = {
            guard let ownerExtensionId = extensionIDForContext(extensionContext) else {
                return []
            }
            return miniWindowAdapters(
                ownerExtensionID: ownerExtensionId,
                profileId: contextProfileId
            )
        }()

        var openWindows: [any WKWebExtensionWindow] = ownerMiniWindowAdapters
        openWindows += browserContext.allExtensionWindowStates.compactMap { windowState -> (any WKWebExtensionWindow)? in
            guard windowMatchesProfile(windowState, contextProfileId) else {
                return nil
            }
            return windowAdapter(windowState.id)
        }

        return openWindows
    }

    func miniWindowAdapters(
        ownerExtensionID: String,
        profileId: UUID?
    ) -> [ExtensionMiniWindowAdapter] {
        guard let browserContext = browserBridgeContext() else { return [] }

        var adapters = allMiniWindowAdapters().compactMap { adapter -> ExtensionMiniWindowAdapter? in
            guard let session = browserContext.auxiliaryWindowSession(for: adapter.sessionId),
                  session.ownerExtensionID == ownerExtensionID,
                  session.window.isVisible,
                  let sessionAdapter = session.miniWindowAdapter,
                  let tab = browserContext.extensionTab(for: sessionAdapter.tabId)
            else {
                return nil
            }
            if let profileId, resolvedProfileIdForTab(tab) != profileId {
                return nil
            }
            return sessionAdapter
        }

        adapters.sort { lhs, rhs in
            lhs.sessionId.uuidString < rhs.sessionId.uuidString
        }

        if let focused = browserContext.focusedExtensionMiniWindowAdapter(
            forOwnerExtensionID: ownerExtensionID
        ),
           let focusedIndex = adapters.firstIndex(where: { $0.sessionId == focused.sessionId }) {
            adapters.insert(adapters.remove(at: focusedIndex), at: 0)
        }

        return adapters
    }
}
