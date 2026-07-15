import Foundation
import SumiDomain

@MainActor
struct WindowSplitPresentationSettlementInput {
    let previousGroups: [SumiDomain.SplitGroup]
    let replacementGroups: [SumiDomain.SplitGroup]
    let affectedGroupIDs: Set<UUID>
    let standaloneMembers: [UUID: SplitMemberID]
    let unavailableMembers: [UUID: Set<SplitMemberID>]
    let requiredWindows: [UUID: BrowserWindowState]
    let sessionWriteUrgency: WindowSplitSessionWriteUrgency
}

@MainActor
struct WindowSplitPresentationDraft {
    let window: BrowserWindowState
    let activeMemberID: SplitMemberID?
    let splitSelection: WindowSplitSelection?
    let materializedMembers: [SplitMemberID]
}

/// Immutable topology decision and activation request set. No Tab has been
/// staged and no shortcut-activation phase owner exists at this point.
@MainActor
struct WindowSplitPresentationDraftPlan {
    let drafts: [WindowSplitPresentationDraft]
    let activationRequests: [
        ShortcutPresentationActivationService.Request
    ]
    let expectedGroups: [SumiDomain.SplitGroup]
    let sessionWriteUrgency: WindowSplitSessionWriteUrgency
}
