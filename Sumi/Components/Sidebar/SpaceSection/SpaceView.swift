//
//  SpaceView.swift
//  Sumi
//

import SwiftUI

enum SpaceViewRenderMode {
    case interactive
    case transitionSnapshot

    var isInteractive: Bool {
        self == .interactive
    }

    var debugDescription: String {
        switch self {
        case .interactive:
            return "interactive"
        case .transitionSnapshot:
            return "transitionSnapshot"
        }
    }
}

struct SpaceView: View {
    let space: Space
    let renderMode: SpaceViewRenderMode
    let allowsInteraction: Bool
    @Binding var isSidebarHovered: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @ObservedObject var dragState = SidebarDragState.shared
    @State var viewportHeight: CGFloat = 0
    @State var totalContentHeight: CGFloat = 0
    @State var scrollOffset: CGFloat = 0
    @State var isScrollIndicatorActive: Bool = false
    @State var scrollIndicatorHideTask: Task<Void, Never>?
    @State var deferredScrollStateMutation = SidebarDeferredStateMutation<CGRect>()
    @State var deferredContentHeightMutation = SidebarDeferredStateMutation<CGFloat>()
    @State var isNewTabHovered = false
    @Environment(\.resolvedThemeContext) var themeContext

    let onActivateTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void
    let onPinTab: (Tab) -> Void
    let onMoveTabUp: (Tab) -> Void
    let onMoveTabDown: (Tab) -> Void
    let onMuteTab: (Tab) -> Void
    @EnvironmentObject var splitManager: SplitViewManager

    private var outerWidth: CGFloat {
        let visibleWidth = windowState.sidebarWidth
        if visibleWidth > 0 {
            return visibleWidth
        }
        let fallbackWidth = browserManager.getSavedSidebarWidth(for: windowState)
        return max(fallbackWidth, 0)
    }

    var innerWidth: CGFloat {
        max(outerWidth - 16, 0)
    }

    var isInteractive: Bool {
        renderMode.isInteractive && allowsInteraction
    }


    var body: some View {
        let _ = browserManager.tabStructuralRevision

        VStack(spacing: 4) {
            SpaceTitle(space: space, isAppKitInteractionEnabled: isInteractive)

            mainContentContainer
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .coordinateSpace(name: "SpaceViewCoordinateSpace")
        .transaction { transaction in
            if dragState.isCompletingDrop {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}
