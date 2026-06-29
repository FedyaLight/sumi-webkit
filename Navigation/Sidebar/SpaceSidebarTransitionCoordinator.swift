import Observation
import SwiftUI

@Observable
@MainActor
final class SpaceSidebarTransitionCoordinator {
    struct Context {
        let spaces: [Space]
        let currentSpaces: @MainActor () -> [Space]
        let windowState: BrowserWindowState
        let browserContext: SidebarBrowserContext
        let dragState: SidebarDragState
        let settings: SumiSettingsService
        let allowsInteractiveWork: Bool
        let reduceMotion: Bool
    }

    private struct CompletionContext {
        let currentSpaces: @MainActor () -> [Space]
        let windowState: BrowserWindowState
        let spaceTransitions: SidebarSpaceTransitionActions
        let currentProfileId: @MainActor () -> UUID?
        let dragState: SidebarDragState
        let allowsInteractiveWork: Bool
    }

    var transitionState = SpaceSidebarTransitionState()
    var transitionSnapshot: SpaceSidebarTransitionSnapshot?

    @ObservationIgnored
    private var transitionTask: Task<Void, Never>?
    @ObservationIgnored
    private var pendingCompletionContext: CompletionContext?
    @ObservationIgnored
    private var pendingCompletionToken: UUID?

    func committedSpaceId(in context: Context) -> UUID? {
        committedSpaceId(spaces: context.spaces, windowState: context.windowState)
    }

    func visualSelectedSpaceId(in context: Context) -> UUID? {
        transitionState.visualSelectedSpaceId ?? committedSpaceId(in: context)
    }

    func usesSharedPinnedGrid(
        sourceSpace: Space,
        destinationSpace: Space,
        context: Context
    ) -> Bool {
        SpaceSidebarEssentialsPlacementPolicy.usesSharedPinnedGrid(
            sourceProfileId: resolvedPageProfileId(for: sourceSpace, context: context),
            destinationProfileId: resolvedPageProfileId(for: destinationSpace, context: context)
        )
    }

    func space(for id: UUID?, in context: Context) -> Space? {
        space(for: id, in: context.spaces)
    }

    func resolvedPageProfileId(for space: Space?, context: Context) -> UUID? {
        space?.profileId ?? context.windowState.currentProfileId ?? context.browserContext.currentProfile()?.id
    }

    func sourceOpacity(for travelProgress: Double) -> Double {
        1 - (travelProgress * 0.12)
    }

    func destinationOpacity(for travelProgress: Double) -> Double {
        0.88 + (travelProgress * 0.12)
    }

    func sourceOffsetX(width: CGFloat) -> CGFloat {
        guard transitionState.hasDestination else { return 0 }
        return -CGFloat(transitionState.direction) * width * transitionState.progress
    }

    func destinationOffsetX(width: CGFloat) -> CGFloat {
        guard transitionState.hasDestination else { return 0 }
        return CGFloat(transitionState.direction) * width * (1 - transitionState.progress)
    }

    func handleSpacesCollectionChange(_ context: Context) {
        let wasGestureActive = transitionState.isGestureActive
        let hadThemeTransition = hasActiveThemeTransition(in: context)
        let themeTransitionIdentity = activeThemeTransitionIdentity(in: context)
        transitionState.syncSpaces(
            orderedSpaceIds: context.spaces.map(\.id),
            committedSpaceId: committedSpaceId(in: context)
        )

        if wasGestureActive && !transitionState.isGestureActive {
            cancelPendingSpaceTransition()
            cancelInteractiveThemeTransitionIfNeeded(
                context: context,
                hadThemeTransition: hadThemeTransition,
                identity: themeTransitionIdentity
            )
            clearTransitionSnapshot()
        }

        guard let firstSpace = context.spaces.first else {
            cancelLocalSpaceTransitionIfNeeded(context: context, cancelTheme: true)
            return
        }

        guard let currentSpaceId = context.windowState.currentSpaceId,
              context.spaces.contains(where: { $0.id == currentSpaceId })
        else {
            context.browserContext.spaceTransitions.setActiveSpace(firstSpace, context.windowState)
            return
        }
    }

