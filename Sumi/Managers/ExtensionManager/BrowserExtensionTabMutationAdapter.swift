import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionTabMutationAdapter:
    ExtensionTabMutation {
    private let commands: BrowserExtensionTabCommands
    private let selection: BrowserTabSelectionOwner

    init(
        commands: BrowserExtensionTabCommands,
        selection: BrowserTabSelectionOwner
    ) {
        self.commands = commands
        self.selection = selection
    }

    func createExtensionTab(
        url: URL?,
        in space: Space?,
        activate: Bool,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        commands.create(
            url: url,
            in: space,
            activate: activate,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    func createTransientExtensionTab(
        url: URL,
        in space: Space?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        commands.createTransient(
            url: url,
            in: space,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    @discardableResult
    func pinExtensionTab(
        _ tab: Tab,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?
    ) -> Bool {
        commands.pin(
            tab,
            targetWindow: targetWindow,
            targetSpace: targetSpace
        )
    }

    func selectExtensionTab(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        selection.selectTab(tab, in: windowState, loadPolicy: .immediate)
    }

    func placeExtensionTab(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        windowState.markWebKitChildWindowAdopted(by: tab.id)
    }

    @discardableResult
    func discardExtensionRequestedTab(
        _ tab: Tab,
        restoringSelectionTo tabID: UUID?
    ) -> Bool {
        commands.discard(
            tab,
            restoringSelectionTo: tabID
        )
    }

    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        commands.promoteTransient(tab)
    }
}
