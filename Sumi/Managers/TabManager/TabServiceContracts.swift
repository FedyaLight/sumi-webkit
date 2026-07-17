import Foundation

@MainActor
final class DefaultTabRuntimeStore: ShellSelectionTabStore {
    private let state: TabStateStore
    private let membership: TabCollectionMembershipOwner
    private let regularTabs: RegularTabCollectionOwner
    private let presentation: TabShortcutPresentationOwner

    init(
        state: TabStateStore,
        membership: TabCollectionMembershipOwner,
        regularTabs: RegularTabCollectionOwner,
        presentation: TabShortcutPresentationOwner
    ) {
        self.state = state
        self.membership = membership
        self.regularTabs = regularTabs
        self.presentation = presentation
    }

    var spaces: [Space] { state.spaces.spaces }

    func tab(for id: UUID) -> Tab? {
        membership.tab(for: id)
    }

    func tabs(in space: Space) -> [Tab] {
        regularTabs.tabs(in: space)
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        state.shortcutPins.shortcutPin(by: id)
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        presentation.activeShortcutTab(for: windowId)
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        presentation.liveShortcutTabs(in: windowId)
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        presentation.shortcutLiveTab(for: pinId, in: windowId)
    }
}
