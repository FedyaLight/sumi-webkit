import Foundation
import SumiDomain

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
        guard tabManager.splitGroupStore.group(id: group.id) == group else {
            return false
        }
        guard let resolution = SplitShortcutMemberResolver.resolve(
                  memberID: memberID,
                  in: group,
                  windowState: windowState,
                  tabManager: tabManager
              ) else { return false }
        guard let launcher = launcherPlacement.prepareRestorations(
                  for: [resolution.member]
              ) else { return false }

        let sourceGroups = tabManager.splitGroupStore.groups
        guard let index = sourceGroups.firstIndex(of: group) else { return false }
        var replacementGroups = sourceGroups
        if let remaining = group.removingMember(memberID) {
            replacementGroups[index] = remaining
        } else {
            replacementGroups.remove(at: index)
        }
        let retiringPinID: UUID?
        if preserveLiveInstance {
            retiringPinID = nil
        } else {
            guard case .shortcutPin(let pinID) = memberID else { return false }
            let liveTab = tabManager.liveShortcutTabs.tab(
                for: pinID, in: windowState.id
            )
            guard liveTab == nil || tabManager.runtimePorts != nil
            else { return false }
            retiringPinID = liveTab == nil ? nil : pinID
        }

        let targetPresentsGroup = windowState.splitSelection?.groupID == group.id
        let settlesTargetWindow = preserveLiveInstance || targetPresentsGroup
        let terminalParticipants: WindowSplitPresentationTerminalParticipants =
            settlesTargetWindow
                ? [SplitShortcutMemberRestoreHandoffReceipt(
                    window: windowState,
                    publish: performImmediateVisualHandoff
                )]
                : []
        guard let presentation = presentations.prepareSettlementAgainstSource(
            previousGroups: [group],
            sourceGroups: sourceGroups,
            replacementGroups: replacementGroups,
            affectedGroupIDs: [group.id],
            standaloneMembers: preserveLiveInstance
                ? [windowState.id: memberID] : [:],
            unavailableMembers: preserveLiveInstance || !targetPresentsGroup
                ? [:] : [windowState.id: [memberID]],
            requiredWindows: settlesTargetWindow
                ? [windowState.id: windowState] : [:],
            terminalParticipants: terminalParticipants,
            sessionWriteUrgency: .immediate
        ) else { return false }
        guard let topology = tabManager.splitGroupMutations.prepareReplaceAll(
            expected: sourceGroups,
            with: replacementGroups
        ) else { return false }

        let retirement: ReversibleShortcutLiveTabRetirement?
        if let retiringPinID {
            guard let prepared = tabManager.shortcutLiveTabRetirement
                .prepareReversibleRetirement(
                    pinId: retiringPinID,
                    in: windowState.id
                ) else {
                _ = presentation.cancelPrepared()
                topology.rollback()
                return false
            }
            retirement = prepared
        } else {
            retirement = nil
        }
        let bindingMode: ShortcutSplitLauncherComposedBindingMode
        if let retirement {
            guard let exclusion = retirement.bindingExclusion else {
                _ = presentation.cancelPrepared()
                _ = retirement.cancelPrepared()
                topology.rollback()
                return false
            }
            bindingMode = .consumingExactRetirement(exclusion)
        } else {
            bindingMode = .preservingLiveBindings
        }
        guard let move = launcher.applyForComposedResidenceAggregate(
            bindingMode: bindingMode
        ) else {
            _ = presentation.cancelPrepared()
            _ = retirement?.cancelPrepared()
            topology.rollback()
            return false
        }
        guard move.admitPresentationIdentity(to: presentation) else {
            _ = move.cancelPrepared()
            _ = presentation.cancelPrepared()
            _ = retirement?.cancelPrepared()
            topology.rollback()
            return false
        }
        guard let outcome = move.executeRestore(
            presentation: presentation,
            retirement: retirement,
            topology: topology,
            retirementService: tabManager.shortcutLiveTabRetirement,
            folderOpenState: tabManager.folderOpenState
        ) else { return false }
        return outcome.wasAccepted
    }
}
