//
//  CommandPaletteLayoutPolicy.swift
//  Sumi
//
//

import CoreGraphics

enum CommandPaletteLayoutPolicy {
    static let idealWidth: CGFloat = 765
    static let horizontalPadding: CGFloat = ChromeLayoutTokens.commandPaletteHorizontalPadding
    static let minimumWidth: CGFloat = 200
    static let horizontalVignetteOutset: CGFloat = 56
    static let verticalVignetteOutset: CGFloat = 72
    static let contentHeight: CGFloat = 344
    static let inputRowHeight: CGFloat = 26
    static let inputRowVerticalPadding: CGFloat = 7
    static let suggestionsMaxHeight: CGFloat = 260
    static let suggestionsVisibleRowLimit = 5
    static let suggestionRowMinHeight: CGFloat = 32
    static let suggestionRowHorizontalPadding: CGFloat = 8
    static let suggestionRowVerticalPadding: CGFloat = 10
    static let suggestionRowSpacing: CGFloat = 0
    static let suggestionRowIconSpacing: CGFloat = 9
    static let inputRowHorizontalPadding: CGFloat = 8
    static let resultsPanelTopSpacing: CGFloat = 6
    static let resultsPanelDividerHeight: CGFloat = 0.5
    static let resultsPanelDividerSpacing: CGFloat = 6

    /// Leading edge of the suggestion title column, measured from the card
    /// content edge.
    static var textColumnInset: CGFloat {
        suggestionRowHorizontalPadding
            + CommandPaletteSuggestionMetrics.iconContainerSize
            + suggestionRowIconSpacing
    }

    /// The input row's leading icon shares the suggestion favicon container, so
    /// both glyph columns are centred on the same vertical axis.
    static var inputRowLeadingIconWidth: CGFloat {
        CommandPaletteSuggestionMetrics.iconContainerSize
    }

    /// Gap after the input row's leading icon that lands the field — and its
    /// placeholder — on the same column as the suggestion titles below.
    static var inputRowIconSpacing: CGFloat {
        textColumnInset - inputRowHorizontalPadding - inputRowLeadingIconWidth
    }

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
