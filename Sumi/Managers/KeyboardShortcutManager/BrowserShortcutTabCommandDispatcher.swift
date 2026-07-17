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

    func dispatch(_ action: ShortcutAction) -> Bool {
        switch action {
        case .newTab:
            selection.openNewTabSurfaceInActiveWindow()
        case .closeTab:
            close.closeCurrentTab()
        case .nextTab:
            selection.selectRelativeTab(offset: 1)
        case .previousTab:
            selection.selectRelativeTab(offset: -1)
        case .goToTab1, .goToTab2, .goToTab3, .goToTab4,
             .goToTab5, .goToTab6, .goToTab7, .goToTab8:
            let index = Int(action.rawValue.components(separatedBy: "_").last ?? "1") ?? 1
            selection.selectTab(at: index - 1)
        case .goToLastTab:
            selection.selectLastTab()
        case .duplicateTab:
            selection.duplicateActiveTab()
        case .splitGrid:
            splits.setActiveLayout(.grid)
        case .splitVertical:
            splits.setActiveLayout(.vertical)
        case .splitHorizontal:
            splits.setActiveLayout(.horizontal)
        case .unsplit:
            splits.unsplitActiveWindow()
        case .newEmptySplit:
            splits.createEmptySplitInActiveWindow()
        default:
            return false
        }
        return true
    }
}
