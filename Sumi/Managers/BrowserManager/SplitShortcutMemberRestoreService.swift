import Foundation
import SumiDomain

/// Restores one durable shortcut member to its launcher placement. The exact
/// group snapshot and launcher destination are validated before the shared
/// structural transaction starts.
@MainActor
final class SplitShortcutMemberRestoreService {
    private let runtimeLease: () -> SplitShortcutRuntimeLease?
    private let launcherPlacement: ShortcutSplitLauncherPlacementService
    private let presentations: WindowSplitPresentationSynchronizer
    private let performImmediateVisualHandoff: (BrowserWindowState) -> Void

    init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        launcherPlacement: ShortcutSplitLauncherPlacementService,
        presentations: WindowSplitPresentationSynchronizer,
        performImmediateVisualHandoff: @escaping (BrowserWindowState) -> Void
    ) {
        self.runtimeLease = runtimeLease
        self.launcherPlacement = launcherPlacement
        self.presentations = presentations
        self.performImmediateVisualHandoff = performImmediateVisualHandoff
    }

    @discardableResult
    func restoreShortcutSplitMember(
        _ memberID: SplitMemberID,
        from group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState,
        preserveLiveInstance: Bool = true
    ) -> Bool {
        guard let runtime = runtimeLease() else { return false }
        let tabManager = runtime.tabManager
        guard tabManager.splitGroupStore.group(id: group.id) == group,
              let resolution = SplitShortcutMemberResolver.resolve(
                memberID: memberID,
                in: group,
                windowState: windowState,
                tabManager: tabManager
              ),
              let launcherRestoration = launcherPlacement
                .prepareRestoration(for: resolution.member) else {
            return false
        }

        let remainingGroup = group.removingMember(memberID)
        let retiringPinID: UUID?
        if preserveLiveInstance {
            retiringPinID = nil
        } else {
            guard case .shortcutPin(let pinID) = memberID,
                  tabManager.liveShortcutTabs.tab(
                    for: pinID,
                    in: windowState.id
                  ) == nil || tabManager.runtimePorts != nil else {
                return false
            }
            retiringPinID = pinID
        }

        let retirementSlot = ShortcutRetirementCommitSlot()
        let commitSideEffects: @MainActor @Sendable () -> Bool = {
            [launcherPlacement, retirementSlot] in
            guard launcherPlacement.apply(launcherRestoration) else {
                return false
            }
            guard let retiringPinID else { return true }
            guard let retirement = tabManager.shortcutLiveTabRetirement
                .prepareRetirement(
                    pinId: retiringPinID,
                    in: windowState.id
                ) else {
                preconditionFailure(
                    "Preflighted shortcut retirement lost its runtime lease"
                )
            }
            retirementSlot.prepared = retirement
            return true
        }
        let didCommit: Bool
        if let remainingGroup {
            didCommit = tabManager.splitGroupMutations.replaceAtomically(
                group,
                with: remainingGroup,
                applying: commitSideEffects
            )
        } else {
            didCommit = tabManager.splitGroupMutations.removeAtomically(
                group,
                applying: commitSideEffects
            )
        }
        guard didCommit else { return false }

        presentations.synchronize(
            previousGroups: [group],
            affectedGroupIDs: [group.id],
            standaloneMembers: preserveLiveInstance
                ? [windowState.id: memberID]
                : [:],
            unavailableMembers: preserveLiveInstance
                ? [:]
                : [windowState.id: [memberID]]
        )
        performImmediateVisualHandoff(windowState)
        if let retirement = retirementSlot.prepared {
            _ = tabManager.shortcutLiveTabRetirement.finish(retirement)
        }
        return true
    }
}

@MainActor
private final class ShortcutRetirementCommitSlot {
    var prepared: PreparedShortcutLiveTabRetirement?
}
