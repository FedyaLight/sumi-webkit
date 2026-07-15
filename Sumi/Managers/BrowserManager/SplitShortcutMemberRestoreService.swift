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
        let expectedGroups = tabManager.splitGroupStore.groups
        guard let groupIndex = expectedGroups.firstIndex(where: {
            $0.id == group.id && $0 == group
        }) else { return false }
        var replacementGroups = expectedGroups
        if let remainingGroup {
            replacementGroups[groupIndex] = remainingGroup
        } else {
            replacementGroups.remove(at: groupIndex)
        }
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
        let presentationSlot = SplitPresentationCommitSlot()
        let terminalHandoff = SplitShortcutMemberRestoreHandoffReceipt(
            window: windowState,
            publish: performImmediateVisualHandoff
        )
        let commitSideEffects: @MainActor @Sendable () -> Bool = {
            [
                launcherPlacement,
                presentationSlot,
                presentations,
                retirementSlot,
                terminalHandoff
            ] in
            let retirement: ReversibleShortcutLiveTabRetirement?
            if let retiringPinID {
                guard let prepared = tabManager.shortcutLiveTabRetirement
                    .prepareReversibleRetirement(
                        pinId: retiringPinID,
                        in: windowState.id
                    ) else { return false }
                retirement = prepared
            } else {
                retirement = nil
            }
            guard let launcherReceipt = launcherPlacement
                .applyForComposedResidenceAggregate([launcherRestoration]) else {
                precondition(retirement?.rollback() ?? true)
                return false
            }
            guard let presentation = presentations.prepareSettlement(
                previousGroups: [group],
                replacementGroups: replacementGroups,
                affectedGroupIDs: [group.id],
                standaloneMembers: preserveLiveInstance
                    ? [windowState.id: memberID]
                    : [:],
                unavailableMembers: preserveLiveInstance
                    ? [:]
                    : [windowState.id: [memberID]],
                requiredWindows: [windowState.id: windowState],
                terminalParticipants: [terminalHandoff],
                sessionWriteUrgency: .immediate
            ), presentation.stage() else {
                precondition(launcherReceipt.rollback())
                precondition(retirement?.rollback() ?? true)
                return false
            }
            var participants: [
                any BrowserWindowShortcutAggregateParticipant
            ] = [presentation]
            if let retirement {
                guard launcherReceipt.isCurrent(), retirement.isCurrent(),
                      retirement.sealRuntime() else {
                    presentation.rollback()
                    precondition(launcherReceipt.rollback())
                    precondition(retirement.rollback())
                    return false
                }
                participants.insert(retirement, at: 0)
                precondition(
                    launcherReceipt.settleAndPublishModel(
                        alongside: participants
                    ),
                    "Sealed shortcut retirement lost its admitted aggregate"
                )
                retirementSlot.prepared = retirement.takePreparedResult()
            } else if launcherReceipt.settleAndPublishModel(
                alongside: participants
            ) == false {
                presentation.rollback()
                precondition(launcherReceipt.rollback())
                return false
            }
            presentationSlot.prepared = presentation
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

        guard let presentation = presentationSlot.prepared else {
            preconditionFailure("Split restore lost its terminal presentation")
        }
        presentation.publishTerminalEffects()
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

@MainActor
private final class SplitPresentationCommitSlot {
    var prepared: PreparedWindowSplitPresentationSettlement?
}

/// Prepared exact-window participant for the restore-only visual handoff. It
/// consumes one terminal presentation receipt and cannot publish twice or for
/// a same-ID replacement window.
@MainActor
private final class SplitShortcutMemberRestoreHandoffReceipt:
    WindowSplitPresentationTerminalParticipant {
    private enum State {
        case prepared
        case settled
    }

    let targetWindow: BrowserWindowState
    private let publish: (BrowserWindowState) -> Void
    private var state = State.prepared

    init(
        window: BrowserWindowState,
        publish: @escaping (BrowserWindowState) -> Void
    ) {
        targetWindow = window
        self.publish = publish
    }

    func publish(after receipt: WindowSplitPresentationTerminalWindowReceipt) {
        guard case .prepared = state,
              receipt.matches(targetWindow) else { return }
        state = .settled
        publish(targetWindow)
    }
}
