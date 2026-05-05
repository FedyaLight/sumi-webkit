import SwiftUI

// MARK: - Geometry tracking (deferred)

/// Publishes geometry into `SidebarDragState` on the next main run loop turn so SwiftUI does not emit
/// "Publishing changes from within view updates" during layout/preference application.
@MainActor
private enum SidebarDragStateDeferredGeometry {
    static func setPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int,
        _ frame: CGRect?
    ) {
        SidebarDragState.shared.schedulePageGeometry(
            spaceId: spaceId,
            profileId: profileId,
            frame: frame,
            renderMode: renderMode,
            generation: generation
        )
    }

    static func setSectionFrame(
        spaceId: UUID,
        section: SidebarSectionPrefix,
        generation: Int,
        _ frame: CGRect?
    ) {
        SidebarDragState.shared.scheduleSectionFrame(
            spaceId: spaceId,
            section: section,
            frame: frame,
            generation: generation
        )
    }

    static func updateFolderDropTarget(
        isActive: Bool,
        folderId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        region: SidebarFolderDragRegion,
        frame: CGRect,
        generation: Int
    ) {
        SidebarDragState.shared.scheduleFolderDropTarget(
            folderId: folderId,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            childCount: childCount,
            isOpen: isOpen,
            region: region,
            frame: frame,
            isActive: isActive,
            generation: generation
        )
    }

    static func removeFolderDropTarget(folderId: UUID, region: SidebarFolderDragRegion, generation: Int) {
        SidebarDragState.shared.scheduleFolderDropTarget(
            folderId: folderId,
            spaceId: UUID(),
            topLevelIndex: 0,
            childCount: 0,
            isOpen: false,
            region: region,
            frame: nil,
            isActive: false,
            generation: generation
        )
    }

    static func updateTopLevelPinnedItemTarget(
        isActive: Bool,
        itemId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        frame: CGRect,
        generation: Int
    ) {
        SidebarDragState.shared.scheduleTopLevelPinnedItemTarget(
            itemId: itemId,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            frame: frame,
            isActive: isActive,
            generation: generation
        )
    }

    static func removeTopLevelPinnedItemTarget(itemId: UUID, generation: Int) {
        SidebarDragState.shared.scheduleTopLevelPinnedItemTarget(
            itemId: itemId,
            spaceId: UUID(),
            topLevelIndex: 0,
            frame: nil,
            isActive: false,
            generation: generation
        )
    }

    static func updateFolderChildDropTarget(
        isActive: Bool,
        folderId: UUID,
        childId: UUID,
        index: Int,
        frame: CGRect,
        generation: Int
    ) {
        SidebarDragState.shared.scheduleFolderChildDropTarget(
            folderId: folderId,
            childId: childId,
            index: index,
            frame: frame,
            isActive: isActive,
            generation: generation
        )
    }

    static func removeFolderChildDropTarget(childId: UUID, generation: Int) {
        SidebarDragState.shared.scheduleFolderChildDropTarget(
            folderId: UUID(),
            childId: childId,
            index: 0,
            frame: nil,
            isActive: false,
            generation: generation
        )
    }

    static func updateRegularListHitTarget(spaceId: UUID, frame: CGRect, itemCount: Int, generation: Int) {
        SidebarDragState.shared.scheduleRegularListHitTarget(
            spaceId: spaceId,
            frame: frame,
            itemCount: itemCount,
            generation: generation
        )
    }

    static func removeRegularListHitTarget(spaceId: UUID, generation: Int) {
        SidebarDragState.shared.scheduleRegularListHitTarget(
            spaceId: spaceId,
            frame: nil,
            itemCount: 0,
            generation: generation
        )
    }

    static func updateEssentialsLayoutMetrics(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect,
        dropFrame: CGRect,
        dropSlotFrames: [SidebarEssentialsDropSlotMetrics],
        itemCount: Int,
        columnCount: Int,
        firstSyntheticRowSlot: Int? = nil,
        rowCount: Int,
        itemSize: CGSize,
        gridSpacing: CGFloat,
        canAcceptDrop: Bool,
        visibleItemCount: Int,
        visibleRowCount: Int,
        maxDropRowCount: Int,
        generation: Int
    ) {
        SidebarDragState.shared.scheduleEssentialsLayoutMetrics(
            spaceId: spaceId,
            profileId: profileId,
            frame: frame,
            dropFrame: dropFrame,
            dropSlotFrames: dropSlotFrames,
            itemCount: itemCount,
            columnCount: columnCount,
            firstSyntheticRowSlot: firstSyntheticRowSlot,
            rowCount: rowCount,
            itemSize: itemSize,
            gridSpacing: gridSpacing,
            canAcceptDrop: canAcceptDrop,
            visibleItemCount: visibleItemCount,
            visibleRowCount: visibleRowCount,
            maxDropRowCount: maxDropRowCount,
            generation: generation
        )
    }

    static func removeEssentialsLayoutMetrics(spaceId: UUID, generation: Int) {
        SidebarDragState.shared.scheduleEssentialsLayoutMetrics(
            spaceId: spaceId,
            profileId: nil,
            frame: nil,
            dropFrame: nil,
            itemCount: 0,
            columnCount: 1,
            rowCount: 1,
            itemSize: .zero,
            gridSpacing: 0,
            canAcceptDrop: false,
            visibleItemCount: 0,
            visibleRowCount: 0,
            maxDropRowCount: 0,
            generation: generation
        )
    }
}