    func handleTransitionProgressFrame(
        _ progress: Double,
        transitionIdentity: SpaceTransitionIdentity?,
        context: Context
    ) {
        guard !(transitionState.trigger == .swipe && transitionState.phase == .interactive) else {
            return
        }
        guard transitionState.transitionIdentity == transitionIdentity else {
            return
        }

        guard transitionState.hasDestination,
              space(for: transitionState.sourceSpaceId, in: context) != nil,
              space(for: transitionState.destinationSpaceId, in: context) != nil
        else {
            return
        }

        updateInteractiveThemeTransitionProgress(progress, transitionIdentity: transitionIdentity, context: context)
    }

    func handleSwipeEvent(
        _ event: SpaceSwipeGestureEvent,
        context: Context
    ) {
        let orderedSpaceIds = context.spaces.map(\.id)

        switch event.phase {
        case .began:
            return

        case .changed:
            guard SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(for: event) else {
                return
            }

            if transitionState.phase == .idle {
                _ = transitionState.beginSwipeGesture(
                    from: committedSpaceId(in: context),
                    orderedSpaceIds: orderedSpaceIds
                )
            }

            guard transitionState.trigger == .swipe else { return }

            let previousDestinationSpaceId = transitionState.destinationSpaceId
            let hadThemeTransition = hasActiveThemeTransition(in: context)
            let previousThemeTransitionIdentity = activeThemeTransitionIdentity(in: context)
            transitionState.updateSwipeGesture(
                progress: event.progress,
                latchedDirection: event.direction,
                orderedSpaceIds: orderedSpaceIds
            )

            guard transitionState.destinationSpaceId != nil else {
                cancelInteractiveThemeTransitionIfNeeded(
                    context: context,
                    hadThemeTransition: hadThemeTransition,
                    identity: previousThemeTransitionIdentity
                )
                transitionState.reset()
                clearTransitionSnapshot()
                refreshCommittedSidebarDragGeometry(context: context)
                return
            }

            reconcileSwipeThemeTransition(
                previousDestinationSpaceId: previousDestinationSpaceId,
                hadThemeTransition: hadThemeTransition,
                previousThemeTransitionIdentity: previousThemeTransitionIdentity,
                context: context
            )

        case .ended:
            guard transitionState.trigger == .swipe else { return }
            if transitionState.destinationSpaceId == nil && transitionState.progress < 0.001 {
                transitionState.reset()
                clearTransitionSnapshot()
                return
            }
            settleInteractiveSpaceTransition(commit: transitionState.shouldCommitSwipeOnEnd, context: context)

        case .cancelled:
            guard transitionState.trigger == .swipe else { return }
            if transitionState.destinationSpaceId == nil && transitionState.progress < 0.001 {
                cancelInteractiveThemeTransitionIfNeeded(
                    context: context,
                    identity: activeThemeTransitionIdentity(in: context)
                )
                transitionState.reset()
                clearTransitionSnapshot()
                return
            }
            settleInteractiveSpaceTransition(commit: false, context: context)
        }
    }

    func settleInteractiveSpaceTransition(commit: Bool, context: Context) {
        guard transitionState.isGestureActive else { return }

        transitionState.markSettling()
        let targetProgress = commit ? 1.0 : 0.0

        withAnimation(spaceSwitchAnimation(reduceMotion: context.reduceMotion)) {
            transitionState.updateProgress(targetProgress)
        }

        scheduleTransitionCompletion(
            after: SpaceSidebarRenderPolicy.completionDelay,
            commit: commit,
            context: context
        )
    }

