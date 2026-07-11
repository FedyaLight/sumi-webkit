import Foundation

/// Assembles the browser-side WebExtension Tab mutation capability. The
/// factory stores no browser root; returned callbacks retain it weakly and the
/// discard path is a concrete transaction service.
@available(macOS 15.5, *)
@MainActor
enum BrowserExtensionTabMutationComposition {
    static func make(
        browserManager: BrowserManager
    ) -> BrowserExtensionTabMutationAdapter {
        let tabs = browserManager.tabManager
        let discard = ExtensionRequestedTabDiscardService(
            transactions: tabs.structuralLookupCoordinator,
            persistence: tabs.structuralPersistence,
            membership: tabs.tabCollectionMembershipOwner,
            transientTabs: tabs.transientWebKitTabLifecycleOwner,
            regularTabs: tabs.regularTabCollectionOwner,
            spaces: tabs.spaceStateOwner,
            selection: tabs.selectionStateOwner,
            runtimePorts: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure(
                        "Browser runtime released before requested Tab discard."
                    )
                }
                return browserManager.tabManager.requireRuntimePorts()
            }
        )

        return BrowserExtensionTabMutationAdapter(
            createTab: { [weak browserManager] url, space, activate, context in
                guard let tabs = browserManager?.tabManager else {
                    preconditionFailure(
                        "Browser runtime released before extension Tab creation."
                    )
                }
                if let url {
                    return tabs.regularTabLifecycleOwner.createNewTab(
                        url: url.absoluteString,
                        in: space,
                        activate: activate,
                        webExtensionContextOverride: context
                    )
                }
                return tabs.regularTabLifecycleOwner.createNewTab(
                    in: space,
                    activate: activate,
                    webExtensionContextOverride: context
                )
            },
            createTransientTab: {
                [weak browserManager] url, space, context in
                guard let tabs = browserManager?.tabManager else {
                    preconditionFailure(
                        "Browser runtime released before transient Tab creation."
                    )
                }
                return tabs.transientWebKitTabLifecycleOwner
                    .createTransientExtensionTab(
                        url: url.absoluteString,
                        in: space,
                        webExtensionContextOverride: context
                    )
            },
            pinTab: { [weak browserManager] tab, window, space in
                let targetSpaceID = space?.id ?? tab.spaceId
                browserManager?.tabManager.shortcutPinCommandOwner.pinTab(
                    tab,
                    context: .init(
                        windowState: window,
                        spaceId: targetSpaceID
                    )
                )
                let committed = tab.shortcutPinId != nil
                return committed
            },
            selectTab: { [weak browserManager] tab, window in
                browserManager?.selectTab(tab, in: window)
            },
            placeTab: { tab, window in
                window.markWebKitChildWindowAdopted(by: tab.id)
            },
            requestedTabDiscard: discard,
            promoteTransientTab: { [weak browserManager] tab in
                guard let tabs = browserManager?.tabManager,
                      tabs.transientWebKitTabLifecycleOwner
                        .isTransientExtensionTab(tab),
                      let targetSpace = tab.spaceId.flatMap({ spaceID in
                          tabs.spaceStateOwner.spaces.first {
                              $0.id == spaceID
                          }
                      })
                else {
                    return false
                }
                return tabs.transientWebKitTabLifecycleOwner
                    .promoteTransientExtensionTab(
                        tab,
                        in: targetSpace,
                        activate: false
                    )
            }
        )
    }
}
