import Foundation
import SumiDomain

@MainActor
final class BrowserShortcutTabCommandDispatcher {
    private let selection: BrowserKeyboardTabSelectionCommands
    private let splits: BrowserKeyboardSplitCommands
    private let pins: BrowserKeyboardPinCommands
    private let close: BrowserTabCloseOrchestrationOwner

    init(
        selection: BrowserKeyboardTabSelectionCommands,
        splits: BrowserKeyboardSplitCommands,
        pins: BrowserKeyboardPinCommands,
        close: BrowserTabCloseOrchestrationOwner
    ) {
        self.selection = selection
        self.splits = splits
        self.pins = pins
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
            return splits.setLayout(.grid, in: windowState) != .rejected
        case .splitVertical:
            return splits.setLayout(.vertical, in: windowState) != .rejected
        case .splitHorizontal:
            return splits.setLayout(.horizontal, in: windowState) != .rejected
        case .unsplit:
            splits.unsplit(in: windowState)
        case .newEmptySplit:
            splits.createEmptySplit(in: windowState)
        case .addSplitTop:
            return splits.createEmptySplit(side: .top, in: windowState)
        case .addSplitLeft:
            return splits.createEmptySplit(side: .left, in: windowState)
        case .addSplitRight:
            return splits.createEmptySplit(side: .right, in: windowState)
        case .addSplitBottom:
            return splits.createEmptySplit(side: .bottom, in: windowState)
        case .pinTab:
            return pins.pinCurrentTab(in: context)
        case .unpinTab:
            return pins.unpinCurrentTab(in: context)
        case .addToEssentials:
            return pins.addCurrentToEssentials(in: context)
        case .removeFromEssentials:
            return pins.removeCurrentFromEssentials(in: context)
        default:
            return false
        }
        return true
    }

    func canDispatch(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> Bool {
        return switch action {
        case .newTab:
            true
        case .newEmptySplit:
            splits.canCreateEmptySplit(in: context.windowState)
        case .addSplitTop:
            splits.canCreateEmptySplit(side: .top, in: context.windowState)
        case .addSplitLeft:
            splits.canCreateEmptySplit(side: .left, in: context.windowState)
        case .addSplitRight:
            splits.canCreateEmptySplit(side: .right, in: context.windowState)
        case .addSplitBottom:
            splits.canCreateEmptySplit(side: .bottom, in: context.windowState)
        case .splitGrid, .splitVertical, .splitHorizontal:
            context.page != nil
                && (
                    splits.hasSplit(in: context.windowState)
                    || splits.canCreateEmptySplit(in: context.windowState)
                )
        case .unsplit:
            splits.hasSplit(in: context.windowState)
        case .pinTab:
            pins.canPinCurrentTab(in: context)
        case .unpinTab:
            pins.canUnpinCurrentTab(in: context)
        case .addToEssentials:
            pins.canAddCurrentToEssentials(in: context)
        case .removeFromEssentials:
            pins.canRemoveCurrentFromEssentials(in: context)
        case .closeTab, .nextTab, .previousTab, .goToTab1, .goToTab2,
             .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7,
             .goToTab8, .goToLastTab, .duplicateTab:
            context.page != nil
        default:
            false
        }
    }

    func dispatchFromCommandPalette(
        _ action: ShortcutAction,
        in context: BrowserShortcutContext
    ) -> CommandPaletteShortcutExecutionOutcome? {
        switch action {
        case .newTab:
            return selection.openNewTabSurface(in: context.windowState)
                ? .paletteReplaced
                : .dismissPalette
        case .newEmptySplit, .addSplitTop, .addSplitLeft, .addSplitRight,
             .addSplitBottom:
            guard canDispatch(action, in: context) else { return nil }
            let side: SplitDropSide = switch action {
            case .addSplitTop: .top
            case .addSplitLeft: .left
            case .addSplitBottom: .bottom
            case .newEmptySplit, .addSplitRight: .right
            default:
                preconditionFailure("Unreachable split insertion action")
            }
            guard splits.createEmptySplit(
                side: side,
                in: context.windowState
            ) else { return nil }
            return .paletteReplaced
        case .closeTab:
            guard canDispatch(action, in: context) else { return nil }
            close.closeCurrentTabFromCommandPalette(
                in: context.windowState
            )
            return .dismissPalette
        case .splitGrid, .splitVertical, .splitHorizontal:
            guard canDispatch(action, in: context) else { return nil }
            let layoutKind: SplitLayoutKind = switch action {
            case .splitGrid: .grid
            case .splitVertical: .vertical
            case .splitHorizontal: .horizontal
            default:
                preconditionFailure("Unreachable split layout action")
            }
            return switch splits.setLayout(
                layoutKind,
                in: context.windowState
            ) {
            case .updatedExistingSplit:
                .dismissPalette
            case .createdSplitPicker:
                .paletteReplaced
            case .rejected:
                nil
            }
        default:
            guard canDispatch(action, in: context) else { return nil }
            guard dispatch(action, in: context) else { return nil }
            return .dismissPalette
        }
    }
}
