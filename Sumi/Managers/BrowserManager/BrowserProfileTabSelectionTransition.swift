import Foundation

@MainActor
final class BrowserProfileTabSelectionTransition {
    private let selection: ProfileSelectionCoordinator

    init(selection: ProfileSelectionCoordinator) {
        self.selection = selection
    }

    func transition(in window: BrowserWindowState?) {
        selection.handleProfileSwitch(contextWindowID: window?.id)
    }
}
