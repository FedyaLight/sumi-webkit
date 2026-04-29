//
//  SpacesList.swift
//  Sumi
//
//  Created by Maciek Bagiński on 04/08/2025.
//  Refactored by Aether on 15/11/2025.
//

import SwiftUI

struct SpacesList: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    let visualSelectedSpaceId: UUID?
    let onSelectSpace: (Space) -> Void
    @State private var availableWidth: CGFloat = 0
    @State private var deferredAvailableWidthMutation = SidebarDeferredStateMutation<CGFloat>()
    @State private var hoveredSpaceId: UUID?
    @State private var showPreview: Bool = false
    @State private var isHoveringList: Bool = false
    @State private var reorderState = SpaceReorderDragState()

    private var layoutMode: SpacesListLayoutMode {
        let spaces = windowState.isIncognito
            ? windowState.ephemeralSpaces
            : browserManager.tabManager.spaces
        if sumiSettings.sidebarCompactSpaces {
            return .compact
        }
        return SpacesListLayoutMode.determine(
            spacesCount: spaces.count,
            availableWidth: availableWidth
        )
    }

    private var visibleSpaces: [Space] {
        if windowState.isIncognito {
            return windowState.ephemeralSpaces
        }
        return browserManager.tabManager.spaces
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
                spacesContent(spaces: visibleSpaces)
            }
            .coordinateSpace(name: SpaceReorderCoordinateSpace.name)
            .onPreferenceChange(SpaceReorderItemFramePreferenceKey.self) { frames in
                reorderState.updateItemFrames(frames)
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
            .animation(.easeInOut(duration: 0.3), value: visibleSpaces.map(\.id))
    }

    private var previewTextColor: Color {
        themeContext.tokens(settings: sumiSettings).secondaryText
    }

    private var canReorderSpaces: Bool {
        !windowState.isIncognito && visibleSpaces.count > 1
    }

    private func spacesContent(spaces: [Space]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                SpacesListItem(
                    space: space,
                    isActive: visualSelectedSpaceId == space.id,
                    compact: layoutMode == .compact,
                    isFaded: reorderState.draggedSpaceId == space.id && reorderState.isDragging,
                    onSelect: {
                        guard !reorderState.isDragging else { return }
                        guard !reorderState.consumeSuppressedClick(for: space.id) else { return }
                        onSelectSpace(space)
                    },
                    onHoverChange: { isHovering in
                        handleHoverChange(isHovering, for: space)
                    }
                )
                .environmentObject(browserManager)
                .environment(windowState)
                .background(SpaceReorderItemFrameReporter(spaceId: space.id))
                .simultaneousGesture(
                    spaceReorderGesture(for: space, spaces: spaces),
                    including: canReorderSpaces ? .gesture : .none
                )
                .id(space.id)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))

                if index != spaces.count - 1 {
                    Spacer()
                        .frame(minWidth: 1, maxWidth: 8)
                        .layoutPriority(-1)
                }
            }
        }
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
            spaceDropMarker(spaces: spaces)
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

    private func spaceReorderGesture(for space: Space, spaces: [Space]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(SpaceReorderCoordinateSpace.name))
            .onChanged { value in
                let didBeginDrag = reorderState.update(
                    spaceId: space.id,
                    location: value.location,
                    orderedSpaceIds: spaces.map(\.id)
                )
                if didBeginDrag {
                    showPreview = false
                    hoveredSpaceId = nil
                    windowState.sidebarInteractionState.syncSidebarItemDrag(true)
                }
            }
            .onEnded { _ in
                let wasDragging = reorderState.isDragging
                let drop = reorderState.finish(orderedSpaceIds: spaces.map(\.id))
                if wasDragging {
                    windowState.sidebarInteractionState.syncSidebarItemDrag(false)
                }
                if let drop {
                    browserManager.tabManager.reorderSpace(
                        spaceId: drop.spaceId,
                        to: drop.targetIndex
                    )
                }
            }
    }

    @ViewBuilder
    private func spacePreviewOverlay(spaces: [Space]) -> some View {
        if showPreview,
           let hoveredId = hoveredSpaceId,
           hoveredId != visualSelectedSpaceId,
           let hoveredSpace = spaces.first(where: { $0.id == hoveredId })
        {
            Text(hoveredSpace.name)
                .font(.caption)
                .foregroundStyle(previewTextColor)
                .opacity(0.7)
                .lineLimit(1)
                .id(hoveredSpace.id)
                .transition(.blur.animation(.smooth(duration: 0.2)))
                .offset(y: -20)
        }
    }

    @ViewBuilder
    private func spaceDropMarker(spaces: [Space]) -> some View {
        if let markerFrame = reorderState.markerFrame(orderedSpaceIds: spaces.map(\.id)) {
            Capsule()
                .fill(previewTextColor.opacity(0.9))
                .frame(width: markerFrame.width, height: markerFrame.height)
                .offset(x: markerFrame.minX, y: markerFrame.minY)
                .allowsHitTesting(false)
        }
    }

}

// MARK: - Layout Mode

enum SpacesListLayoutMode {
    case normal    // Full icons with spacing
    case compact   // Dots for inactive, icons for active

    static func determine(spacesCount: Int, availableWidth: CGFloat) -> Self {
        guard spacesCount > 0 else { return .normal }

        // Measurements for NavButtonStyle button with default .regular control size
        let buttonSize: CGFloat = 32.0  // NavButtonStyle .regular = 32pt
        let minSpacing: CGFloat = 4.0

        // Normal mode: all icons visible with minimum spacing
        let normalMinWidth = (CGFloat(spacesCount) * buttonSize) + (CGFloat(spacesCount - 1) * minSpacing)

        // Compact mode: 1 active icon + (n-1) dots with minimum spacing
        let dotSize: CGFloat = 6.0
        let totalDots = spacesCount - 1
        let compactMinWidth = buttonSize + (CGFloat(totalDots) * dotSize) + (CGFloat(totalDots) * minSpacing)

        // Choose mode: switch to compact only when normal mode would be too cramped
        // Stay in normal as long as we have at least minimum spacing
        if availableWidth >= normalMinWidth {
            return .normal
        } else if availableWidth >= compactMinWidth {
            return .compact
        } else {
            // Even compact doesn't fit perfectly, but use compact anyway
            return .compact
        }
    }
}
