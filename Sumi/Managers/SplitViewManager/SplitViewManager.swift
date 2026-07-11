import CoreGraphics
import Foundation
import SumiDomain
import SwiftUI

@MainActor
struct SplitViewRuntime {
    let tabManager: @MainActor () -> TabManager?
    let currentTab: @MainActor (BrowserWindowState) -> Tab?
    let selectTabWithoutPersistence: @MainActor (
        Tab,
        BrowserWindowState
    ) -> Void
    let restoreShortcutMember: @MainActor (
        SplitMemberID,
        SumiDomain.SplitGroup,
        BrowserWindowState
    ) -> Bool
    let refreshCompositor: @MainActor (BrowserWindowState) -> Void
    let schedulePersistWindowSession: @MainActor (BrowserWindowState) -> Void
    let focusFloatingBar: @MainActor (
        BrowserWindowState,
        FloatingBarPresentationReason
    ) -> Void
    let notifications: @MainActor () -> (any BrowserNotificationPresenting)?
}

/// SwiftUI/AppKit adapter for the split subsystem. Durable state, layout
/// mutations, drop transactions, runtime projection and preview state live in
/// separate collaborators; this object only exposes the UI-facing commands.
@MainActor
final class SplitViewManager: ObservableObject {
    typealias WindowSplitPreviewState = SplitPreviewSession.WindowState

    weak var windowRegistry: WindowRegistry?
    private var runtime: SplitViewRuntime?

    private lazy var previewSession = SplitPreviewSession(
        activeWindowID: { [weak self] in
            self?.windowRegistry?.activeWindow?.id
        },
        publishActiveWindowChange: { [weak self] in
            self?.objectWillChange.send()
        },
        refreshWindow: { [weak self] windowID in
            self?.refreshCompositor(in: windowID)
        }
    )

    private lazy var memberResolver = SplitRuntimeMemberResolver(
        tabManager: { [weak self] in self?.tabManager }
    )

    private lazy var windowQuery = WindowSplitQuery(
        tabManager: { [weak self] in self?.tabManager },
        windowState: { [weak self] in self?.windowRegistry?.windows[$0] },
        previewIsActive: { [weak self] in
            self?.previewSession.isActive(in: $0) == true
        }
    )

    private lazy var presentationSynchronizer =
        WindowSplitPresentationSynchronizer(
            tabManager: { [weak self] in self?.tabManager },
            windows: { [weak self] in
                guard let values = self?.windowRegistry?.windows.values else {
                    return []
                }
                return Array(values)
            },
            selectTabWithoutPersistence: { [weak self] tab, windowState in
                self?.runtime?.selectTabWithoutPersistence(tab, windowState)
            },
            publishWindowChange: { [weak self] windowID in
                self?.previewSession.syncPublishedState(
                    for: windowID,
                    force: true
                )
            },
            refreshCompositor: { [weak self] windowState in
                self?.runtime?.refreshCompositor(windowState)
            },
            persistWindowSession: { [weak self] windowState in
                self?.runtime?.schedulePersistWindowSession(windowState)
            }
        )

    private lazy var launcherPlacement = ShortcutSplitLauncherPlacementService(
        tabManager: { [weak self] in self?.tabManager }
    )

    private lazy var dissolution = SplitGroupDissolutionService(
        tabManager: { [weak self] in self?.tabManager },
        launcherPlacement: launcherPlacement,
        presentations: presentationSynchronizer
    )

    private lazy var layoutWeightMutations = SplitLayoutWeightMutationService(
        tabManager: { [weak self] in self?.tabManager }
    )

    private lazy var dropTargets = SplitDropTargetService(
        tabManager: { [weak self] in self?.tabManager },
        windowState: { [weak self] in self?.windowRegistry?.windows[$0] },
        currentTab: { [weak self] in self?.runtime?.currentTab($0) },
        query: windowQuery,
        memberResolver: memberResolver
    )

