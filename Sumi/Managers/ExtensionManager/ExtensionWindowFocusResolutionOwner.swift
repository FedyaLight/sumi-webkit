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
    struct Dependencies {
        let browserBridgeContext: @MainActor () -> (any ExtensionBrowserBridgeContext)?
        let profileIdForContext: @MainActor (WKWebExtensionContext) -> UUID?
        let extensionIDForContext: @MainActor (WKWebExtensionContext) -> String?
        let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
        let windowAdapter: @MainActor (UUID) -> ExtensionWindowAdapter?
        let miniWindowAdapters: @MainActor () -> [ExtensionMiniWindowAdapter]
        let resolvedProfileIdForTab: @MainActor (Tab) -> UUID?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func focusedWindow(
        for extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard let browserContext = dependencies.browserBridgeContext() else { return nil }
        let contextProfileId = dependencies.profileIdForContext(extensionContext)
        let ownerExtensionId = dependencies.extensionIDForContext(extensionContext)
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
           contextProfileId.map({ dependencies.windowMatchesProfile(mainWindowState, $0) }) ?? true {
            return dependencies.windowAdapter(mainWindowState.id)
        }

        if let activeWindow = browserContext.activeExtensionWindowState,
           contextProfileId.map({ dependencies.windowMatchesProfile(activeWindow, $0) }) ?? true {
            return dependencies.windowAdapter(activeWindow.id)
        }
        return nil
    }

    func openWindows(
        for extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        guard let browserContext = dependencies.browserBridgeContext(),
              let contextProfileId = dependencies.profileIdForContext(extensionContext)
        else { return [] }

        let ownerMiniWindowAdapters: [ExtensionMiniWindowAdapter] = {
            guard let ownerExtensionId = dependencies.extensionIDForContext(extensionContext) else {
                return []
            }
            return miniWindowAdapters(
                ownerExtensionID: ownerExtensionId,
                profileId: contextProfileId
            )
        }()

        var openWindows: [any WKWebExtensionWindow] = ownerMiniWindowAdapters
        openWindows += browserContext.allExtensionWindowStates.compactMap { windowState -> (any WKWebExtensionWindow)? in
            guard dependencies.windowMatchesProfile(windowState, contextProfileId) else {
                return nil
            }
            return dependencies.windowAdapter(windowState.id)
        }

        return openWindows
    }

    func miniWindowAdapters(
        ownerExtensionID: String,
        profileId: UUID?
    ) -> [ExtensionMiniWindowAdapter] {
        guard let browserContext = dependencies.browserBridgeContext() else { return [] }

        var adapters = dependencies.miniWindowAdapters().compactMap { adapter -> ExtensionMiniWindowAdapter? in
            guard let session = browserContext.auxiliaryWindowSession(for: adapter.sessionId),
                  session.ownerExtensionID == ownerExtensionID,
                  session.window.isVisible,
                  let sessionAdapter = session.miniWindowAdapter,
                  let tab = browserContext.extensionTab(for: sessionAdapter.tabId)
            else {
                return nil
            }
            if let profileId, dependencies.resolvedProfileIdForTab(tab) != profileId {
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

@available(macOS 15.5, *)
extension ExtensionWindowFocusResolutionOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            browserBridgeContext: { [weak manager] in
                manager?.browserBridgeContext
            },
            profileIdForContext: { [weak manager] context in
                manager?.profileId(for: context)
            },
            extensionIDForContext: { [weak manager] context in
                manager?.extensionID(for: context)
            },
            windowMatchesProfile: { [weak manager] windowState, profileId in
                manager?.windowMatchesProfile(windowState, profileId: profileId) ?? false
            },
            windowAdapter: { [weak manager] windowId in
                manager?.windowAdapter(for: windowId)
            },
            miniWindowAdapters: { [weak manager] in
                manager.map { Array($0.adapterStore.miniWindowAdapters.values) } ?? []
            },
            resolvedProfileIdForTab: { [weak manager] tab in
                manager?.resolvedProfileId(for: tab)
            }
        )
    }
}
