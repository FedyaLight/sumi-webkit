//
//  ExtensionWindowVisibilityResolver.swift
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
final class ExtensionWindowVisibilityResolver {
    private let windowQuery: @MainActor () -> (any ExtensionWindowQuery)?
    private let auxiliaryWindows:
        @MainActor () -> (any ExtensionAuxiliaryWindowControl)?
    private let profileIdForContext: @MainActor (WKWebExtensionContext) -> UUID?
    private let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?
    private let publishedWindowAdapter: @MainActor (
        BrowserWindowState,
        UUID
    ) -> ExtensionWindowAdapter?
    private let publishedMiniWindowAdapters: @MainActor (
        String,
        UUID
    ) -> [ExtensionMiniWindowAdapter]

    init(
        windowQuery: @escaping @MainActor () -> (any ExtensionWindowQuery)?,
        auxiliaryWindows:
            @escaping @MainActor () -> (any ExtensionAuxiliaryWindowControl)?,
        profileIdForContext: @escaping @MainActor (WKWebExtensionContext) -> UUID?,
        extensionIDForContext: @escaping @MainActor (WKWebExtensionContext) -> String?,
        publishedWindowAdapter: @escaping @MainActor (
            BrowserWindowState,
            UUID
        ) -> ExtensionWindowAdapter?,
        miniWindowAdapters: @escaping @MainActor (
            String,
            UUID
        ) -> [ExtensionMiniWindowAdapter]
    ) {
        self.windowQuery = windowQuery
        self.auxiliaryWindows = auxiliaryWindows
        self.profileIdForContext = profileIdForContext
        self.extensionIDForContext = extensionIDForContext
        self.publishedWindowAdapter = publishedWindowAdapter
        self.publishedMiniWindowAdapters = miniWindowAdapters
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
           let publishedAdapter = ownerMiniWindowAdapters.first(
               where: { $0 === miniWindowAdapter }
           ),
           let receipt = auxiliaryWindows.auxiliaryWindowSessionReceipt(
                for: session
           ) {
            auxiliaryWindows.recordAuxiliaryWindowSessionFocus(receipt)
            return publishedAdapter
        }

        if let miniWindowAdapter = ownerMiniWindowAdapters.first,
           let session = auxiliaryWindows.auxiliaryWindowSession(
                for: miniWindowAdapter.sessionId
           ),
           session.miniWindowAdapter === miniWindowAdapter,
           let receipt = auxiliaryWindows.auxiliaryWindowSessionReceipt(
                for: session
           ) {
            auxiliaryWindows.recordAuxiliaryWindowSessionFocus(receipt)
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
        guard let auxiliaryWindows = auxiliaryWindows(),
              let profileId
        else { return [] }

        var adapters = publishedMiniWindowAdapters(
            ownerExtensionID,
            profileId
        ).compactMap { adapter -> ExtensionMiniWindowAdapter? in
            guard let session = auxiliaryWindows.auxiliaryWindowSession(
                    for: adapter.sessionId
                  ),
                  session.ownerExtensionID == ownerExtensionID,
                  session.window.isVisible,
                  let sessionAdapter = session.miniWindowAdapter,
                  sessionAdapter === adapter
            else {
                return nil
            }
            return adapter
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

@available(macOS 15.5, *)
extension ExtensionWindowVisibilityResolver {
    convenience init(manager: ExtensionManager) {
        self.init(
            windowQuery: { [weak manager] in
                manager?.extensionWindowQuery
            },
            auxiliaryWindows: { [weak manager] in
                manager?.extensionAuxiliaryWindows
            },
            profileIdForContext: { [weak manager] context in
                manager?.profileId(for: context)
            },
            extensionIDForContext: { [weak manager] context in
                manager?.extensionID(for: context)
            },
            publishedWindowAdapter: { [weak manager] windowState, profileId in
                manager?.windowPublications.publishedWindowAdapter(
                    for: windowState,
                    profileID: profileId
                )
            },
            miniWindowAdapters: { [weak manager] ownerExtensionID, profileID in
                manager?.windowPublications.publishedAuxiliaryWindowAdapters(
                    ownerExtensionID: ownerExtensionID,
                    profileID: profileID
                ) ?? []
            }
        )
    }
}
