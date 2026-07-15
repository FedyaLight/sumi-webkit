import Foundation
import SumiDomain

@MainActor
struct WindowSplitPresentationPersistedState: Equatable {
    let tabState: ShortcutConversionWindowSessionState
    let splitSelection: WindowSplitSelection?

    init(_ window: BrowserWindowState) {
        tabState = ShortcutConversionWindowSessionState(window)
        splitSelection = window.splitSelection
    }
}

@MainActor
enum WindowSplitPresentationMemberWitness {
    case regular(tabID: UUID, tab: Tab, windowID: UUID)
    case shortcut(WindowSplitPresentationShortcutWitness)

    var memberID: SplitMemberID {
        switch self {
        case .regular(let tabID, _, _): .regularTab(tabID)
        case .shortcut(let witness): witness.memberID
        }
    }

    var tab: Tab {
        switch self {
        case .regular(_, let tab, _): tab
        case .shortcut(let witness): witness.tab
        }
    }

    var windowID: UUID {
        switch self {
        case .regular(_, _, let windowID): windowID
        case .shortcut(let witness): witness.windowID
        }
    }

    func applySelection(to state: inout BrowserWindowShortcutMutationState) {
        switch self {
        case .regular(_, let tab, _):
            _ = WindowTabSelectionStateApplicator.apply(
                tab,
                to: &state,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        case .shortcut(let witness): witness.applySelection(to: &state)
        }
    }
}

@MainActor
struct WindowSplitPresentationWindowPlan {
    let window: BrowserWindowState
    let expectedWindowState: BrowserWindowShortcutMutationState
    let targetWindowState: BrowserWindowShortcutMutationState
    let memberWitnesses: [WindowSplitPresentationMemberWitness]
    let activeWitness: WindowSplitPresentationMemberWitness?
    let before: WindowSplitPresentationPersistedState

    var activeMemberID: SplitMemberID? { activeWitness?.memberID }
    var activeTab: Tab? { activeWitness?.tab }
}

/// Immutable evidence produced before the aggregate transaction begins. It
/// retains exact windows, Tabs and model snapshots, but no phase owner or
/// ambient TabManager lookup surface.
@MainActor
struct WindowSplitPresentationSettlementPlan {
    let expectedGroups: [SumiDomain.SplitGroup]
    let windows: [WindowSplitPresentationWindowPlan]
    let sessionWriteUrgency: WindowSplitSessionWriteUrgency
}
