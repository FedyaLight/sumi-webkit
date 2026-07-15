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
struct WindowSplitPresentationMemberWitness {
    let memberID: SplitMemberID
    let tab: Tab
    let windowID: UUID
}

@MainActor
struct WindowSplitPresentationWindowPlan {
    let window: BrowserWindowState
    let expectedWindowState: BrowserWindowShortcutMutationState
    let targetWindowState: BrowserWindowShortcutMutationState
    let memberWitnesses: [WindowSplitPresentationMemberWitness]
    let activeMemberID: SplitMemberID?
    let activeTab: Tab?
    let before: WindowSplitPresentationPersistedState
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
