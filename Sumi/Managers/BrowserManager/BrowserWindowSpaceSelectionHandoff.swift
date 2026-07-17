import Foundation

@MainActor
final class BrowserWindowSpaceSelectionHandoff {
    enum Target {
        case tab(Tab)
        case empty

        var preferredTab: Tab? {
            guard case .tab(let tab) = self else { return nil }
            return tab
        }
    }

    private let tabContext: BrowserWindowTabContext
    private let selection: BrowserTabSelectionOwner
    private let visuals: BrowserWindowVisualCoordinator

    init(
        tabContext: BrowserWindowTabContext,
        selection: BrowserTabSelectionOwner,
        visuals: BrowserWindowVisualCoordinator
    ) {
        self.tabContext = tabContext
        self.selection = selection
        self.visuals = visuals
    }

    func canPreserveCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        tabContext.hasValidCurrentSelection(in: windowState)
            && tabContext.currentTab(for: windowState) != nil
    }

    func resolveTarget(
        for space: Space,
        in windowState: BrowserWindowState
    ) -> Target {
        guard let tab = tabContext.selectionTarget(for: space, in: windowState) else {
            return .empty
        }
        return .tab(tab)
    }

    func present(_ target: Target, in windowState: BrowserWindowState) {
        switch target {
        case .tab(let tab):
            _ = selection.applyTabSelection(
                tab,
                in: windowState,
                updateSpaceFromTab: false,
                updateTheme: false,
                rememberSelection: true,
                persistSelection: false,
                loadPolicy: .immediate
            )
            _ = visuals.performImmediateVisualHandoffIfPossible(
                in: windowState
            )
        case .empty:
            selection.showEmptyState(in: windowState)
        }
    }
}