// MARK: - Geometry Tracking

struct SidebarPageGeometryReporter: ViewModifier {
    let spaceId: UUID
    let profileId: UUID?
    let renderMode: SidebarPageGeometryRenderMode
    let generation: Int
    let isEnabled: Bool
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        let shouldReport = isEnabled && renderMode == .interactive
        content
            .background {
                if shouldReport {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                SidebarDragStateDeferredGeometry.setPageGeometry(
                                    spaceId: spaceId,
                                    profileId: profileId,
                                    renderMode: renderMode,
                                    generation: generation,
                                    newFrame
                                )
                            }
                            .onChange(of: generation) { _, newGeneration in
                                SidebarDragStateDeferredGeometry.setPageGeometry(
                                    spaceId: spaceId,
                                    profileId: profileId,
                                    renderMode: renderMode,
                                    generation: newGeneration,
                                    geo.frame(in: .global)
                                )
                            }
                            .onChange(of: dragState.geometryRevision) { _, _ in
                                SidebarDragStateDeferredGeometry.setPageGeometry(
                                    spaceId: spaceId,
                                    profileId: profileId,
                                    renderMode: renderMode,
                                    generation: generation,
                                    geo.frame(in: .global)
                                )
                            }
                            .onAppear {
                                SidebarDragStateDeferredGeometry.setPageGeometry(
                                    spaceId: spaceId,
                                    profileId: profileId,
                                    renderMode: renderMode,
                                    generation: generation,
                                    geo.frame(in: .global)
                                )
                            }
                            .onDisappear {
                                SidebarDragStateDeferredGeometry.setPageGeometry(
                                    spaceId: spaceId,
                                    profileId: profileId,
                                    renderMode: renderMode,
                                    generation: generation,
                                    nil
                                )
                            }
                    }
                }
            }
    }
}

struct SidebarSectionGeometryReporter: ViewModifier {
    let spaceId: UUID
    let section: SidebarSectionPrefix
    let generation: Int
    let isEnabled: Bool
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        content
            .background {
                if isEnabled {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                SidebarDragStateDeferredGeometry.setSectionFrame(
                                    spaceId: spaceId,
                                    section: section,
                                    generation: generation,
                                    newFrame
                                )
                            }
                            .onChange(of: generation) { _, newGeneration in
                                SidebarDragStateDeferredGeometry.setSectionFrame(
                                    spaceId: spaceId,
                                    section: section,
                                    generation: newGeneration,
                                    geo.frame(in: .global)
                                )
                            }
                            .onChange(of: dragState.geometryRevision) { _, _ in
                                SidebarDragStateDeferredGeometry.setSectionFrame(
                                    spaceId: spaceId,
                                    section: section,
                                    generation: generation,
                                    geo.frame(in: .global)
                                )
                            }
                            .onAppear {
                                SidebarDragStateDeferredGeometry.setSectionFrame(
                                    spaceId: spaceId,
                                    section: section,
                                    generation: generation,
                                    geo.frame(in: .global)
                                )
                            }
                            .onDisappear {
                                SidebarDragStateDeferredGeometry.setSectionFrame(
                                    spaceId: spaceId,
                                    section: section,
                                    generation: generation,
                                    nil
                                )
                            }
                    }
                }
            }
    }
}

