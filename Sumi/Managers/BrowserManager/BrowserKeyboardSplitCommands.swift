import Foundation
import SumiDomain

/// Active-window split commands with exact split-runtime collaborators.
@MainActor
final class BrowserKeyboardSplitCommands {
    private let shell: BrowserShellRuntime
    private let query: WindowSplitQuery
    private let layout: SplitLayoutService
    private let insertion: SplitInsertionService
    private let emptyCreation: EmptySplitCreationWorkflow

    init(
        shell: BrowserShellRuntime,
        query: WindowSplitQuery,
        layout: SplitLayoutService,
        insertion: SplitInsertionService,
        emptyCreation: EmptySplitCreationWorkflow
    ) {
        self.shell = shell
        self.query = query
        self.layout = layout
        self.insertion = insertion
        self.emptyCreation = emptyCreation
    }

    func setActiveLayout(_ layoutKind: SplitLayoutKind) {
        guard let activeWindow = shell.windowRegistry.activeWindow else { return }
        if query.group(in: activeWindow.id) != nil {
            layout.setLayoutKind(layoutKind, in: activeWindow.id)
            return
        }
        guard let current = shell.windowTabs.currentTab(for: activeWindow),
              current.representsSumiNativeSurface == false else {
            return
        }
        insertion.enterSplit(with: current, side: .right, in: activeWindow)
        layout.setLayoutKind(layoutKind, in: activeWindow.id)
    }

    func unsplitActiveWindow() {
        guard let activeWindow = shell.windowRegistry.activeWindow else { return }
        layout.unsplit(in: activeWindow)
    }

    func createEmptySplitInActiveWindow() {
        guard let activeWindow = shell.windowRegistry.activeWindow else { return }
        emptyCreation.create(side: .right, in: activeWindow)
    }
}