    func switchSpace(
        to targetSpace: Space,
        context: Context
    ) {
        guard transitionState.beginClick(
            from: committedSpaceId(in: context),
            to: targetSpace.id,
            orderedSpaceIds: context.spaces.map(\.id)
        ),
        let sourceSpace = space(for: transitionState.sourceSpaceId, in: context),
        let destinationSpace = space(for: transitionState.destinationSpaceId, in: context)
        else {
            return
        }

        cancelPendingSpaceTransition()
        captureTransitionSnapshot(
            sourceSpace: sourceSpace,
            destinationSpace: destinationSpace,
            context: context
        )
        startInteractiveThemeTransition(from: sourceSpace, to: destinationSpace, context: context)
        updateInteractiveThemeTransitionProgress(0, context: context)

        withAnimation(spaceSwitchAnimation(reduceMotion: context.reduceMotion)) {
            transitionState.updateProgress(1)
        }

        scheduleTransitionCompletion(
            after: SpaceSidebarRenderPolicy.completionDelay,
            commit: true,
            context: context
        )
    }

    func cancelLocalSpaceTransitionIfNeeded(context: Context, cancelTheme: Bool) {
        cancelPendingSpaceTransition()
        if cancelTheme {
            cancelInteractiveThemeTransitionIfNeeded(context: context)
        }
        transitionState.reset()
        clearTransitionSnapshot()
        refreshCommittedSidebarDragGeometry(context: context)
    }

    func handleCommittedSpaceChange(_ context: Context) {
        guard transitionState.isGestureActive,
              let sourceSpaceId = transitionState.sourceSpaceId,
              context.windowState.currentSpaceId != sourceSpaceId
        else {
            refreshCommittedSidebarDragGeometryIfInteractive(context: context)
            return
        }

        let hadThemeTransition = hasActiveThemeTransition(in: context)
        let themeTransitionIdentity = activeThemeTransitionIdentity(in: context)
        cancelPendingSpaceTransition()
        cancelInteractiveThemeTransitionIfNeeded(
            context: context,
            hadThemeTransition: hadThemeTransition,
            identity: themeTransitionIdentity
        )
        transitionState.reset()
        clearTransitionSnapshot()
        refreshCommittedSidebarDragGeometry(context: context)
    }

    func refreshCommittedSidebarDragGeometryIfInteractive(context: Context) {
        guard context.allowsInteractiveWork else { return }
        refreshCommittedSidebarDragGeometry(context: context)
    }

    func refreshCommittedSidebarDragGeometry(context: Context) {
        refreshCommittedSidebarDragGeometry(
            spaces: context.spaces,
            windowState: context.windowState,
            dragState: context.dragState,
            fallbackProfileId: context.browserContext.currentProfile()?.id,
            allowsInteractiveWork: context.allowsInteractiveWork
        )
    }

    func cancelPendingSpaceTransition() {
        transitionTask?.cancel()
        transitionTask = nil
        pendingCompletionContext = nil
        pendingCompletionToken = nil
    }

    private func scheduleTransitionCompletion(
        after duration: Double,
        commit: Bool,
        context: Context
    ) {
        cancelPendingSpaceTransition()
        let destinationSpaceId = transitionState.destinationSpaceId
        let transitionIdentity = transitionState.transitionIdentity
        let hadThemeTransition = hasActiveThemeTransition(in: context)
        let completionToken = UUID()
        let spaceTransitions = context.browserContext.spaceTransitions
        let currentProfile = context.browserContext.currentProfile

        pendingCompletionContext = CompletionContext(
            currentSpaces: context.currentSpaces,
            windowState: context.windowState,
            spaceTransitions: spaceTransitions,
            currentProfileId: {
                currentProfile()?.id
            },
            dragState: context.dragState,
            allowsInteractiveWork: context.allowsInteractiveWork
        )
        pendingCompletionToken = completionToken

        transitionTask = Task { @MainActor [weak self, completionToken] in
            let nanoseconds = UInt64(max(duration, 0) * 1_000_000_000)
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else { return }

            self?.finishScheduledSpaceTransition(
                commit: commit,
                destinationSpaceId: destinationSpaceId,
                transitionIdentity: transitionIdentity,
                hadThemeTransition: hadThemeTransition,
                token: completionToken
            )
        }
    }

    private func spaceSwitchAnimation(reduceMotion: Bool) -> Animation {
        SidebarMotionPolicy.spaceSwitchAnimation(
            for: SidebarMotionPolicy.currentMode(reduceMotion: reduceMotion)
        ) ?? .linear(duration: 0)
    }

