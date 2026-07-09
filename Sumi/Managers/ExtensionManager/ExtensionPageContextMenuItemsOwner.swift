//
//  ExtensionPageContextMenuItemsOwner.swift
//  Sumi
//
//  Builds the extension-provided items (menus/contextMenus API) for a page's
//  contextual menu, mirroring Safari's per-extension context-menu entries.
//

import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionPageContextMenuItemsOwner {
    private weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    /// WebKit resolves each extension's menu state (visibility, document
    /// patterns, enablement) at fetch time, so fetch immediately before the
    /// menu is shown — items must not be cached across menu presentations.
    func menuItems(for tab: Tab) -> [NSMenuItem] {
        guard let manager,
              manager.isTabEligibleForCurrentExtensionRuntime(tab),
              let profileId = manager.resolvedProfileId(for: tab),
              let tabAdapter = manager.adapterResolutionOwner.stableAdapter(for: tab)
        else { return [] }

        return manager.extensionContexts(for: profileId)
            .sorted { $0.key < $1.key }
            .flatMap { _, extensionContext -> [NSMenuItem] in
                guard extensionContext.isLoaded else { return [] }
                return extensionContext.menuItems(for: tabAdapter)
            }
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func pageContextMenuItems(for tab: Tab) -> [NSMenuItem] {
        pageContextMenuItemsOwner.menuItems(for: tab)
    }
}