extension View {
    func sidebarPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarPageGeometryReporter(
                spaceId: spaceId,
                profileId: profileId,
                renderMode: renderMode,
                generation: generation,
                isEnabled: isEnabled
            )
        )
    }

    func sidebarSectionGeometry(
        for section: SidebarSectionPrefix,
        spaceId: UUID,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarSectionGeometryReporter(
                spaceId: spaceId,
                section: section,
                generation: generation,
                isEnabled: isEnabled
            )
        )
    }

    func sidebarFolderDropGeometry(
        folderId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        region: SidebarFolderDragRegion,
        generation: Int,
        isActive: Bool = true
    ) -> some View {
        modifier(
            SidebarFolderDropGeometryReporter(
                folderId: folderId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                childCount: childCount,
                isOpen: isOpen,
                region: region,
                isActive: isActive,
                generation: generation
            )
        )
    }

    func sidebarTopLevelPinnedItemGeometry(
        itemId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        generation: Int,
        isActive: Bool = true
    ) -> some View {
        modifier(
            SidebarTopLevelPinnedItemGeometryReporter(
                itemId: itemId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                generation: generation,
                isActive: isActive
            )
        )
    }

    func sidebarFolderChildDropGeometry(
        spaceId: UUID,
        folderId: UUID,
        childId: UUID,
        index: Int,
        generation: Int,
        isActive: Bool = true
    ) -> some View {
        modifier(
            SidebarFolderChildDropGeometryReporter(
                spaceId: spaceId,
                folderId: folderId,
                childId: childId,
                index: index,
                generation: generation,
                isActive: isActive
            )
        )
    }

    func sidebarRegularListHitGeometry(
        for spaceId: UUID,
        itemCount: Int,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarRegularListHitGeometryReporter(
                spaceId: spaceId,
                itemCount: itemCount,
                generation: generation,
                isEnabled: isEnabled
            )
        )
    }

    func sidebarEssentialsLayoutGeometry(
        spaceId: UUID,
        profileId: UUID?,
        itemCount: Int,
        columnCount: Int,
        firstSyntheticRowSlot: Int? = nil,
        rowCount: Int,
        visibleItemCount: Int,
        visibleRowCount: Int,
        maxDropRowCount: Int,
        dropFrame: CGRect,
        dropSlotFrames: [SidebarEssentialsDropSlotMetrics] = [],
        itemSize: CGSize,
        gridSpacing: CGFloat,
        canAcceptDrop: Bool,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarEssentialsLayoutGeometryReporter(
                spaceId: spaceId,
                profileId: profileId,
                itemCount: itemCount,
                columnCount: columnCount,
                firstSyntheticRowSlot: firstSyntheticRowSlot,
                rowCount: rowCount,
                visibleItemCount: visibleItemCount,
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount,
                dropFrame: dropFrame,
                dropSlotFrames: dropSlotFrames,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                canAcceptDrop: canAcceptDrop,
                generation: generation,
                isEnabled: isEnabled
            )
        )
    }
}

struct SidebarFolderDropGeometryReporter: ViewModifier {
    let folderId: UUID
    let spaceId: UUID
    let topLevelIndex: Int
    let childCount: Int
    let isOpen: Bool
    let region: SidebarFolderDragRegion
    let isActive: Bool
    let generation: Int
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        let shouldReport = isActive
            && dragState.shouldCollectDetailedGeometry(spaceId: spaceId, profileId: nil)
        content
            .background {
                if shouldReport {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                update(frame: newFrame)
                            }
                            .onChange(of: topLevelIndex) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: childCount) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: isOpen) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: generation) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: dragState.isDragging) { _, isDragging in
                                if isDragging {
                                    update(frame: geo.frame(in: .global))
                                }
                            }
                            .onChange(of: dragState.geometryRevision) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onAppear {
                                update(frame: geo.frame(in: .global))
                            }
                            .onDisappear {
                                SidebarDragStateDeferredGeometry.removeFolderDropTarget(
                                    folderId: folderId,
                                    region: region,
                                    generation: generation
                                )
                            }
                    }
                }
            }
    }

    private func update(frame: CGRect) {
        SidebarDragStateDeferredGeometry.updateFolderDropTarget(
            isActive: isActive,
            folderId: folderId,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            childCount: childCount,
            isOpen: isOpen,
            region: region,
            frame: frame,
            generation: generation
        )
    }
}

