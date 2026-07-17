import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class BrowserTransientExtensionTabCommands {
    private let creation: TransientExtensionTabCreationTransaction
    private let residence: TransientExtensionTabResidenceQuery
    private let promotion: TransientExtensionTabPromotionTransaction
    private let spaces: TabSpaceCollectionStateOwner

    init(
        creation: TransientExtensionTabCreationTransaction,
        residence: TransientExtensionTabResidenceQuery,
        promotion: TransientExtensionTabPromotionTransaction,
        spaces: TabSpaceCollectionStateOwner
    ) {
        self.creation = creation
        self.residence = residence
        self.promotion = promotion
        self.spaces = spaces
    }

    func create(
        url: URL,
        in space: Space?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        creation.create(
            url: url.absoluteString,
            in: space,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    func containsExact(_ tab: Tab) -> Bool {
        residence.containsExact(tab)
    }

    func promote(_ tab: Tab) -> Bool {
        guard residence.containsExact(tab),
              let targetSpace = tab.spaceId.flatMap({ spaceID in
                  spaces.spaces.first { $0.id == spaceID }
              }) else {
            return false
        }
        return promotion.promote(tab, in: targetSpace, activate: false)
    }
}

/// Browser-owned WebExtension tab commands. This is a behavior boundary, not
/// a dependency catalog: callers can only perform extension tab mutations.
@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionTabCommands {
    private let regularTabs: TabRegularLifecycleOwner
    private let transientTabs: BrowserTransientExtensionTabCommands
    private let pinning: SidebarPinCommands
    private let requestedDiscard: ExtensionRequestedTabDiscardService

    init(
        regularTabs: TabRegularLifecycleOwner,
        transientTabs: BrowserTransientExtensionTabCommands,
        pinning: SidebarPinCommands,
        requestedDiscard: ExtensionRequestedTabDiscardService
    ) {
        self.regularTabs = regularTabs
        self.transientTabs = transientTabs
        self.pinning = pinning
        self.requestedDiscard = requestedDiscard
    }

    func create(
        url: URL?,
        in space: Space?,
        activate: Bool,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        if let url {
            return regularTabs.createNewTab(
                url: url.absoluteString,
                in: space,
                activate: activate,
                webExtensionContextOverride: webExtensionContextOverride
            )
        }
        return regularTabs.createNewTab(
            in: space,
            activate: activate,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    func createTransient(
        url: URL,
        in space: Space?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        transientTabs.create(
            url: url,
            in: space,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    func containsTransient(_ tab: Tab) -> Bool {
        transientTabs.containsExact(tab)
    }

    func pin(
        _ tab: Tab,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?
    ) -> Bool {
        pinning.pinTab(
            tab,
            context: .init(
                windowState: targetWindow,
                spaceId: targetSpace?.id ?? tab.spaceId
            )
        )
        return tab.shortcutPinId != nil
    }

    func discard(_ tab: Tab, restoringSelectionTo tabID: UUID?) -> Bool {
        requestedDiscard.discard(tab, restoringSelectionTo: tabID)
    }

    func promoteTransient(_ tab: Tab) -> Bool {
        transientTabs.promote(tab)
    }
}

@available(macOS 15.5, *)
@MainActor
enum BrowserExtensionTabMutationComposition {
    static func make(
        commands: BrowserExtensionTabCommands,
        selection: BrowserTabSelectionOwner
    ) -> BrowserExtensionTabMutationAdapter {
        BrowserExtensionTabMutationAdapter(
            commands: commands,
            selection: selection
        )
    }
}
