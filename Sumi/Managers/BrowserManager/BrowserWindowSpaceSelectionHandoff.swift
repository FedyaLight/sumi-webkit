import Foundation

/// Resolves and presents the selection belonging to a Space in one exact
/// browser window. Resolution is deliberately separated from presentation so
/// the process-wide Space activation can use the same preferred tab first.
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
    private let applyTabSelection: (Tab, BrowserWindowState) -> Void
    private let performImmediateVisualHandoff: (BrowserWindowState) -> Void
    private let showEmptyState: (BrowserWindowState) -> Void

    init(
        tabContext: BrowserWindowTabContext,
        applyTabSelection: @escaping (Tab, BrowserWindowState) -> Void,
        performImmediateVisualHandoff: @escaping (BrowserWindowState) -> Void,
        showEmptyState: @escaping (BrowserWindowState) -> Void
    ) {
        self.tabContext = tabContext
        self.applyTabSelection = applyTabSelection
        self.performImmediateVisualHandoff = performImmediateVisualHandoff
        self.showEmptyState = showEmptyState
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
            applyTabSelection(tab, windowState)
            performImmediateVisualHandoff(windowState)
        case .empty:
            showEmptyState(windowState)
        }
    }
}