struct SidebarTopLevelPinnedItemGeometryReporter: ViewModifier {
    let itemId: UUID
    let spaceId: UUID
    let topLevelIndex: Int
    let generation: Int
    let isActive: Bool
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        let shouldReport = isActive
            && dragState.shouldCollectDetailedGeometry(spaceId: spaceId, profileId: nil)
        content
            .background {
                if shouldReport {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                update(frame: newFrame)
                            }
                            .onChange(of: topLevelIndex) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: generation) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: dragState.geometryRevision) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onAppear {
                                update(frame: geo.frame(in: .global))
                            }
                            .onDisappear {
                                SidebarDragStateDeferredGeometry.removeTopLevelPinnedItemTarget(
                                    itemId: itemId,
                                    generation: generation
                                )
                            }
                    }
                }
            }
    }

    private func update(frame: CGRect) {
        SidebarDragStateDeferredGeometry.updateTopLevelPinnedItemTarget(
            isActive: isActive,
            itemId: itemId,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            frame: frame,
            generation: generation
        )
    }
}

struct SidebarFolderChildDropGeometryReporter: ViewModifier {
    let spaceId: UUID
    let folderId: UUID
    let childId: UUID
    let index: Int
    let generation: Int
    let isActive: Bool
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        let shouldReport = isActive
            && dragState.shouldCollectDetailedGeometry(spaceId: spaceId, profileId: nil)
        content
            .background {
                if shouldReport {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                update(frame: newFrame)
                            }
                            .onChange(of: index) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: generation) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: dragState.geometryRevision) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onAppear {
                                update(frame: geo.frame(in: .global))
                            }
                            .onDisappear {
                                SidebarDragStateDeferredGeometry.removeFolderChildDropTarget(
                                    childId: childId,
                                    generation: generation
                                )
                            }
                    }
                }
            }
    }

    private func update(frame: CGRect) {
        SidebarDragStateDeferredGeometry.updateFolderChildDropTarget(
            isActive: isActive,
            folderId: folderId,
            childId: childId,
            index: index,
            frame: frame,
            generation: generation
        )
    }
}

struct SidebarRegularListHitGeometryReporter: ViewModifier {
    let spaceId: UUID
    let itemCount: Int
    let generation: Int
    let isEnabled: Bool
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        let shouldReport = isEnabled
            && dragState.shouldCollectDetailedGeometry(spaceId: spaceId, profileId: nil)
        content
            .background {
                if shouldReport {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                update(frame: newFrame)
                            }
                            .onChange(of: itemCount) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: generation) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: dragState.geometryRevision) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onAppear {
                                update(frame: geo.frame(in: .global))
                            }
                            .onDisappear {
                                SidebarDragStateDeferredGeometry.removeRegularListHitTarget(
                                    spaceId: spaceId,
                                    generation: generation
                                )
                            }
                    }
                }
            }
    }

    private func update(frame: CGRect) {
        if isEnabled {
            SidebarDragStateDeferredGeometry.updateRegularListHitTarget(
                spaceId: spaceId,
                frame: frame,
                itemCount: itemCount,
                generation: generation
            )
        } else {
            SidebarDragStateDeferredGeometry.removeRegularListHitTarget(
                spaceId: spaceId,
                generation: generation
            )
        }
    }
}

private struct SidebarEssentialsLayoutGeometrySignature: Equatable {
    let itemCount: Int
    let columnCount: Int
    let firstSyntheticRowSlot: Int?
    let rowCount: Int
    let visibleItemCount: Int
    let visibleRowCount: Int
    let maxDropRowCount: Int
    let dropFrame: CGRect
    let dropSlotFrames: [SidebarEssentialsDropSlotMetrics]
    let itemSize: CGSize
    let gridSpacing: CGFloat
    let canAcceptDrop: Bool
    let generation: Int
    let isEnabled: Bool

