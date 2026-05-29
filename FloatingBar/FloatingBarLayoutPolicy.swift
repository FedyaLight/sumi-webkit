//
//  FloatingBarLayoutPolicy.swift
//  Sumi
//
//

import CoreGraphics

enum FloatingBarLayoutPolicy {
    static let idealWidth: CGFloat = 765
    static let horizontalPadding: CGFloat = 10
    static let minimumWidth: CGFloat = 200
    static let horizontalVignetteOutset: CGFloat = 56
    static let verticalVignetteOutset: CGFloat = 72
    static let contentHeight: CGFloat = 328
    static let inputRowHeight: CGFloat = 22
    static let inputRowVerticalPadding: CGFloat = 5
    static let suggestionsMaxHeight: CGFloat = 260
    static let suggestionsVisibleRowLimit = 5
    static let suggestionRowMinHeight: CGFloat = 32
    static let suggestionRowHorizontalPadding: CGFloat = 8
    static let suggestionRowVerticalPadding: CGFloat = 10
    static let suggestionRowSpacing: CGFloat = 0
    static let resultsPanelTopSpacing: CGFloat = 6
    static let resultsPanelDividerHeight: CGFloat = 0.5
    static let resultsPanelDividerSpacing: CGFloat = 6

    static var suggestionRowHeight: CGFloat {
        suggestionRowMinHeight + suggestionRowVerticalPadding * 2
    }

    static func suggestionsHeight(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        guard count <= suggestionsVisibleRowLimit else { return suggestionsMaxHeight }
        let rowHeights = CGFloat(count) * suggestionRowHeight
        let spacings = CGFloat(max(count - 1, 0)) * suggestionRowSpacing
        return min(suggestionsMaxHeight, rowHeights + spacings)
    }

    static func resultsPanelHeight(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return resultsPanelTopSpacing
            + resultsPanelDividerHeight
            + resultsPanelDividerSpacing
            + suggestionsHeight(for: count)
    }

    static func layoutCount(forVisibleCount visibleCount: Int) -> Int {
        min(visibleCount, suggestionsVisibleRowLimit)
    }

    static func shouldWaitForSuggestionLayout(
        isDebouncing: Bool,
        isLoading: Bool,
        visibleLayoutCount: Int
    ) -> Bool {
        isDebouncing || (isLoading && visibleLayoutCount < suggestionsVisibleRowLimit)
    }

    static func effectiveWidth(availableWindowWidth: CGFloat) -> CGFloat {
        min(
            idealWidth,
            max(minimumWidth, availableWindowWidth - (horizontalPadding * 2))
        )
    }
}
