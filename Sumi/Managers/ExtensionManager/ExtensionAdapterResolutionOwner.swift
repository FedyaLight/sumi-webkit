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
        manager?.browserBridgeContext?
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
                  let browserBridgeContext = manager.browserBridgeContext else {
                return nil
            }

            return ExtensionMiniWindowAdapter(
                sessionId: sessionId,
                tabId: tab.id,
                window: window,
                browserContext: browserBridgeContext,
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
                  let browserBridgeContext = manager.browserBridgeContext,
                  browserBridgeContext.extensionWindowState(for: windowId) != nil else {
                return nil
            }

            return ExtensionWindowAdapter(
                windowId: windowId,
                browserContext: browserBridgeContext,
                extensionManager: manager
            )
        }
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let manager else { return nil }
        return manager.adapterStore.tabAdapter(for: tab.id) { [weak manager] in
            guard let manager,
                  let browserBridgeContext = manager.browserBridgeContext else {
                return nil
            }

            return ExtensionTabAdapter(
                tabId: tab.id,
                browserContext: browserBridgeContext,
                extensionManager: manager
            )
        }
    }
}
