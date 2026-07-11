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
    private let windowQuery: @MainActor () -> (any ExtensionWindowQuery)?
    private let tabQuery: @MainActor () -> (any ExtensionTabQuery)?
    private let auxiliaryWindows:
        @MainActor () -> (any ExtensionAuxiliaryWindowControl)?
    private let profileIdForContext: @MainActor (WKWebExtensionContext) -> UUID?
    private let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?
    private let publishedWindowAdapter: @MainActor (
        BrowserWindowState,
        UUID
    ) -> ExtensionWindowAdapter?
    private let allMiniWindowAdapters: @MainActor () -> [ExtensionMiniWindowAdapter]
    private let resolvedProfileIdForTab: @MainActor (Tab) -> UUID?

    init(
        windowQuery: @escaping @MainActor () -> (any ExtensionWindowQuery)?,
        tabQuery: @escaping @MainActor () -> (any ExtensionTabQuery)?,
        auxiliaryWindows:
            @escaping @MainActor () -> (any ExtensionAuxiliaryWindowControl)?,
        profileIdForContext: @escaping @MainActor (WKWebExtensionContext) -> UUID?,
        extensionIDForContext: @escaping @MainActor (WKWebExtensionContext) -> String?,
        publishedWindowAdapter: @escaping @MainActor (
            BrowserWindowState,
            UUID
        ) -> ExtensionWindowAdapter?,
        miniWindowAdapters: @escaping @MainActor () -> [ExtensionMiniWindowAdapter],
        resolvedProfileIdForTab: @escaping @MainActor (Tab) -> UUID?
    ) {
        self.windowQuery = windowQuery
        self.tabQuery = tabQuery
        self.auxiliaryWindows = auxiliaryWindows
        self.profileIdForContext = profileIdForContext
        self.extensionIDForContext = extensionIDForContext
        self.publishedWindowAdapter = publishedWindowAdapter
        self.allMiniWindowAdapters = miniWindowAdapters
        self.resolvedProfileIdForTab = resolvedProfileIdForTab
    }

    func focusedWindow(
        for extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard let windowQuery = windowQuery(),
              let auxiliaryWindows = auxiliaryWindows()
        else { return nil }
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
           let session = auxiliaryWindows.auxiliaryWindowSession(for: keyWindow),
           let miniWindowAdapter = session.miniWindowAdapter,
           ownerMiniWindowAdapters.contains(where: { $0.sessionId == miniWindowAdapter.sessionId }) {
            auxiliaryWindows.recordAuxiliaryWindowSessionFocus(session.id)
            return miniWindowAdapter
        }

        if let miniWindowAdapter = ownerMiniWindowAdapters.first {
            auxiliaryWindows.recordAuxiliaryWindowSessionFocus(
                miniWindowAdapter.sessionId
            )
            return miniWindowAdapter
        }

        if let keyWindow = NSApp.keyWindow,
           let mainWindowState = windowQuery.extensionWindowState(
            forAppKitWindow: keyWindow
           ),
           let contextProfileId,
           let adapter = publishedWindowAdapter(
               mainWindowState,
               contextProfileId
           ) {
            return adapter
        }

        if let activeWindow = windowQuery.activeExtensionWindowState,
           let contextProfileId,
           let adapter = publishedWindowAdapter(
               activeWindow,
               contextProfileId
           ) {
            return adapter
        }
        return nil
    }

    func openWindows(
        for extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        guard let windowQuery = windowQuery(),
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
        openWindows += windowQuery.allExtensionWindowStates.compactMap { windowState -> (any WKWebExtensionWindow)? in
            publishedWindowAdapter(windowState, contextProfileId)
        }

        return openWindows
    }

    func miniWindowAdapters(
        ownerExtensionID: String,
        profileId: UUID?
    ) -> [ExtensionMiniWindowAdapter] {
        guard let tabQuery = tabQuery(),
              let auxiliaryWindows = auxiliaryWindows()
        else { return [] }

        var adapters = allMiniWindowAdapters().compactMap { adapter -> ExtensionMiniWindowAdapter? in
            guard let session = auxiliaryWindows.auxiliaryWindowSession(
                    for: adapter.sessionId
                  ),
                  session.ownerExtensionID == ownerExtensionID,
                  session.window.isVisible,
                  let sessionAdapter = session.miniWindowAdapter,
                  let tab = tabQuery.extensionTab(for: sessionAdapter.tabId)
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

        if let focused = auxiliaryWindows.focusedExtensionMiniWindowAdapter(
            forOwnerExtensionID: ownerExtensionID
        ),
           let focusedIndex = adapters.firstIndex(where: { $0.sessionId == focused.sessionId }) {
            adapters.insert(adapters.remove(at: focusedIndex), at: 0)
        }

        return adapters
    }
}
