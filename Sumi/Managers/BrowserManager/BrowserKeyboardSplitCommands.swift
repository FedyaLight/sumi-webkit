import Foundation
import SumiDomain

/// Split commands scoped to one resolved browser window.
@MainActor
final class BrowserKeyboardSplitCommands {
    private let query: WindowSplitQuery
    private let layout: SplitLayoutService
    private let emptyCreation: EmptySplitCreationWorkflow

    init(
        query: WindowSplitQuery,
        layout: SplitLayoutService,
        emptyCreation: EmptySplitCreationWorkflow
    ) {
        self.query = query
        self.layout = layout
        self.emptyCreation = emptyCreation
    }

    func setLayout(
        _ layoutKind: SplitLayoutKind,
        in windowState: BrowserWindowState
    ) {
        if query.group(in: windowState.id) != nil {
            layout.setLayoutKind(layoutKind, in: windowState.id)
            return
        }
        emptyCreation.create(side: .right, in: windowState)
        layout.setLayoutKind(layoutKind, in: windowState.id)
    }

    func unsplit(in windowState: BrowserWindowState) {
        layout.unsplit(in: windowState)
    }

    func createEmptySplit(in windowState: BrowserWindowState) {
        emptyCreation.create(side: .right, in: windowState)
    }
}
