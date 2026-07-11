//
//  ExtensionAdapterResolutionOwner.swift
//  Sumi
//
//  Resolves (and lazily creates) the WKWebExtension window/tab adapter
//  objects that bridge browser windows and tabs into the extension runtime.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionAdapterResolutionOwner {
    private weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func miniWindowAdapter(for tab: Tab) -> ExtensionMiniWindowAdapter? {
        manager?.extensionAuxiliaryWindows?
            .auxiliaryWindowSession(for: tab)?.miniWindowAdapter
    }

    func miniWindowAdapter(
        for sessionId: UUID,
        tab: Tab,
        window: NSWindow,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) -> ExtensionMiniWindowAdapter? {
        guard let manager else { return nil }
        return manager.adapterStore.miniWindowAdapter(for: sessionId) { [weak manager] in
            guard let manager,
                  let auxiliaryWindows = manager.extensionAuxiliaryWindows
            else {
                return nil
            }

            return ExtensionMiniWindowAdapter(
                sessionId: sessionId,
                tab: tab,
                window: window,
                auxiliaryWindows: auxiliaryWindows,
                windowPublications: manager.browserRuntimeBridgeOwner
                    .windowPublications,
                isPrivate: isPrivate,
                shouldActivateApp: shouldActivateApp
            )
        }
    }

    func windowAdapter(for windowId: UUID) -> ExtensionWindowAdapter? {
        guard let manager else { return nil }
        return manager.adapterStore.windowAdapter(for: windowId) { [weak manager] in
            guard let manager,
                  let windowQuery = manager.extensionWindowQuery,
                  let windowActivation = manager.extensionWindowActivation,
                  let windowState = windowQuery.extensionWindowState(
                    for: windowId
                  )
            else {
                return nil
            }

            return ExtensionWindowAdapter(
                windowState: windowState,
                windowQuery: windowQuery,
                windowActivation: windowActivation,
                contextPublications: manager.contextPublications,
                extensionManager: manager
            )
        }
    }

    /// Resolves only a normal window already published to the exact WebKit
    /// profile represented by `extensionContext`. This is the read boundary;
    /// `windowAdapter(for:)` exists only for lifecycle materialization.
    func publishedNormalWindowAdapter(
        for windowState: BrowserWindowState,
        extensionContext: WKWebExtensionContext
    ) -> ExtensionWindowAdapter? {
        guard let manager,
              let windowQuery = manager.extensionWindowQuery,
              windowQuery.extensionWindowState(for: windowState.id)
                === windowState,
              let profileID = manager.contextPublications.currentIdentity(
                for: extensionContext
              )?.profileID,
              manager.windowMatchesProfile(windowState, profileId: profileID),
              let adapter = manager.browserRuntimeBridgeOwner
                .publishedWindowAdapter(
                    for: windowState,
                    profileID: profileID
                ),
              adapter.represents(windowState)
        else {
            return nil
        }
        return adapter
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let manager else { return nil }
        return manager.adapterStore.tabAdapter(for: tab) { [weak manager] in
            guard let manager,
                  let windowQuery = manager.extensionWindowQuery,
                  let tabQuery = manager.extensionTabQuery,
                  let tabMutation = manager.extensionTabMutation,
                  let webViewHosting = manager.extensionWebViewHosting,
                  let auxiliaryWindows = manager.extensionAuxiliaryWindows
            else {
                return nil
            }

            return ExtensionTabAdapter(
                tab: tab,
                windowQuery: windowQuery,
                tabQuery: tabQuery,
                tabMutation: tabMutation,
                webViewHosting: webViewHosting,
                auxiliaryWindows: auxiliaryWindows,
                windowPublications: manager.browserRuntimeBridgeOwner
                    .windowPublications,
                contextPublications: manager.contextPublications,
                extensionManager: manager
            )
        }
    }
}
