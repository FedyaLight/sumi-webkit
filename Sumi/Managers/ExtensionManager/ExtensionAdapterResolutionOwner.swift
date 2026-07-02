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
    struct Dependencies {
        let adapterStore: ExtensionBrowserAdapterStore
        let browserBridgeContext: @MainActor () -> (any ExtensionBrowserBridgeContext)?
        let manager: @MainActor () -> ExtensionManager?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func miniWindowAdapter(for tab: Tab) -> ExtensionMiniWindowAdapter? {
        dependencies.browserBridgeContext()?
            .auxiliaryWindowSession(for: tab)?.miniWindowAdapter
    }

    func miniWindowAdapter(
        for sessionId: UUID,
        tab: Tab,
        window: NSWindow,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) -> ExtensionMiniWindowAdapter? {
        dependencies.adapterStore.miniWindowAdapter(for: sessionId) { [dependencies] in
            guard let manager = dependencies.manager(),
                  let browserBridgeContext = dependencies.browserBridgeContext() else {
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
        dependencies.adapterStore.windowAdapter(for: windowId) { [dependencies] in
            guard let manager = dependencies.manager(),
                  let browserBridgeContext = dependencies.browserBridgeContext(),
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
        dependencies.adapterStore.tabAdapter(for: tab.id) { [dependencies] in
            guard let manager = dependencies.manager(),
                  let browserBridgeContext = dependencies.browserBridgeContext() else {
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

@available(macOS 15.5, *)
extension ExtensionAdapterResolutionOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            adapterStore: manager.adapterStore,
            browserBridgeContext: { [weak manager] in
                manager?.browserBridgeContext
            },
            manager: { [weak manager] in
                manager
            }
        )
    }
}
