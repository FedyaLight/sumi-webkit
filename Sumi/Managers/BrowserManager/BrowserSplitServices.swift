import Foundation
import SumiDomain

/// Process-lifetime split services assembled once for a browser session.
///
/// `BrowserManager` retains this behavior-free graph. Only composition roots
/// select a concrete capability from it and inject that capability into feature
/// code; the graph itself never crosses the composition boundary.
@MainActor
struct BrowserSplitServices {
    let updates: SplitWindowUpdateStream
    let query: WindowSplitQuery
    let previews: SplitPreviewSession
    let presentations: WindowSplitPresentationSynchronizer
    let launcherPlacement: ShortcutSplitLauncherPlacementService
    let layout: SplitLayoutService
    let insertion: SplitInsertionService
    let drops: SplitDropService
    let dropTargets: SplitDropTargetService
    let emptyPlaceholders: EmptySplitService
    let emptyCreation: EmptySplitCreationWorkflow
    let tabClosures: SplitTabClosureService
}

@MainActor
extension BrowserSplitServices {
    static func live(browserManager: BrowserManager) -> Self {
        let tabManager: @MainActor () -> TabManager? = {
            [weak tabManager = browserManager.tabManager] in tabManager
        }
        let currentTab: @MainActor (BrowserWindowState) -> Tab? = {
            [weak browserManager] windowState in
            browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
        }
        let updateChannel = SplitWindowUpdateStream.makeChannel()
        let updates = updateChannel.stream
        let previews = SplitPreviewSession(
            publishWindowChange: { [emitter = updateChannel.emitter] windowID in
                emitter.publish(windowID: windowID)
            },
            refreshWindow: { [weak browserManager] windowID in
                guard let windowState = browserManager?.windowRegistry?
                    .windows[windowID] else { return }
                browserManager?.shellRuntime.windowVisuals
                    .refreshCompositor(for: windowState)
            }
        )
        let query = WindowSplitQuery(
            tabManager: tabManager,
            windowState: { [weak browserManager] in
                browserManager?.windowRegistry?.windows[$0]
            },
            previewIsActive: { [previews] in
                previews.isActive(in: $0)
            }
        )
        let presentations = WindowSplitPresentationSynchronizer(
            tabManager: tabManager,
            windows: { [weak browserManager] in
                browserManager?.windowRegistry.map {
                    Array($0.windows.values)
                } ?? []
            },
            selectTabWithoutPersistence: {
                [weak browserManager] tab, windowState in
                browserManager?.applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: true,
                    updateTheme: true,
                    rememberSelection: true,
                    persistSelection: false
                )
            },
            publishWindowChange: { [emitter = updateChannel.emitter] windowID in
                emitter.publish(windowID: windowID)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowVisuals
                    .refreshCompositor(for: windowState)
            },
            scheduleWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence
                    .schedule(windowState)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence
                    .persist(windowState)
            }
        )
        let launcherPlacement = ShortcutSplitLauncherPlacementService(
            tabManager: tabManager
        )
        let memberResolver = SplitRuntimeMemberResolver(
            tabManager: tabManager
        )
        let dissolution = SplitGroupDissolutionService(
            tabManager: tabManager,
            launcherPlacement: launcherPlacement,
            presentations: presentations
        )
        let weightMutations = SplitLayoutWeightMutationService(
            tabManager: tabManager
        )
        let dropTargets = SplitDropTargetService(
            tabManager: tabManager,
            windowState: { [weak browserManager] in
                browserManager?.windowRegistry?.windows[$0]
            },
            currentTab: currentTab,
            query: query,
            memberResolver: memberResolver
        )
        let drops = SplitDropService(
            tabManager: tabManager,
            memberResolver: memberResolver,
            launcherPlacement: launcherPlacement,
            reconcileAfterCommit: { [presentations] effect in
                presentations.synchronize(
                    previousGroups: effect.previousGroups,
                    affectedGroupIDs: effect.affectedGroupIDs,
                    preferredSelections: [
                        effect.callerWindowID: WindowSplitSelection(
                            groupID: effect.targetGroupID,
                            activeMemberID: effect.preferredActiveMemberID
                        )
                    ]
                )
            },
            notifyLimit: { [weak browserManager] windowState in
                browserManager?.notificationPresenter
                    .presentSplitViewLimitNotification(in: windowState)
            }
        )
        let layout = SplitLayoutService(
            tabManager: tabManager,
            query: query,
            weightMutations: weightMutations,
            presentations: presentations,
            dissolution: dissolution,
            launcherPlacement: launcherPlacement,
            restoreShortcutMember: {
                [weak browserManager]
                memberID,
                group,
                windowState in
                browserManager?.sidebarCommandService.splitShortcuts
                    .memberRestoration.restoreShortcutSplitMember(
                        memberID,
                        from: group,
                        in: windowState
                    ) == true
            }
        )
        let emptyPlaceholders = EmptySplitService(
            tabManager: tabManager,
            currentTab: currentTab,
            memberResolver: memberResolver,
            dropService: drops
        )
        let emptyCreation = EmptySplitCreationWorkflow(
            placeholders: emptyPlaceholders,
            focusFloatingBar: { [weak browserManager] windowState, reason in
                browserManager?.urlBarBundle.floatingBar.presentation.focus(
                    in: windowState,
                    prefill: "",
                    navigateCurrentTab: true,
                    reason: reason
                )
            }
        )
        let insertion = SplitInsertionService(
            currentTab: currentTab,
            memberIsGrouped: {
                tabManager()?.splitGroupStore.group(containing: $0) != nil
            },
            members: memberResolver,
            drops: drops
        )
        let tabClosures = SplitTabClosureService(
            dropTargets: dropTargets,
            layout: layout
        )

        return Self(
            updates: updates,
            query: query,
            previews: previews,
            presentations: presentations,
            launcherPlacement: launcherPlacement,
            layout: layout,
            insertion: insertion,
            drops: drops,
            dropTargets: dropTargets,
            emptyPlaceholders: emptyPlaceholders,
            emptyCreation: emptyCreation,
            tabClosures: tabClosures
        )
    }
}
