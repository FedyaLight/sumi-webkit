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
    private let publishedTabs: ExtensionPublishedNormalTabQuery
    private let profileRuntime: ExtensionProfileRuntime
    private let profileID: @MainActor (Tab) -> UUID?
    private let adapters: ExtensionAdapterCatalog

    init(
        publishedTabs: ExtensionPublishedNormalTabQuery,
        profileRuntime: ExtensionProfileRuntime,
        profileID: @escaping @MainActor (Tab) -> UUID?,
        adapters: ExtensionAdapterCatalog
    ) {
        self.publishedTabs = publishedTabs
        self.profileRuntime = profileRuntime
        self.profileID = profileID
        self.adapters = adapters
    }

    /// WebKit resolves each extension's menu state (visibility, document
    /// patterns, enablement) at fetch time, so fetch immediately before the
    /// menu is shown — items must not be cached across menu presentations.
    func menuItems(for tab: Tab) -> [NSMenuItem] {
        guard publishedTabs.containsPublishedTab(tab),
              let profileId = profileID(tab),
              let tabAdapter = adapters.stableAdapter(for: tab)
        else { return [] }

        return profileRuntime.contexts(for: profileId)
            .sorted { $0.key < $1.key }
            .flatMap { _, extensionContext -> [NSMenuItem] in
                guard extensionContext.isLoaded else { return [] }
                return extensionContext.menuItems(for: tabAdapter)
            }
    }
}
