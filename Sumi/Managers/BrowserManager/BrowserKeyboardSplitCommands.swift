import Foundation
import SumiDomain

enum BrowserSplitLayoutCommandResult {
    case updatedExistingSplit
    case createdSplitPicker
    case rejected
}

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

    @discardableResult
    func setLayout(
        _ layoutKind: SplitLayoutKind,
        in windowState: BrowserWindowState
    ) -> BrowserSplitLayoutCommandResult {
        if query.group(in: windowState.id) != nil {
            layout.setLayoutKind(layoutKind, in: windowState.id)
            return .updatedExistingSplit
        }
        guard emptyCreation.create(side: .right, in: windowState) else {
            return .rejected
        }
        layout.setLayoutKind(layoutKind, in: windowState.id)
        return .createdSplitPicker
    }

    func unsplit(in windowState: BrowserWindowState) {
        layout.unsplit(in: windowState)
    }

    @discardableResult
    func createEmptySplit(
        side: SplitDropSide = .right,
        in windowState: BrowserWindowState
    ) -> Bool {
        emptyCreation.create(side: side, in: windowState)
    }

    func canCreateEmptySplit(
        side: SplitDropSide = .right,
        in windowState: BrowserWindowState
    ) -> Bool {
        let memberCount =
            query.group(in: windowState.id)?.members.count ?? 0
        return memberCount < SplitGroup.maximumMembers
            && emptyCreation.canCreate(side: side, in: windowState)
    }

    func hasSplit(in windowState: BrowserWindowState) -> Bool {
        query.group(in: windowState.id) != nil
    }
}
