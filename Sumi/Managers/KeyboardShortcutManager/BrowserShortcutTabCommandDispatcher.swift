import Foundation
import SumiDomain

@MainActor
final class BrowserShortcutTabCommandDispatcher {
    private let selection: BrowserKeyboardTabSelectionCommands
    private let splits: BrowserKeyboardSplitCommands
    private let close: BrowserTabCloseOrchestrationOwner

    init(
        selection: BrowserKeyboardTabSelectionCommands,
        splits: BrowserKeyboardSplitCommands,
        close: BrowserTabCloseOrchestrationOwner
    ) {
        self.selection = selection
        self.splits = splits
        self.close = close
    }

    func dispatch(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        let windowState = context.windowState
        switch action {
        case .newTab:
            selection.openNewTabSurface(in: windowState)
        case .closeTab:
            close.closeCurrentTab(in: windowState)
        case .nextTab:
            selection.selectRelativeTab(offset: 1, in: windowState)
        case .previousTab:
            selection.selectRelativeTab(offset: -1, in: windowState)
        case .goToTab1, .goToTab2, .goToTab3, .goToTab4,
             .goToTab5, .goToTab6, .goToTab7, .goToTab8:
            let index = Int(action.rawValue.components(separatedBy: "_").last ?? "1") ?? 1
            selection.selectTab(at: index - 1, in: windowState)
        case .goToLastTab:
            selection.selectLastTab(in: windowState)
        case .duplicateTab:
            selection.duplicateTab(in: windowState)
        case .splitGrid:
            splits.setLayout(.grid, in: windowState)
        case .splitVertical:
            splits.setLayout(.vertical, in: windowState)
        case .splitHorizontal:
            splits.setLayout(.horizontal, in: windowState)
        case .unsplit:
            splits.unsplit(in: windowState)
        case .newEmptySplit:
            splits.createEmptySplit(in: windowState)
        default:
            return false
        }
        return true
    }

}
