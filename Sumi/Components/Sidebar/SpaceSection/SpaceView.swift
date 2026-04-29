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
    @Binding var isSidebarHovered: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @ObservedObject var dragState = SidebarDragState.shared
    @State var canScrollUp: Bool = false
    @State var canScrollDown: Bool = false
    @State var showTopArrow: Bool = false
    @State var showBottomArrow: Bool = false
    @State var isAtTop: Bool = true
    @State var viewportHeight: CGFloat = 0
    @State var totalContentHeight: CGFloat = 0
    @State var activeTabPosition: CGRect = .zero
    @State var scrollOffset: CGFloat = 0
    @State var tabPositions: [UUID: CGRect] = [:]
    @State var lastScrollOffset: CGFloat = 0
    @State var selectionScrollGuard = SidebarSelectionScrollGuard()
    @State var preferenceUpdateCoalescer = SidebarPreferenceUpdateCoalescer()
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
        renderMode.isInteractive
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
    }
}
