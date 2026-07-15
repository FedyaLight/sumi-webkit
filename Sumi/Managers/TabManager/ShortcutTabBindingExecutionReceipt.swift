import Foundation

/// One-shot typed profile execution tail for an already installed shortcut
/// binding model.
@MainActor
final class ShortcutTabBindingExecutionReceipt {
    private enum State { case prepared, executed }

    private let profiles: TabProfileTransitionService
    private let tab: Tab
    private let targetProfileID: UUID?
    private var state = State.prepared

    init(
        profiles: TabProfileTransitionService,
        tab: Tab,
        targetProfileID: UUID?
    ) {
        self.profiles = profiles
        self.tab = tab
        self.targetProfileID = targetProfileID
    }

    func execute() {
        guard case .prepared = state else {
            preconditionFailure("Shortcut binding execution settled twice")
        }
        state = .executed
        profiles.assignProfile(targetProfileID, to: tab)
    }
}
