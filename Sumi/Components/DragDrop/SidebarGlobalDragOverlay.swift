import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarGlobalDragOverlay: NSViewRepresentable {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) var windowState

    func makeNSView(context: Context) -> SidebarDragNSView {
        let view = SidebarDragNSView()
        view.browserManager = browserManager
        view.windowState = windowState
        return view
    }

    func updateNSView(_ nsView: SidebarDragNSView, context: Context) {
        nsView.browserManager = browserManager
        nsView.windowState = windowState
    }
}

struct SidebarDropResolution: Equatable {
    let slot: DropZoneSlot
    let targetSpaceId: UUID?
    let targetProfileId: UUID?
    let folderIntent: FolderDropIntent
    let activeHoveredFolderId: UUID?
}

@MainActor
enum SidebarDropResolver {
    private static let folderContainThreshold: CGFloat = 0.2
    private static let rowStride: CGFloat = SidebarRowLayout.rowHeight

    static func resolve(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        let hoveredPage = state.hoveredInteractivePage(at: location)
        if hoveredPage == nil {
            state.requestGeometryRefresh()
        }
        return resolve(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage
        )
    }

    private static func resolve(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution {
        if let essentialsResolution = resolveEssentials(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage
        ) {
            return essentialsResolution
        }

        if let folderResolution = resolveFolderTarget(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage
        ) {
            return folderResolution
        }

        if let pinnedResolution = resolveSpacePinnedTarget(
            location: location,
            state: state,
            hoveredPage: hoveredPage
        ) {
            return pinnedResolution
        }

        if let regularResolution = resolveRegularTarget(
            location: location,
            state: state,
            hoveredPage: hoveredPage
        ) {
            return regularResolution
        }

        return SidebarDropResolution(
            slot: .empty,
            targetSpaceId: nil,
            targetProfileId: nil,
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    @discardableResult
    static func updateState(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        state.updateDragLocation(location)
        let resolution = resolve(
            location: location,
            state: state,
            draggedItem: draggedItem
        )
        state.hoveredSlot = resolution.slot
        state.folderDropIntent = resolution.folderIntent
        state.activeHoveredFolderId = resolution.activeHoveredFolderId
        state.updateEssentialsPreviewState(
            at: location,
            resolution: resolution.slot
        )
        return resolution
    }

    private static func resolveSpacePinnedTarget(
        location: CGPoint,
        state: SidebarDragState,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage,
              let pinnedFrame = state.sectionFrame(for: .spacePinned, in: hoveredPage.spaceId),
              pinnedFrame.contains(location) else {
            return nil
        }

        let localY = max(0, location.y - pinnedFrame.minY)
        return SidebarDropResolution(
            slot: .spacePinned(
                spaceId: hoveredPage.spaceId,
                slot: midpointSlotIndex(localY: localY)
            ),
            targetSpaceId: hoveredPage.spaceId,
            targetProfileId: hoveredPage.profileId,
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func resolveFolderTarget(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage else { return nil }
        let targets = state.folderDropTargets.values
            .filter { $0.spaceId == hoveredPage.spaceId }
            .sorted { lhs, rhs in
            let leftY = lhs.headerFrame?.minY ?? lhs.bodyFrame?.minY ?? lhs.afterFrame?.minY ?? .greatestFiniteMagnitude
            let rightY = rhs.headerFrame?.minY ?? rhs.bodyFrame?.minY ?? rhs.afterFrame?.minY ?? .greatestFiniteMagnitude
            if leftY != rightY { return leftY < rightY }
            return lhs.folderId.uuidString < rhs.folderId.uuidString
        }

        for target in targets {
            if let headerFrame = target.headerFrame, headerFrame.contains(location) {
                return resolveFolderHeader(
                    target,
                    frame: headerFrame,
                    location: location,
                    draggedItem: draggedItem
                )
            }

            if let bodyFrame = target.bodyFrame, bodyFrame.contains(location) {
                return resolveFolderBody(
                    target,
                    frame: bodyFrame,
                    location: location,
                    draggedItem: draggedItem
                )
            }

            if let afterFrame = target.afterFrame, afterFrame.contains(location) {
                return resolveFolderAfter(
                    target,
                    draggedItem: draggedItem
                )
            }
        }

        return nil
    }

    private static func resolveFolderHeader(
        _ target: SidebarFolderDropTargetMetrics,
        frame: CGRect,
        location: CGPoint,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        if draggedItem?.kind == .folder, draggedItem?.tabId == target.folderId {
            return emptyResolution
        }

        let ratio = frame.height > 0 ? (location.y - frame.minY) / frame.height : 0.5
        if ratio < folderContainThreshold {
            return SidebarDropResolution(
                slot: .spacePinned(spaceId: target.spaceId, slot: target.topLevelIndex),
                targetSpaceId: target.spaceId,
                targetProfileId: nil,
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        }

        if ratio > 1 - folderContainThreshold {
            return SidebarDropResolution(
                slot: .spacePinned(spaceId: target.spaceId, slot: target.topLevelIndex + 1),
                targetSpaceId: target.spaceId,
                targetProfileId: nil,
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        }

        guard draggedItem?.kind != .folder else {
            return emptyResolution
        }

        return containResolution(for: target)
    }

    private static func resolveFolderBody(
        _ target: SidebarFolderDropTargetMetrics,
        frame: CGRect,
        location: CGPoint,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        guard draggedItem?.kind != .folder else {
            return emptyResolution
        }

        guard target.isOpen, target.childCount > 0 else {
            return containResolution(for: target)
        }

        let localY = max(0, location.y - frame.minY)
        let safeIndex = midpointSlotIndex(localY: localY, itemCount: target.childCount)
        return SidebarDropResolution(
            slot: .folder(folderId: target.folderId, slot: safeIndex),
            targetSpaceId: target.spaceId,
            targetProfileId: nil,
            folderIntent: .insertIntoFolder(folderId: target.folderId, index: safeIndex),
            activeHoveredFolderId: target.folderId
        )
    }

    private static func resolveFolderAfter(
        _ target: SidebarFolderDropTargetMetrics,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        if draggedItem?.kind == .folder, draggedItem?.tabId == target.folderId {
            return emptyResolution
        }

        return SidebarDropResolution(
            slot: .spacePinned(spaceId: target.spaceId, slot: target.topLevelIndex + 1),
            targetSpaceId: target.spaceId,
            targetProfileId: nil,
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func containResolution(
        for target: SidebarFolderDropTargetMetrics
    ) -> SidebarDropResolution {
        SidebarDropResolution(
            slot: .folder(folderId: target.folderId, slot: target.childCount),
            targetSpaceId: target.spaceId,
            targetProfileId: nil,
            folderIntent: .contain(folderId: target.folderId),
            activeHoveredFolderId: target.folderId
        )
    }

    private static var emptyResolution: SidebarDropResolution {
        SidebarDropResolution(
            slot: .empty,
            targetSpaceId: nil,
            targetProfileId: nil,
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func resolveRegularTarget(
        location: CGPoint,
        state: SidebarDragState,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage else { return nil }
        let spaceId = hoveredPage.spaceId
        let outerFrame = state.sectionFrame(for: .spaceRegular, in: spaceId)
            ?? state.regularListHitTargets[spaceId]?.frame
        let foundSlot = resolveRegularSection(
            location: location,
            spaceId: spaceId,
            outerFrame: outerFrame,
            state: state
        )

        if foundSlot != .empty {
            return SidebarDropResolution(
                slot: foundSlot,
                targetSpaceId: spaceId,
                targetProfileId: hoveredPage.profileId,
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        }

        if let regularFrame = outerFrame,
           location.x >= regularFrame.minX,
           location.x <= regularFrame.maxX,
           location.y >= regularFrame.maxY {
            return SidebarDropResolution(
                slot: .spaceRegular(spaceId: spaceId, slot: 9999),
                targetSpaceId: spaceId,
                targetProfileId: hoveredPage.profileId,
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        }

        return nil
    }

    private static func resolveRegularSection(
        location: CGPoint,
        spaceId: UUID,
        outerFrame: CGRect?,
        state: SidebarDragState
    ) -> DropZoneSlot {
        guard let outerFrame else { return .empty }

        guard let metrics = state.regularListHitTargets[spaceId] else {
            guard outerFrame.contains(location) else {
                return .empty
            }
            let localY = location.y - outerFrame.minY
            let slotIndex = midpointSlotIndex(localY: max(0, localY))
            return .spaceRegular(spaceId: spaceId, slot: slotIndex)
        }

        guard outerFrame.contains(location) else {
            return .empty
        }

        if location.y < metrics.frame.minY {
            return .empty
        }

        guard metrics.itemCount > 0 else {
            return .spaceRegular(spaceId: spaceId, slot: 0)
        }

        if location.y <= metrics.frame.maxY {
            let localY = max(0, location.y - metrics.frame.minY)
            let slotIndex = midpointSlotIndex(localY: localY, itemCount: metrics.itemCount)
            return .spaceRegular(spaceId: spaceId, slot: slotIndex)
        }

        return .spaceRegular(spaceId: spaceId, slot: metrics.itemCount)
    }

    private static func resolveEssentials(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage,
              let metrics = state.essentialsLayoutMetricsBySpace[hoveredPage.spaceId],
              metrics.dropFrame.contains(location) else {
            _ = draggedItem
            return nil
        }
        guard metrics.canAcceptDrop || metrics.visibleItemCount > 0 else {
            return nil
        }

        let targetProfileId = hoveredPage.profileId ?? metrics.profileId
        return resolveEssentials(
            location: location,
            metrics: metrics,
            targetSpaceId: hoveredPage.spaceId,
            targetProfileId: targetProfileId
        )
    }

    private static func resolveEssentials(
        location: CGPoint,
        metrics: SidebarEssentialsLayoutMetrics,
        targetSpaceId: UUID,
        targetProfileId: UUID?
    ) -> SidebarDropResolution {
        guard metrics.visibleItemCount > 0 else {
            return SidebarDropResolution(
                slot: .essentials(slot: 0),
                targetSpaceId: targetSpaceId,
                targetProfileId: targetProfileId,
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        }

        let localX = max(0, location.x - metrics.dropFrame.minX)
        let localY = max(0, location.y - metrics.dropFrame.minY)
        let columnCount = max(metrics.columnCount, 1)
        let columnStride = metrics.itemSize.width + metrics.gridSpacing
        let rowStride = metrics.itemSize.height + metrics.gridSpacing
        let column = max(
            0,
            min(
                columnCount - 1,
                Int(floor((localX + (metrics.gridSpacing / 2)) / max(columnStride, 1)))
            )
        )
        let maxDropRowIndex = max(metrics.maxDropRowCount - 1, 0)
        let row = max(
            0,
            min(
                maxDropRowIndex,
                Int(floor((localY + (metrics.gridSpacing / 2)) / max(rowStride, 1)))
            )
        )
        let slot = max(0, min((row * columnCount) + column, metrics.visibleItemCount))

        return SidebarDropResolution(
            slot: .essentials(slot: slot),
            targetSpaceId: targetSpaceId,
            targetProfileId: targetProfileId,
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func midpointSlotIndex(localY: CGFloat, itemCount: Int? = nil) -> Int {
        let rawIndex = Int(floor((localY / rowStride) + 0.5))
        guard let itemCount else {
            return max(0, rawIndex)
        }
        return max(0, min(rawIndex, itemCount))
    }
}

class SidebarDragNSView: NSView {
    weak var browserManager: BrowserManager?
    var windowState: BrowserWindowState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string, .URL, .fileURL, NSPasteboard.PasteboardType.sumiTabItem])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Pass through all normal mouse events
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let state = SidebarDragState.shared
        if let item = SumiDragItem.fromPasteboard(sender.draggingPasteboard) {
            if state.isInternalDragSession {
                state.activeDragItemId = item.tabId
            } else {
                state.beginExternalDragSession(itemId: item.tabId)
            }
        } else if !state.isInternalDragSession {
            state.beginExternalDragSession(itemId: nil)
        }
        updateDragSlot(sender: sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragSlot(sender: sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        let state = SidebarDragState.shared
        if state.isInternalDragSession {
            state.clearHoverState()
        } else {
            state.resetInteractionState()
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let state = SidebarDragState.shared
        let draggedItem = SumiDragItem.fromPasteboard(sender.draggingPasteboard)
        let resolution = resolveDropResolution(sender: sender, draggedItem: draggedItem)

        defer {
            state.resetInteractionState()
        }

        guard let resolution,
              resolution.slot != .empty,
              let browserManager = browserManager else { return false }
        
        // Sumi Drag Resolution
        if let draggedItem {
            guard let payload = browserManager.tabManager.resolveSidebarDragPayload(for: draggedItem) else { return false }
            
            let sourceContainer = resolveSourceContainer(for: draggedItem)
            let sourceIndex = resolveSourceIndex(for: draggedItem)
            
            let operation = DragOperation(
                payload: payload,
                fromContainer: sourceContainer,
                fromIndex: sourceIndex,
                toContainer: resolution.slot.asDragContainer,
                toIndex: resolution.slot.visualIndex,
                toSpaceId: resolution.targetSpaceId,
                toProfileId: resolution.targetProfileId
            )
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                browserManager.tabManager.performSidebarDragOperation(operation)
            }
            return true
        }

        // Add additional drag payload extraction for raw URLs dropped into sidebar here

        return false
    }

    private func updateDragSlot(sender: NSDraggingInfo) {
        let draggedItem = SumiDragItem.fromPasteboard(sender.draggingPasteboard)
        _ = resolveDropResolution(sender: sender, draggedItem: draggedItem)
    }

    @discardableResult
    private func resolveDropResolution(
        sender: NSDraggingInfo,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution? {
        guard let swiftUILocation = resolvedSwiftUILocation(for: sender) else { return nil }
        let state = SidebarDragState.shared
        return SidebarDropResolver.updateState(
            location: swiftUILocation,
            state: state,
            draggedItem: draggedItem
        )
    }

    private func resolvedSwiftUILocation(for sender: NSDraggingInfo) -> CGPoint? {
        guard let window = windowState?.window else { return nil }
        let location = sender.draggingLocation
        let windowHeight = window.contentView?.bounds.height ?? window.frame.height
        return CGPoint(x: location.x, y: windowHeight - location.y)
    }
    
    // Dynamic Resolution Helpers
    private func resolveSourceContainer(for item: SumiDragItem) -> TabDragManager.DragContainer {
        guard let tabManager = browserManager?.tabManager else { return .none }
        if item.kind == .folder {
            guard let folder = tabManager.folder(by: item.tabId) else { return .none }
            // Sumi folders in sidebar exist in spacePinned natively
            return .spacePinned(folder.spaceId)
        } else {
            if let pin = tabManager.shortcutPin(by: item.tabId) {
                if pin.role == .essential { return .essentials }
                if pin.role == .spacePinned {
                    if let folderId = pin.folderId { return .folder(folderId) }
                    if let sid = pin.spaceId { return .spacePinned(sid) }
                }
            }
            
            guard let tab = tabManager.resolveDragTab(for: item.tabId) else { return .none }
            
            if tab.isPinned {
                return .essentials
            }
            if tab.isSpacePinned, let sid = tab.spaceId {
                if let folderId = tab.folderId {
                    return .folder(folderId)
                } else {
                    return .spacePinned(sid)
                }
            }
            if let sid = tab.spaceId {
                return .spaceRegular(sid)
            }
        }
        return .none
    }
    
    private func resolveSourceIndex(for item: SumiDragItem) -> Int {
        guard let tabManager = browserManager?.tabManager else { return 0 }
        if item.kind == .folder {
            guard let folder = tabManager.folder(by: item.tabId) else { return 0 }
            return tabManager.topLevelSpacePinnedItems(for: folder.spaceId).firstIndex {
                if case .folder(let existingFolder) = $0 {
                    return existingFolder.id == folder.id
                }
                return false
            } ?? 0
        } else {
            if let pin = tabManager.shortcutPin(by: item.tabId) { return pin.index }
            guard let tab = tabManager.resolveDragTab(for: item.tabId) else { return 0 }
            return tab.index
        }
    }
}
