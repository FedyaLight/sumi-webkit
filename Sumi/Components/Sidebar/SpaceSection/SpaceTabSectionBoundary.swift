import CoreGraphics
import SwiftUI

/// Complete layout state for the pinned↔regular boundary. Both the live surface
/// and its transition snapshot consume this value, so visibility and heights
/// cannot drift between the two adapters.
struct SpaceTabSectionBoundaryLayout: Equatable {
    static let hairlineHeight: CGFloat = 1
    static let separatorPadding: CGFloat = 10
    /// Half a row of empty space above the separator when the space has no pinned
    /// content. It keeps the hairline (and the hovered Clear button) clear of
    /// the scroll content's top edge, and gives a drop target for turning a
    /// regular tab into a pinned one.
    static let emptyPinnedTopPadding: CGFloat = SidebarRowLayout.rowHeight / 2

    let showsSeparator: Bool
    let topPadding: CGFloat
    let separatorHeight: CGFloat
    let bottomPadding: CGFloat

    init(
        hasPinnedContent: Bool,
        regularTabCount: Int,
        supportsPinnedContent: Bool = true
    ) {
        let hasVisiblePinnedContent = supportsPinnedContent && hasPinnedContent
        showsSeparator = supportsPinnedContent && regularTabCount > 0
        topPadding = hasVisiblePinnedContent
            ? (showsSeparator ? Self.separatorPadding : SidebarRowLayout.rowGap)
            : (showsSeparator ? Self.emptyPinnedTopPadding : 0)
        separatorHeight = showsSeparator ? Self.hairlineHeight : 0
        bottomPadding = showsSeparator ? Self.separatorPadding : 0
    }
}

/// Shared boundary structure with renderer-specific separator content.
struct SpaceTabSectionBoundary<Separator: View>: View {
    let layout: SpaceTabSectionBoundaryLayout
    @ViewBuilder let separator: () -> Separator

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.topPadding)
            if layout.showsSeparator {
                separator()
                    .frame(height: layout.separatorHeight)
            }
            Color.clear.frame(height: layout.bottomPadding)
        }
    }
}
