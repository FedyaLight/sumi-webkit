//
//  SpacesList.swift
//  Sumi
//
//

import SwiftUI

struct SpacesList: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.controlSize) private var controlSize
    let browserContext: SidebarBrowserContext
    let visualSelectedSpaceId: UUID?
    let onSelectSpace: (Space) -> Void
    @State private var availableWidth: CGFloat = 0
    @State private var deferredAvailableWidthMutation = SidebarDeferredStateMutation<CGFloat>()
    @State private var hoveredSpaceId: UUID?
    @State private var showPreview: Bool = false
    @State private var isHoveringList: Bool = false
    @State private var reorderState = ReorderDragState<UUID>()

    private var metrics: SpaceStripMetrics {
        SpaceStripMetrics.resolve(for: controlSize)
    }

    private var reorderGeometry: ReorderGeometry {
        ReorderGeometry(
            axis: .horizontal,
            slotFrames: SpaceStripGeometry.make(
                itemCount: displayedSpaces.count,
                availableWidth: availableWidth,
                metrics: metrics
            ).slotFrames
        )
    }

    private var visibleSpaces: [Space] {
        if windowState.isIncognito {
            return windowState.ephemeralSpaces
        }
        return browserContext.tabManager.spaceStateOwner.spaces
    }

    private var displayedSpaces: [Space] {
        reorderState.displayOrder(visibleSpaces, id: \.id)
    }

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                deferredAvailableWidthMutation.schedule(newWidth) { resolvedWidth in
                    guard abs(availableWidth - resolvedWidth) > 0.5 else { return }
                    availableWidth = resolvedWidth
                }
            }
            .overlay {
                spacesContent(spaces: displayedSpaces)
            }
            .onChange(of: visibleSpaces.map(\.id)) { _, _ in
                if reorderState.isDragging {
                    windowState.sidebarInteractionState.syncSidebarItemDrag(false)
                }
                reorderState.reset()
            }
            .onDisappear {
                if reorderState.isDragging {
                    windowState.sidebarInteractionState.syncSidebarItemDrag(false)
                }
                reorderState.reset()
            }
            .animation(.easeInOut(duration: 0.3), value: visibleSpaces.count)
            .animation(.interactiveSpring(duration: 0.22, extraBounce: 0.05), value: displayedSpaces.map(\.id))
    }

    private var previewTextColor: Color {
        themeContext.tokens(settings: sumiSettings).secondaryText
    }

    private var canReorderSpaces: Bool {
        !windowState.isIncognito && visibleSpaces.count > 1
    }

    private func spacesContent(spaces: [Space]) -> some View {
        SpaceStripLayout(metrics: metrics) {
            ForEach(spaces, id: \.id) { space in
                SpacesListItem(
                    space: space,
                    browserContext: browserContext,
                    isActive: visualSelectedSpaceId == space.id,
                    isFaded: false,
                    metrics: metrics,
                    onSelect: {
                        guard !reorderState.isDragging else { return }
                        guard !reorderState.consumeSuppressedClick(for: space.id) else { return }
                        onSelectSpace(space)
                    },
                    onHoverChange: { isHovering in
                        handleHoverChange(isHovering, for: space)
                    }
                )
                .environment(windowState)
                .gesture(spaceInteractionGesture(for: space, spaces: spaces))
                .opacity(reorderState.hidesInlineItem(space.id) ? 0 : 1)
                .id(space.id)
                .transition(reorderState.isDragging ? .identity : .asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .coordinateSpace(name: SpaceReorderCoordinateSpace.name)
        .onHover { hovering in
            isHoveringList = hovering
            if !hovering {
                showPreview = false
                hoveredSpaceId = nil
            }
        }
        .overlay(alignment: .top) {
            spacePreviewOverlay(spaces: spaces)
        }
        .overlay(alignment: .topLeading) {
            draggedSpaceOverlay(spaces: spaces)
        }
    }

    private func handleHoverChange(_ isHovering: Bool, for space: Space) {
        guard !reorderState.isDragging else { return }

        if isHovering {
            hoveredSpaceId = space.id
            if !showPreview {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    if hoveredSpaceId == space.id && isHoveringList && !reorderState.isDragging {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showPreview = true
                        }
                    }
                }
            }
        } else if hoveredSpaceId == space.id {
            hoveredSpaceId = nil
        }
    }

    private func spaceInteractionGesture(for space: Space, spaces: [Space]) -> some Gesture {
        makeReorderDragGesture(
            id: space.id,
            coordinateSpaceName: SpaceReorderCoordinateSpace.name,
            isEnabled: { canReorderSpaces },
            orderedIDs: { spaces.map(\.id) },
            geometry: { reorderGeometry },
            state: $reorderState,
            onBeginDrag: {
                showPreview = false
                hoveredSpaceId = nil
                windowState.sidebarInteractionState.syncSidebarItemDrag(true)
            },
            onEndDrag: {
                windowState.sidebarInteractionState.syncSidebarItemDrag(false)
            },
            onCommit: { move in
                browserContext.tabManager.spaceLifecycleOwner.reorderSpace(
                    spaceId: move.id,
                    to: move.targetIndex
                )
            },
            onTap: { onSelectSpace(space) }
        )
    }

    @ViewBuilder
    private func draggedSpaceOverlay(spaces: [Space]) -> some View {
        if let draggedSpaceId = reorderState.draggedID,
           let draggedSpace = spaces.first(where: { $0.id == draggedSpaceId }),
           let frame = reorderState.draggedOverlayFrame() {
            SpacesListItem(
                space: draggedSpace,
                browserContext: browserContext,
                isActive: visualSelectedSpaceId == draggedSpace.id,
                isFaded: false,
                metrics: metrics,
                onSelect: { _ = () },
                onHoverChange: nil
            )
            .environment(windowState)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
            .animation(nil, value: reorderState.currentLocation.x)
            .zIndex(2)
        }
    }

    @ViewBuilder
    private func spacePreviewOverlay(spaces: [Space]) -> some View {
        if showPreview,
           let hoveredId = hoveredSpaceId,
           hoveredId != visualSelectedSpaceId,
           let hoveredSpace = spaces.first(where: { $0.id == hoveredId }) {
            Text(hoveredSpace.name)
                .font(.caption)
                .foregroundStyle(previewTextColor)
                .opacity(0.7)
                .lineLimit(1)
                .id(hoveredSpace.id)
                .transition(
                    .scale(scale: 0.8)
                        .combined(with: .opacity)
                        .animation(.smooth(duration: 0.2))
                )
                .offset(y: -20)
        }
    }
}