    static func == (
        lhs: SidebarEssentialsLayoutGeometrySignature,
        rhs: SidebarEssentialsLayoutGeometrySignature
    ) -> Bool {
        lhs.itemCount == rhs.itemCount
            && lhs.columnCount == rhs.columnCount
            && lhs.firstSyntheticRowSlot == rhs.firstSyntheticRowSlot
            && lhs.rowCount == rhs.rowCount
            && lhs.visibleItemCount == rhs.visibleItemCount
            && lhs.visibleRowCount == rhs.visibleRowCount
            && lhs.maxDropRowCount == rhs.maxDropRowCount
            && lhs.dropFrame == rhs.dropFrame
            && lhs.dropSlotFrames == rhs.dropSlotFrames
            && lhs.itemSize == rhs.itemSize
            && lhs.gridSpacing == rhs.gridSpacing
            && lhs.canAcceptDrop == rhs.canAcceptDrop
            && lhs.generation == rhs.generation
            && lhs.isEnabled == rhs.isEnabled
    }
}

struct SidebarEssentialsLayoutGeometryReporter: ViewModifier {
    let spaceId: UUID
    let profileId: UUID?
    let itemCount: Int
    let columnCount: Int
    let firstSyntheticRowSlot: Int?
    let rowCount: Int
    let visibleItemCount: Int
    let visibleRowCount: Int
    let maxDropRowCount: Int
    let dropFrame: CGRect
    let dropSlotFrames: [SidebarEssentialsDropSlotMetrics]
    let itemSize: CGSize
    let gridSpacing: CGFloat
    let canAcceptDrop: Bool
    let generation: Int
    let isEnabled: Bool
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        let signature = geometrySignature
        let shouldReport = isEnabled
            && dragState.shouldCollectDetailedGeometry(spaceId: spaceId, profileId: profileId)
        content
            .background {
                if shouldReport {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global)) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: signature) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onChange(of: dragState.geometryRevision) { _, _ in
                                update(frame: geo.frame(in: .global))
                            }
                            .onAppear {
                                update(frame: geo.frame(in: .global))
                            }
                            .onDisappear {
                                SidebarDragStateDeferredGeometry.removeEssentialsLayoutMetrics(
                                    spaceId: spaceId,
                                    generation: generation
                                )
                            }
                    }
                }
            }
    }

    private var geometrySignature: SidebarEssentialsLayoutGeometrySignature {
        SidebarEssentialsLayoutGeometrySignature(
            itemCount: itemCount,
            columnCount: columnCount,
            firstSyntheticRowSlot: firstSyntheticRowSlot,
            rowCount: rowCount,
            visibleItemCount: visibleItemCount,
            visibleRowCount: visibleRowCount,
            maxDropRowCount: maxDropRowCount,
            dropFrame: dropFrame,
            dropSlotFrames: dropSlotFrames,
            itemSize: itemSize,
            gridSpacing: gridSpacing,
            canAcceptDrop: canAcceptDrop,
            generation: generation,
            isEnabled: isEnabled
        )
    }

    private func update(frame: CGRect) {
        if isEnabled {
            let resolvedDropFrame = CGRect(
                x: frame.minX + dropFrame.minX,
                y: frame.minY + dropFrame.minY,
                width: dropFrame.width,
                height: dropFrame.height
            )
            let resolvedDropSlotFrames = dropSlotFrames.map { slotFrame in
                SidebarEssentialsDropSlotMetrics(
                    slot: slotFrame.slot,
                    frame: CGRect(
                        x: frame.minX + slotFrame.frame.minX,
                        y: frame.minY + slotFrame.frame.minY,
                        width: slotFrame.frame.width,
                        height: slotFrame.frame.height
                    )
                )
            }
            SidebarDragStateDeferredGeometry.updateEssentialsLayoutMetrics(
                spaceId: spaceId,
                profileId: profileId,
                frame: frame,
                dropFrame: resolvedDropFrame,
                dropSlotFrames: resolvedDropSlotFrames,
                itemCount: itemCount,
                columnCount: columnCount,
                firstSyntheticRowSlot: firstSyntheticRowSlot,
                rowCount: rowCount,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                canAcceptDrop: canAcceptDrop,
                visibleItemCount: visibleItemCount,
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount,
                generation: generation
            )
        } else {
            SidebarDragStateDeferredGeometry.removeEssentialsLayoutMetrics(
                spaceId: spaceId,
                generation: generation
            )
        }
    }
}
