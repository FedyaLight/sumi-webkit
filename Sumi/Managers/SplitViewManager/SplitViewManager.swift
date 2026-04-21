import SwiftUI


@MainActor
final class SplitViewManager: ObservableObject {
    enum Side { case left, right }

    // MARK: - State
    @Published var isSplit: Bool = false
    @Published var leftTabId: UUID? = nil
    @Published var rightTabId: UUID? = nil
    @Published private(set) var dividerFraction: CGFloat = 0.5 // 0.0 = all left, 1.0 = all right
    @Published var activeSide: Side? = nil
    @Published private(set) var orientation: SplitOrientation = .horizontal

    // Preview state during drag-over of the web content
    @Published var isPreviewActive: Bool = false
    @Published var previewSide: Side? = nil
    @Published var dragLocation: CGPoint? = nil // Track drag location for magnetic cards

    // Limits for divider movement
    let minFraction: CGFloat = 0.2
    let maxFraction: CGFloat = 0.8

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?

    struct WindowSplitState {
        var isSplit: Bool = false
        var leftTabId: UUID? = nil
        var rightTabId: UUID? = nil
        var dividerFraction: CGFloat = 0.5
        var isPreviewActive: Bool = false
        var previewSide: Side? = nil
        var activeSide: Side? = nil
        var dragLocation: CGPoint? = nil // Track drag location per window
        var orientation: SplitOrientation = .horizontal
    }

    private struct CommittedWindowSplitState {
        var isSplit: Bool = false
        var leftTabId: UUID? = nil
        var rightTabId: UUID? = nil
        var dividerFraction: CGFloat = 0.5
        var activeSide: Side? = nil
        var orientation: SplitOrientation = .horizontal
    }

    private struct TransientWindowSplitState {
        var isPreviewActive: Bool = false
        var previewSide: Side? = nil
        var dragLocation: CGPoint? = nil // Track drag location per window
        var liveDividerFraction: CGFloat?
    }

    // Window-specific split state
    private var committedWindowSplitStates: [UUID: CommittedWindowSplitState] = [:]
    private var transientWindowSplitStates: [UUID: TransientWindowSplitState] = [:]

    private func committedState(for windowId: UUID) -> CommittedWindowSplitState {
        committedWindowSplitStates[windowId] ?? CommittedWindowSplitState()
    }

    private func transientState(for windowId: UUID) -> TransientWindowSplitState {
        transientWindowSplitStates[windowId] ?? TransientWindowSplitState()
    }

    init(browserManager: BrowserManager? = nil) {
        self.browserManager = browserManager
    }
    
    // MARK: - Window-Aware Split Management
    
    /// Get split state for a specific window
    func getSplitState(for windowId: UUID) -> WindowSplitState {
        let committed = committedState(for: windowId)
        let transient = transientState(for: windowId)
        return WindowSplitState(
            isSplit: committed.isSplit,
            leftTabId: committed.leftTabId,
            rightTabId: committed.rightTabId,
            dividerFraction: transient.liveDividerFraction ?? committed.dividerFraction,
            isPreviewActive: transient.isPreviewActive,
            previewSide: transient.previewSide,
            activeSide: committed.activeSide,
            dragLocation: transient.dragLocation,
            orientation: committed.orientation
        )
    }
    
    /// Set split state for a specific window
    func setSplitState(_ state: WindowSplitState, for windowId: UUID) {
        committedWindowSplitStates[windowId] = CommittedWindowSplitState(
            isSplit: state.isSplit,
            leftTabId: state.leftTabId,
            rightTabId: state.rightTabId,
            dividerFraction: state.dividerFraction,
            activeSide: state.activeSide,
            orientation: state.orientation
        )
        syncPublishedStateIfNeeded(for: windowId)
        persistWindowSessionIfPossible(for: windowId)
    }

    private func setTransientState(_ state: TransientWindowSplitState, for windowId: UUID) {
        if state.isPreviewActive == false,
           state.previewSide == nil,
           state.dragLocation == nil,
           state.liveDividerFraction == nil {
            transientWindowSplitStates.removeValue(forKey: windowId)
        } else {
            transientWindowSplitStates[windowId] = state
        }
        syncPublishedStateIfNeeded(for: windowId)
    }
    
    /// Check if split is active for a specific window
    func isSplit(for windowId: UUID) -> Bool {
        return getSplitState(for: windowId).isSplit
    }
    
