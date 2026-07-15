import Foundation

@MainActor
struct DisplayedTabShortcutTerminalSelectionPlan {
    let tab: Tab
    let identity: ShortcutBindingIdentity

    func apply(to state: inout BrowserWindowShortcutMutationState) {
        _ = ShortcutSelectionTransition.apply(
            tabID: tab.id,
            source: ShortcutBindingIdentity(tab: tab),
            target: identity,
            isSelected: true,
            to: &state
        )
    }
}
