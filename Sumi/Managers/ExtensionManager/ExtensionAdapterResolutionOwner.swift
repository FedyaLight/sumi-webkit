//
//  ExtensionAdapterResolutionOwner.swift
//  Sumi
//
//  Resolves (and lazily creates) the WKWebExtension window/tab adapter
//  objects that bridge browser windows and tabs into the extension runtime.
//

import AppKit
import Foundation

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
                  let tabQuery = manager.extensionTabQuery,
                  let auxiliaryWindows = manager.extensionAuxiliaryWindows
            else {
                return nil
            }

            return ExtensionMiniWindowAdapter(
                sessionId: sessionId,
                tabId: tab.id,
                window: window,
                tabQuery: tabQuery,
                auxiliaryWindows: auxiliaryWindows,
                extensionManager: manager,
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
                  windowQuery.extensionWindowState(for: windowId) != nil
            else {
                return nil
            }

            return ExtensionWindowAdapter(
                windowId: windowId,
                windowQuery: windowQuery,
                windowActivation: windowActivation,
                extensionManager: manager
            )
        }
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let manager else { return nil }
        return manager.adapterStore.tabAdapter(for: tab.id) { [weak manager] in
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
                tabId: tab.id,
                windowQuery: windowQuery,
                tabQuery: tabQuery,
                tabMutation: tabMutation,
                webViewHosting: webViewHosting,
                auxiliaryWindows: auxiliaryWindows,
                extensionManager: manager
            )
        }
    }
}