    /// Get left tab ID for a specific window
    func leftTabId(for windowId: UUID) -> UUID? {
        return getSplitState(for: windowId).leftTabId
    }
    
    /// Get right tab ID for a specific window
    func rightTabId(for windowId: UUID) -> UUID? {
        return getSplitState(for: windowId).rightTabId
    }
    
    /// Get divider fraction for a specific window
    func dividerFraction(for windowId: UUID) -> CGFloat {
        return getSplitState(for: windowId).dividerFraction
    }

    func orientation(for windowId: UUID) -> SplitOrientation {
        getSplitState(for: windowId).orientation
    }
    
    /// Set divider fraction for a specific window
    func setDividerFraction(_ value: CGFloat, for windowId: UUID) {
        commitDividerFraction(value, for: windowId)
    }

    func updateLiveDividerFraction(_ value: CGFloat, for windowId: UUID) {
        let clamped = min(max(value, minFraction), maxFraction)
        var transient = transientState(for: windowId)
        if abs((transient.liveDividerFraction ?? committedState(for: windowId).dividerFraction) - clamped) > 0.0001 {
            transient.liveDividerFraction = clamped
            setTransientState(transient, for: windowId)
        }
    }

    func commitDividerFraction(_ value: CGFloat, for windowId: UUID) {
        let clamped = min(max(value, minFraction), maxFraction)
        var committed = committedState(for: windowId)
        guard abs(committed.dividerFraction - clamped) > 0.0001 else {
            clearTransientDividerFraction(for: windowId)
            return
        }
        committed.dividerFraction = clamped
        committedWindowSplitStates[windowId] = committed
        clearTransientDividerFraction(for: windowId)
        syncPublishedStateIfNeeded(for: windowId)
        persistWindowSessionIfPossible(for: windowId)
    }

    private func clearTransientDividerFraction(for windowId: UUID) {
        var transient = transientState(for: windowId)
        transient.liveDividerFraction = nil
        setTransientState(transient, for: windowId)
    }