    private lazy var dropService = SplitDropService(
        tabManager: { [weak self] in self?.tabManager },
        memberResolver: memberResolver,
        launcherPlacement: launcherPlacement,
        reconcileAfterCommit: { [weak self] effect in
            self?.finishDropCommit(effect)
        },
        notifyLimit: { [weak self] windowState in
            self?.runtime?.notifications()?
                .presentSplitViewLimitNotification(in: windowState)
        }
    )

    private lazy var layoutService = SplitLayoutService(
        tabManager: { [weak self] in self?.tabManager },
        query: windowQuery,
        weightMutations: layoutWeightMutations,
        presentations: presentationSynchronizer,
        dissolution: dissolution,
        launcherPlacement: launcherPlacement,
        restoreShortcutMember: { [weak self] memberID, group, windowState in
            self?.runtime?.restoreShortcutMember(
                memberID,
                group,
                windowState
            ) == true
        }
    )

    private lazy var emptySplits = EmptySplitService(
        tabManager: { [weak self] in self?.tabManager },
        currentTab: { [weak self] in self?.runtime?.currentTab($0) },
        memberResolver: memberResolver,
        dropService: dropService,
        focusFloatingBar: { [weak self] windowState, reason in
            self?.runtime?.focusFloatingBar(windowState, reason)
        }
    )

    init(runtime: SplitViewRuntime? = nil) {
        self.runtime = runtime
    }

    func attach(runtime: SplitViewRuntime) {
        self.runtime = runtime
    }

    private var tabManager: TabManager? {
        runtime?.tabManager()
    }

    // MARK: Read model

    func previewState(for windowID: UUID) -> WindowSplitPreviewState {
        previewSession.state(for: windowID)
    }

    func splitGroup(for windowID: UUID) -> SumiDomain.SplitGroup? {
        windowQuery.group(in: windowID)
    }

    func visibleTabIds(for windowID: UUID) -> [UUID] {
        windowQuery.visibleTabIDs(in: windowID)
    }

    func isSplit(for windowID: UUID) -> Bool {
        windowQuery.group(in: windowID) != nil
    }

    func isTabVisibleInSplit(_ tabID: UUID, in windowID: UUID) -> Bool {
        windowQuery.contains(tabID: tabID, in: windowID)
    }

    func isTabActiveInSplit(_ tabID: UUID, in windowID: UUID) -> Bool {
        windowQuery.isActive(tabID: tabID, in: windowID)
    }

    func isPreviewActive(for windowID: UUID) -> Bool {
        previewSession.isActive(in: windowID)
    }

    // MARK: Layout lifecycle

    func updateSplitLayoutWeights(
        expectedGroup: SumiDomain.SplitGroup,
        path: [Int],
        weights: [Double],
        for windowID: UUID
    ) {
        layoutService.updateWeights(
            expectedGroup: expectedGroup,
            path: path,
            weights: weights,
            in: windowID
        )
    }

    func refreshPublishedState(for windowID: UUID) {
        previewSession.syncPublishedState(for: windowID)
    }

    func cleanupWindow(_ windowID: UUID) {
        emptySplits.removeWindow(windowID)
        previewSession.removeWindow(windowID)
    }

    func handleTabClosure(_ tabID: UUID) {
        handleTabClosures([tabID])
    }

    func handleTabClosures(_ tabIDs: Set<UUID>) {
        dropTargets.clearCachedLayouts()
        layoutService.handleClosedRegularTabs(tabIDs)
    }

    func unsplitActiveGroup(for windowID: UUID) {
        guard let windowState = windowRegistry?.windows[windowID] else {
            return
        }
        layoutService.unsplit(in: windowState)
    }

    func setLayoutKind(_ layoutKind: SplitLayoutKind, for windowID: UUID) {
        layoutService.setLayoutKind(layoutKind, in: windowID)
    }

    func expandSplitPane(tabId: UUID, in windowState: BrowserWindowState) {
        layoutService.expand(tabID: tabId, in: windowState)
    }

    // MARK: Empty split

    func createEmptySplit(
        side: SplitDropSide = .right,
        in windowState: BrowserWindowState,
        floatingBarPresentationReason: FloatingBarPresentationReason = .keyboard
    ) {
        emptySplits.create(
            side: side,
            in: windowState,
            floatingBarReason: floatingBarPresentationReason
        )
    }

