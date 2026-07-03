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
    struct Dependencies {
        let isTabEligible: @MainActor (Tab) -> Bool
        let resolvedProfileId: @MainActor (Tab) -> UUID?
        let loadedContexts: @MainActor (UUID) -> [String: WKWebExtensionContext]
        let tabAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// WebKit resolves each extension's menu state (visibility, document
    /// patterns, enablement) at fetch time, so fetch immediately before the
    /// menu is shown — items must not be cached across menu presentations.
    func menuItems(for tab: Tab) -> [NSMenuItem] {
        guard dependencies.isTabEligible(tab),
              let profileId = dependencies.resolvedProfileId(tab),
              let tabAdapter = dependencies.tabAdapter(tab)
        else { return [] }

        return dependencies.loadedContexts(profileId)
            .sorted { $0.key < $1.key }
            .flatMap { _, extensionContext -> [NSMenuItem] in
                guard extensionContext.isLoaded else { return [] }
                return extensionContext.menuItems(for: tabAdapter)
            }
    }
}

@available(macOS 15.5, *)
extension ExtensionPageContextMenuItemsOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            isTabEligible: { [weak manager] tab in
                manager?.isTabEligibleForCurrentExtensionRuntime(tab) ?? false
            },
            resolvedProfileId: { [weak manager] tab in
                manager?.resolvedProfileId(for: tab)
            },
            loadedContexts: { [weak manager] profileId in
                manager?.extensionContexts(for: profileId) ?? [:]
            },
            tabAdapter: { [weak manager] tab in
                manager?.adapterResolutionOwner.stableAdapter(for: tab)
            }
        )
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