    func setOrientation(_ orientation: SplitOrientation, for windowId: UUID) {
        var state = getSplitState(for: windowId)
        guard state.orientation != orientation else { return }
        state.orientation = orientation
        setSplitState(state, for: windowId)
        if let windowState = browserManager?.windowRegistry?.windows[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
    }

    func toggleOrientation(for windowId: UUID) {
        let newOrientation: SplitOrientation = orientation(for: windowId) == .horizontal ? .vertical : .horizontal
        setOrientation(newOrientation, for: windowId)
    }

    /// Keep published shell state aligned with the active window's state
    private func syncPublishedStateIfNeeded(for windowId: UUID) {
        guard browserManager != nil, windowRegistry?.activeWindow?.id == windowId else { return }
        updatePublishedState(from: getSplitState(for: windowId))
    }

    private func updatePublishedState(from state: WindowSplitState) {
        isSplit = state.isSplit
        leftTabId = state.leftTabId
        rightTabId = state.rightTabId
        dividerFraction = state.dividerFraction
        isPreviewActive = state.isPreviewActive
        previewSide = state.previewSide
        activeSide = state.activeSide
        dragLocation = state.dragLocation
        orientation = state.orientation
    }

    func refreshPublishedState(for windowId: UUID) {
        updatePublishedState(from: getSplitState(for: windowId))
    }
    
    /// Enter split mode for a specific window
    func enterSplit(leftTabId: UUID, rightTabId: UUID, for windowId: UUID) {
        var state = getSplitState(for: windowId)
        state.isSplit = true
        state.leftTabId = leftTabId
        state.rightTabId = rightTabId
        state.dividerFraction = 0.5
        state.orientation = .horizontal
        // Set active side based on which tab is currently active in this window
        if let windowState = browserManager?.windowRegistry?.windows[windowId],
           let currentTabId = windowState.currentTabId {
            if currentTabId == leftTabId {
                state.activeSide = .left
            } else if currentTabId == rightTabId {
                state.activeSide = .right
            }
        }
        setSplitState(state, for: windowId)
        
        // Note: No need to update tab display ownership since windows are independent
        
        if let windowState = browserManager?.windowRegistry?.windows[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
        
        RuntimeDiagnostics.emit("🪟 [SplitViewManager] Entered split mode for window \(windowId)")
    }
    
    /// Exit split mode for a specific window
    func exitSplit(keep: Side, for windowId: UUID) {
        var state = getSplitState(for: windowId)
        guard state.isSplit else { return }
        
        state.isSplit = false
        state.leftTabId = nil
        state.rightTabId = nil
        state.isPreviewActive = false
        state.previewSide = nil
        state.activeSide = nil
        state.orientation = .horizontal
        setSplitState(state, for: windowId)
        
        // Note: No need to update tab display ownership since windows are independent
        
        if let windowState = browserManager?.windowRegistry?.windows[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
        
        RuntimeDiagnostics.emit("🪟 [SplitViewManager] Exited split mode for window \(windowId), keeping \(keep)")
    }
    
    /// Close a pane in a specific window
    func closePane(_ side: Side, for windowId: UUID) {
        guard let bm = browserManager else { return }
        let state = getSplitState(for: windowId)
        guard state.isSplit else { return }
        guard let windowState = bm.windowRegistry?.windows[windowId] else { return }
        
        switch side {
        case .left:
            if let rightId = state.rightTabId, let rightTab = bm.tabManager.tab(for: rightId) {
                bm.selectTab(rightTab, in: windowState)
            }
        case .right:
            if let leftId = state.leftTabId, let leftTab = bm.tabManager.tab(for: leftId) {
                bm.selectTab(leftTab, in: windowState)
            }
        }
        exitSplit(keep: side == .left ? .right : .left, for: windowId)
    }

    func cleanupWindow(_ windowId: UUID) {
        committedWindowSplitStates.removeValue(forKey: windowId)
        transientWindowSplitStates.removeValue(forKey: windowId)
        if browserManager != nil, windowRegistry?.activeWindow?.id == windowId {
            updatePublishedState(from: WindowSplitState())
        }
        RuntimeDiagnostics.emit("🪟 [SplitViewManager] Cleaned up split state for window \(windowId)")
    }
    
    /// Handle tab closure to prevent "zombie split" state
    func handleTabClosure(_ tabId: UUID) {
        // Check all windows for split state involving this tab
        for (windowId, state) in committedWindowSplitStates {
            if state.isSplit {
                if state.leftTabId == tabId {
                    RuntimeDiagnostics.emit("🪟 [SplitViewManager] Closing left pane for window \(windowId) due to tab closure")
                    exitSplit(keep: .right, for: windowId)
                } else if state.rightTabId == tabId {
                    RuntimeDiagnostics.emit("🪟 [SplitViewManager] Closing right pane for window \(windowId) due to tab closure")
                    exitSplit(keep: .left, for: windowId)
                }
            }
        }
    }

    func setDividerFraction(_ value: CGFloat) {
        if let windowId = windowRegistry?.activeWindow?.id {
            setDividerFraction(value, for: windowId)
        } else {
            let clamped = min(max(value, minFraction), maxFraction)
            if abs(clamped - dividerFraction) > 0.0001 {
                dividerFraction = clamped
            }
        }
    }

    // MARK: - Helpers
    func resolveTab(_ id: UUID?) -> Tab? {
        guard let id, let bm = browserManager else { return nil }
        return bm.tabManager.tab(for: id)
    }

    func tab(for side: Side) -> Tab? {
        switch side {
        case .left: return resolveTab(leftTabId)
        case .right: return resolveTab(rightTabId)
        }
    }

    func side(for tabId: UUID) -> Side? {
        if leftTabId == tabId { return .left }
        if rightTabId == tabId { return .right }
        return nil
    }
    
    /// Get which side a tab is on for a specific window
    func side(for tabId: UUID, in windowId: UUID) -> Side? {
        let state = getSplitState(for: windowId)
        if state.leftTabId == tabId { return .left }
        if state.rightTabId == tabId { return .right }
        return nil
    }
    
    /// Get the active side for a specific window
    func activeSide(for windowId: UUID) -> Side? {
        return getSplitState(for: windowId).activeSide
    }
    
    /// Set the active side for a specific window
    func setActiveSide(_ side: Side?, for windowId: UUID) {
        var state = getSplitState(for: windowId)
        state.activeSide = side
        setSplitState(state, for: windowId)
    }
    
    /// Update the active side based on which tab is currently active
    /// This should be called whenever a tab becomes active
    func updateActiveSide(for tabId: UUID, in windowId: UUID) {
        let state = getSplitState(for: windowId)
        guard state.isSplit else {
            // Not in split view, clear active side
            if state.activeSide != nil {
                var updatedState = state
                updatedState.activeSide = nil
                setSplitState(updatedState, for: windowId)
            }
            return
        }
        
        // Determine which side this tab is on
        let side = self.side(for: tabId, in: windowId)
        if state.activeSide != side {
            var updatedState = state
            updatedState.activeSide = side
            setSplitState(updatedState, for: windowId)
        }
    }

    // MARK: - Entry points
    func enterSplit(with tab: Tab, placeOn side: Side = .right, animate: Bool = true) {
        guard let windowState = windowRegistry?.activeWindow else { return }
        enterSplit(with: tab, placeOn: side, in: windowState, animate: animate)
    }

    func enterSplit(with tab: Tab, placeOn side: Side = .right, in windowState: BrowserWindowState, animate: Bool = true) {
        guard let bm = browserManager else { return }
        if tab.representsSumiSettingsSurface {
            return
        }
        let tm = bm.tabManager
        let windowId = windowState.id
        var state = getSplitState(for: windowId)

        func maybeDuplicateIfPinned(_ candidate: Tab, anchor: Tab?) -> Tab {
            if candidate.isShortcutLiveInstance {
                return candidate
            }
            if tm.isGlobalPinned(candidate) || tm.isSpacePinned(candidate) {
                return tm.duplicateAsRegularForSplit(from: candidate, anchor: anchor, placeAfterAnchor: true)
            }
            return candidate
        }

        if state.isSplit {
            let oppositeId = (side == .left) ? state.rightTabId : state.leftTabId
            let opposite = oppositeId.flatMap { id in tm.tab(for: id) }
            let resolved = maybeDuplicateIfPinned(tab, anchor: opposite)
            if resolved.representsSumiSettingsSurface {
                return
            }
            switch side {
            case .left: state.leftTabId = resolved.id
            case .right: state.rightTabId = resolved.id
            }
            // Set active side to the side we're placing the tab on
            state.activeSide = side
            setSplitState(state, for: windowId)
            bm.compositorManager.loadTab(resolved)
            if let ws = bm.windowRegistry?.windows[windowId] {
                bm.refreshCompositor(for: ws)
            }
            bm.selectTab(resolved, in: windowState)
            return
        }

        let current = bm.currentTab(for: windowState) ?? tm.currentTab
        guard let current else { return }
        if current.representsSumiSettingsSurface {
            return
        }

        let incomingTab: Tab
        if current.id == tab.id {
            let currentSpace =
                windowState.currentSpaceId.flatMap { id in
                    tm.spaces.first(where: { $0.id == id })
                } ?? tm.currentSpace
            incomingTab = tm.createNewTab(in: currentSpace)
        } else {
            incomingTab = tab
        }

        var leftCandidate: Tab
        var rightCandidate: Tab
        switch side {
        case .left:
            leftCandidate = incomingTab
            rightCandidate = current
        case .right:
            leftCandidate = current
            rightCandidate = incomingTab
        }

        let leftResolved = maybeDuplicateIfPinned(leftCandidate, anchor: rightCandidate)
        let rightResolved = maybeDuplicateIfPinned(rightCandidate, anchor: leftResolved)
        if leftResolved.representsSumiSettingsSurface || rightResolved.representsSumiSettingsSurface {
            return
        }

        state.isSplit = true
        state.leftTabId = leftResolved.id
        state.rightTabId = rightResolved.id
        state.orientation = .horizontal
        state.activeSide = side
        setSplitState(state, for: windowId)

        bm.compositorManager.loadTab(leftResolved)
        bm.compositorManager.loadTab(rightResolved)

        if animate {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                setDividerFraction(0.5, for: windowId)
            }
        } else {
            setDividerFraction(0.5, for: windowId)
        }

        bm.refreshCompositor(for: windowState)

        let focusedTab = (side == .left) ? leftResolved : rightResolved
        bm.selectTab(focusedTab, in: windowState)
    }

    func exitSplit(keep side: Side = .left) {
        guard browserManager != nil, let activeWindow = windowRegistry?.activeWindow else { return }
        exitSplit(keep: side, for: activeWindow.id)
    }

    func closePane(_ side: Side) {
        guard browserManager != nil, let activeWindow = windowRegistry?.activeWindow else { return }
        closePane(side, for: activeWindow.id)
    }

    func swapSides() {
        guard browserManager != nil, let activeWindow = windowRegistry?.activeWindow else { return }
        swapSides(for: activeWindow.id)
    }
    
    /// Swap sides for a specific window
    func swapSides(for windowId: UUID) {
        var state = getSplitState(for: windowId)
        guard state.isSplit else { return }
        let l = state.leftTabId
        state.leftTabId = state.rightTabId
        state.rightTabId = l
        // Swap active side too
        if let currentActiveSide = state.activeSide {
            state.activeSide = (currentActiveSide == .left) ? .right : .left
        }
        setSplitState(state, for: windowId)
        if let windowState = browserManager?.windowRegistry?.windows[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
        
        RuntimeDiagnostics.emit("🪟 [SplitViewManager] Swapped sides for window \(windowId)")
    }

    func exitSplitCompletely() {
        isSplit = false
        leftTabId = nil
        rightTabId = nil
        isPreviewActive = false
        previewSide = nil
    }

    // MARK: - Preview during drag-over
    func beginPreview(side: Side) {
        guard browserManager != nil, let windowState = windowRegistry?.activeWindow else { return }
        beginPreview(side: side, for: windowState.id)
    }

    func endPreview(cancel: Bool) {
        guard browserManager != nil, let windowState = windowRegistry?.activeWindow else { return }
        endPreview(cancel: cancel, for: windowState.id)
    }

    func beginPreview(side: Side?, for windowId: UUID) {
        var transient = transientState(for: windowId)
        transient.previewSide = side
        transient.isPreviewActive = true
        setTransientState(transient, for: windowId)
        if let windowState = browserManager?.windowRegistry?.windows[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
    }
    
    /// Update preview side when drag moves
    func updatePreviewSide(_ side: Side?, for windowId: UUID) {
        var transient = transientState(for: windowId)
        guard transient.isPreviewActive else { return }
        transient.previewSide = side
        setTransientState(transient, for: windowId)
    }
    
    /// Update drag location for magnetic card effect
    func updateDragLocation(_ location: CGPoint?, for windowId: UUID) {
        var transient = transientState(for: windowId)
        transient.dragLocation = location
        setTransientState(transient, for: windowId)
    }
    
    /// Get drag location for a specific window
    func dragLocation(for windowId: UUID) -> CGPoint? {
        return getSplitState(for: windowId).dragLocation
    }

    func endPreview(cancel: Bool, for windowId: UUID) {
        _ = cancel
        var transient = transientState(for: windowId)
        transient.isPreviewActive = false
        transient.previewSide = nil
        transient.dragLocation = nil
        setTransientState(transient, for: windowId)
        if let windowState = browserManager?.windowRegistry?.windows[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
    }

    func snapshot(for windowId: UUID) -> SplitSessionSnapshot? {
        let state = committedState(for: windowId)
        guard state.isSplit, let leftTabId = state.leftTabId, let rightTabId = state.rightTabId else {
            return nil
        }
        return SplitSessionSnapshot(
            leftTabId: leftTabId,
            rightTabId: rightTabId,
            dividerFraction: Double(state.dividerFraction),
            activeSideRawValue: serializedSide(state.activeSide),
            orientation: state.orientation
        )
    }

    func restoreSession(_ snapshot: SplitSessionSnapshot?, for windowId: UUID) {
        guard let snapshot else {
            setSplitState(WindowSplitState(), for: windowId)
            return
        }

        var state = WindowSplitState()
        state.isSplit = true
        state.leftTabId = snapshot.leftTabId
        state.rightTabId = snapshot.rightTabId
        state.dividerFraction = min(max(CGFloat(snapshot.dividerFraction), minFraction), maxFraction)
        state.activeSide = deserializeSide(snapshot.activeSideRawValue)
        state.orientation = snapshot.orientation
        setSplitState(state, for: windowId)
    }

    private func serializedSide(_ side: Side?) -> String? {
        switch side {
        case .left: return "left"
        case .right: return "right"
        case nil: return nil
        }
    }

    private func deserializeSide(_ rawValue: String?) -> Side? {
        switch rawValue {
        case "left": return .left
        case "right": return .right
        default: return nil
        }
    }

    private func persistWindowSessionIfPossible(for windowId: UUID) {
        guard let windowState = browserManager?.windowRegistry?.windows[windowId] else { return }
        browserManager?.persistWindowSession(for: windowState)
    }
}