    func commitEmptySplitPlaceholder(
        tabId: UUID,
        in windowState: BrowserWindowState
    ) {
        emptySplits.commit(tabID: tabId, in: windowState.id)
    }

    @discardableResult
    func replaceEmptySplitPlaceholder(
        with tab: Tab,
        in windowState: BrowserWindowState
    ) -> Bool {
        emptySplits.replace(with: tab, in: windowState)
    }

    @discardableResult
    func cancelEmptySplitPlaceholder(
        in windowState: BrowserWindowState
    ) -> Bool {
        emptySplits.cancel(in: windowState)
    }

    // MARK: Drop commit and hit testing

    func enterSplit(
        with tab: Tab,
        placeOn side: SplitDropSide = .right,
        in windowState: BrowserWindowState
    ) {
        guard let current = runtime?.currentTab(windowState),
              current.representsSumiNativeSurface == false,
              let targetMemberID = windowState.splitSelection?.activeMemberID
                ?? memberResolver.memberID(for: current) else {
            return
        }
        _ = dropService.drop(
            tab,
            on: SplitDropTarget(
                targetMemberID: targetMemberID,
                side: side,
                targetRect: .zero,
                intent: .firstSplit
            ),
            in: windowState
        )
    }

    @discardableResult
    func dropTab(
        _ tab: Tab,
        placeOn side: SplitDropSide,
        relativeTo targetTabID: UUID?,
        in windowState: BrowserWindowState
    ) -> Bool {
        let targetMemberID = targetTabID.flatMap {
            windowQuery.memberID(for: $0, in: windowState.id)
                ?? memberResolver.memberID(forLookupID: $0)
        } ?? windowState.splitSelection?.activeMemberID
            ?? runtime?.currentTab(windowState).flatMap {
                memberResolver.memberID(for: $0)
            }
        guard let targetMemberID else { return false }
        return dropService.drop(
            tab,
            on: SplitDropTarget(
                targetMemberID: targetMemberID,
                side: side,
                targetRect: .zero
            ),
            in: windowState
        )
    }

    @discardableResult
    func dropTab(
        _ tab: Tab,
        on target: SplitDropTarget,
        in windowState: BrowserWindowState
    ) -> Bool {
        dropService.drop(tab, on: target, in: windowState)
    }

    func dropTarget(
        at location: CGPoint,
        in bounds: CGRect,
        for windowID: UUID,
        draggedMemberID: SplitMemberID? = nil,
        draggedTabId: UUID? = nil
    ) -> SplitDropTarget? {
        dropTargets.target(
            at: location,
            in: bounds,
            windowID: windowID,
            draggedMemberID: draggedMemberID,
            draggedLookupID: draggedTabId
        )
    }

    func beginPreview(
        targetRect: CGRect? = nil,
        style: SplitDropPreviewStyle = .edge,
        for windowID: UUID
    ) {
        previewSession.begin(
            targetRect: targetRect,
            style: style,
            in: windowID
        )
    }

    func updatePreview(
        targetRect: CGRect?,
        style: SplitDropPreviewStyle = .edge,
        for windowID: UUID
    ) {
        previewSession.update(
            targetRect: targetRect,
            style: style,
            in: windowID
        )
    }

    func endPreview(for windowID: UUID) {
        previewSession.end(in: windowID)
    }

    private func finishDropCommit(_ effect: SplitDropCommitEffect) {
        presentationSynchronizer.synchronize(
            previousGroups: effect.previousGroups,
            affectedGroupIDs: effect.affectedGroupIDs,
            preferredSelections: [
                effect.callerWindowID: WindowSplitSelection(
                    groupID: effect.targetGroupID,
                    activeMemberID: effect.preferredActiveMemberID
                )
            ]
        )
    }

    private func refreshCompositor(in windowID: UUID) {
        guard let windowState = windowRegistry?.windows[windowID] else {
            return
        }
        runtime?.refreshCompositor(windowState)
    }
}