    private func hasActiveThemeTransition(in context: Context) -> Bool {
        transitionState.hasDestination || context.windowState.isInteractiveSpaceTransition
    }

    private func activeThemeTransitionIdentity(in context: Context) -> SpaceTransitionIdentity? {
        transitionState.transitionIdentity ?? context.windowState.interactiveSpaceTransitionIdentity
    }

    private func startInteractiveThemeTransition(
        from sourceSpace: Space,
        to destinationSpace: Space,
        context: Context
    ) {
        let identity = SpaceTransitionIdentity(
            sourceSpaceId: sourceSpace.id,
            destinationSpaceId: destinationSpace.id
        )
        if let activeIdentity = context.browserContext.spaceTransitions.beginInteractiveSpaceTransition(
            sourceSpace,
            destinationSpace,
            identity,
            context.windowState
        ) {
            transitionState.bindTransitionIdentity(activeIdentity)
        }
    }

    private func updateInteractiveThemeTransitionProgress(
        _ progress: Double,
        transitionIdentity: SpaceTransitionIdentity? = nil,
        context: Context
    ) {
        context.browserContext.spaceTransitions.updateInteractiveSpaceTransition(
            progress,
            transitionIdentity ?? transitionState.transitionIdentity,
            context.windowState
        )
    }

    private func cancelInteractiveThemeTransitionIfNeeded(
        context: Context,
        hadThemeTransition: Bool? = nil,
        identity: SpaceTransitionIdentity? = nil
    ) {
        let shouldCancel = hadThemeTransition ?? hasActiveThemeTransition(in: context)
        guard shouldCancel else { return }
        context.browserContext.spaceTransitions.cancelInteractiveSpaceTransition(
            identity ?? activeThemeTransitionIdentity(in: context),
            context.windowState
        )
    }

    private func cancelInteractiveThemeTransitionIfNeeded(
        context: CompletionContext,
        hadThemeTransition: Bool,
        identity: SpaceTransitionIdentity?
    ) {
        guard hadThemeTransition else { return }
        context.spaceTransitions.cancelInteractiveSpaceTransition(identity, context.windowState)
    }

    private func reconcileSwipeThemeTransition(
        previousDestinationSpaceId: UUID?,
        hadThemeTransition: Bool,
        previousThemeTransitionIdentity: SpaceTransitionIdentity?,
        context: Context
    ) {
        guard let sourceSpace = space(for: transitionState.sourceSpaceId, in: context) else {
            return
        }

        if let destinationSpaceId = transitionState.destinationSpaceId,
           let destinationSpace = space(for: destinationSpaceId, in: context) {
            if previousDestinationSpaceId != destinationSpaceId
                || !context.windowState.isInteractiveSpaceTransition {
                cancelPendingSpaceTransition()
                captureTransitionSnapshot(
                    sourceSpace: sourceSpace,
                    destinationSpace: destinationSpace,
                    context: context
                )
                startInteractiveThemeTransition(from: sourceSpace, to: destinationSpace, context: context)
            } else if transitionSnapshot == nil {
                captureTransitionSnapshot(
                    sourceSpace: sourceSpace,
                    destinationSpace: destinationSpace,
                    context: context
                )
            }

            updateInteractiveThemeTransitionProgress(transitionState.progress, context: context)
            return
        }

        if previousDestinationSpaceId != nil || hadThemeTransition {
            cancelInteractiveThemeTransitionIfNeeded(
                context: context,
                hadThemeTransition: true,
                identity: previousThemeTransitionIdentity
            )
            clearTransitionSnapshot()
        }
    }

