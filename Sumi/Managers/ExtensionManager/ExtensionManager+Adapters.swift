import AppKit
import Foundation

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func miniWindowAdapter(for tab: Tab) -> ExtensionMiniWindowAdapter? {
        browserBridgeContext?.auxiliaryWindowSession(for: tab)?.miniWindowAdapter
    }

    func miniWindowAdapter(
        for sessionId: UUID,
        tab: Tab,
        window: NSWindow,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) -> ExtensionMiniWindowAdapter? {
        adapterStore.miniWindowAdapter(for: sessionId) { [weak self] in
            guard let self,
                  let browserBridgeContext else {
                return nil
            }

            return ExtensionMiniWindowAdapter(
                sessionId: sessionId,
                tabId: tab.id,
                window: window,
                browserContext: browserBridgeContext,
                extensionManager: self,
                isPrivate: isPrivate,
                shouldActivateApp: shouldActivateApp
            )
        }
    }

    func windowAdapter(for windowId: UUID) -> ExtensionWindowAdapter? {
        adapterStore.windowAdapter(for: windowId) { [weak self] in
            guard let self,
                  let browserBridgeContext,
                  browserBridgeContext.extensionWindowState(for: windowId) != nil else {
                return nil
            }

            return ExtensionWindowAdapter(
                windowId: windowId,
                browserContext: browserBridgeContext,
                extensionManager: self
            )
        }
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        adapterStore.tabAdapter(for: tab.id) { [weak self] in
            guard let self,
                  let browserBridgeContext else {
                return nil
            }

            return ExtensionTabAdapter(
                tabId: tab.id,
                browserContext: browserBridgeContext,
                extensionManager: self
            )
        }
    }
}