    private func finishScheduledSpaceTransition(
        commit: Bool,
        destinationSpaceId: UUID?,
        transitionIdentity: SpaceTransitionIdentity?,
        hadThemeTransition: Bool,
        token: UUID
    ) {
        guard pendingCompletionToken == token,
              let context = pendingCompletionContext else {
            return
        }

        guard transitionState.isGestureActive else {
            discardScheduledSpaceTransition(context: context)
            return
        }

        if let sourceSpaceId = transitionState.sourceSpaceId,
           context.windowState.currentSpaceId != sourceSpaceId {
            discardScheduledSpaceTransition(context: context)
            return
        }

        if let transitionIdentity {
            let isCurrentTransition = transitionState.transitionIdentity == transitionIdentity
                && context.windowState.windowThemeState.matchesInteractiveSpaceTransition(transitionIdentity)
                && context.windowState.currentSpaceId == transitionIdentity.sourceSpaceId
            guard isCurrentTransition else {
                discardScheduledSpaceTransition(context: context)
                return
            }
        }

        // Reset the local render mode before publishing the committed space.
        // Otherwise the destination can briefly rebuild as a transition snapshot,
        // leaving non-drag-capable AppKit row owners under the visible sidebar.
        let completedDestinationSpaceId = transitionState.finishTransition(commit: commit)
        let currentSpaces = context.currentSpaces()

        if commit,
           let destinationSpaceId = completedDestinationSpaceId ?? destinationSpaceId,
           let destinationSpace = space(for: destinationSpaceId, in: currentSpaces) {
            if let transitionIdentity {
                context.spaceTransitions.setActiveSpaceFromTransition(
                    destinationSpace,
                    context.windowState,
                    transitionIdentity
                )
            } else {
                context.spaceTransitions.setActiveSpace(destinationSpace, context.windowState)
            }
        } else {
            cancelInteractiveThemeTransitionIfNeeded(
                context: context,
                hadThemeTransition: hadThemeTransition,
                identity: transitionIdentity
            )
        }

        clearTransitionSnapshot()
        refreshCommittedSidebarDragGeometry(
            spaces: currentSpaces,
            windowState: context.windowState,
            dragState: context.dragState,
            fallbackProfileId: context.currentProfileId(),
            allowsInteractiveWork: context.allowsInteractiveWork
        )
        pendingCompletionContext = nil
        pendingCompletionToken = nil
        transitionTask = nil
    }

    private func discardScheduledSpaceTransition(context: CompletionContext) {
        transitionState.reset()
        clearTransitionSnapshot()
        refreshCommittedSidebarDragGeometry(
            spaces: context.currentSpaces(),
            windowState: context.windowState,
            dragState: context.dragState,
            fallbackProfileId: context.currentProfileId(),
            allowsInteractiveWork: context.allowsInteractiveWork
        )
        pendingCompletionContext = nil
        pendingCompletionToken = nil
        transitionTask = nil
    }

    private func captureTransitionSnapshot(
        sourceSpace: Space,
        destinationSpace: Space,
        context: Context
    ) {
        if transitionSnapshot?.matches(
            sourceSpaceId: sourceSpace.id,
            destinationSpaceId: destinationSpace.id
        ) == true {
            return
        }

        transitionSnapshot = SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: sourceSpace,
            destinationSpace: destinationSpace,
            browserContext: context.browserContext,
            windowState: context.windowState,
            settings: context.settings
        )
    }

    private func clearTransitionSnapshot() {
        transitionSnapshot = nil
    }

    private func committedSpaceId(spaces: [Space], windowState: BrowserWindowState) -> UUID? {
        if let currentSpaceId = windowState.currentSpaceId,
           spaces.contains(where: { $0.id == currentSpaceId }) {
            return currentSpaceId
        }
        return spaces.first?.id
    }

    private func space(for id: UUID?, in spaces: [Space]) -> Space? {
        guard let id else { return nil }
        return spaces.first(where: { $0.id == id })
    }

    private func refreshCommittedSidebarDragGeometry(
        spaces: [Space],
        windowState: BrowserWindowState,
        dragState: SidebarDragState,
        fallbackProfileId: UUID?,
        allowsInteractiveWork: Bool
    ) {
        guard allowsInteractiveWork else { return }
        guard transitionState.phase == .idle,
              let committedSpace = space(
                for: committedSpaceId(spaces: spaces, windowState: windowState),
                in: spaces
              ) else {
            return
        }

        dragState.beginPendingGeometryEpoch(
            expectedSpaceId: committedSpace.id,
            profileId: committedSpace.profileId ?? windowState.currentProfileId ?? fallbackProfileId
        )
    }
}
