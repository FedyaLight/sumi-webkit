//
//  CommandPaletteResultsPanelView.swift
//  Sumi
//
//

import SumiDomain
import SwiftUI

struct CommandPaletteResultsPanelView: View {
    let browserContext: CommandPaletteBrowserContext
    let tokens: ChromeThemeTokens
    let scrollHoverCoordinator: NativeSurfaceScrollHoverCoordinator
    let rows: [CommandPaletteRow]
    let layoutSuggestionCount: Int
    let resultListTopRequestID: UInt64
    @Binding var selectedID: CommandPaletteRow.ID?
    @Binding var hoveredID: CommandPaletteRow.ID?
    let onSelect: (CommandPaletteRow.ID) -> Void
    let onDeleteHistory: (HistoryQuery) -> Void

    private var isExpanded: Bool {
        layoutSuggestionCount > 0
    }

    private var listHeight: CGFloat {
        CommandPaletteLayoutPolicy.suggestionsHeight(for: layoutSuggestionCount)
    }

    private var panelHeight: CGFloat {
        CommandPaletteLayoutPolicy.resultsPanelHeight(for: layoutSuggestionCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: isExpanded ? CommandPaletteLayoutPolicy.resultsPanelTopSpacing : 0)

            RoundedRectangle(cornerRadius: 100)
                .fill(tokens.separator.opacity(0.9))
                .frame(height: isExpanded ? CommandPaletteLayoutPolicy.resultsPanelDividerHeight : 0)
                .frame(maxWidth: .infinity)
                .opacity(isExpanded ? 1 : 0)

            Color.clear
                .frame(height: isExpanded ? CommandPaletteLayoutPolicy.resultsPanelDividerSpacing : 0)

            CommandPaletteSuggestionsListView(
                scrollHoverCoordinator: scrollHoverCoordinator,
                browserContext: browserContext,
                tokens: tokens,
                rows: rows,
                visibleHeight: listHeight,
                resultListTopRequestID: resultListTopRequestID,
                selectedID: $selectedID,
                hoveredID: $hoveredID,
                onSelect: onSelect,
                onDeleteHistory: onDeleteHistory
            )
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .opacity(isExpanded ? 1 : 0)
        }
        .frame(height: panelHeight, alignment: .top)
        .clipped()
    }
}

private struct CommandPaletteSuggestionsListView: View {
    @State private var scrollPosition = ScrollPosition(
        idType: CommandPaletteRow.ID.self
    )
    @ObservedObject var scrollHoverCoordinator: NativeSurfaceScrollHoverCoordinator

    let browserContext: CommandPaletteBrowserContext
    let tokens: ChromeThemeTokens
    let rows: [CommandPaletteRow]
    let visibleHeight: CGFloat
    let resultListTopRequestID: UInt64
    @Binding var selectedID: CommandPaletteRow.ID?
    @Binding var hoveredID: CommandPaletteRow.ID?
    let onSelect: (CommandPaletteRow.ID) -> Void
    let onDeleteHistory: (HistoryQuery) -> Void

    var body: some View {
        let selectedBackground = tokens.accent.opacity(0.82)
        let selectedForeground = ThemeContrastResolver.preferredForeground(on: tokens.accent)
        let selectedChipBackground = selectedForeground.opacity(0.88)
        let selectedChipForeground = ThemeContrastResolver.preferredForeground(on: selectedForeground)

        ScrollView(.vertical) {
            LazyVStack(spacing: CommandPaletteLayoutPolicy.suggestionRowSpacing) {
                ForEach(rows) { row in
                    let isSelected = selectedID == row.id
                    let isHovered = hoveredID == row.id
                    CommandPaletteRowItem(
                        faviconContext: browserContext.favicon,
                        row: row,
                        isSelected: isSelected,
                        isHovered: isHovered,
                        selectedForeground: selectedForeground,
                        selectedChipBackground: selectedChipBackground,
                        selectedChipForeground: selectedChipForeground,
                        onDeleteHistory: onDeleteHistory
                    )
                    .frame(minHeight: CommandPaletteLayoutPolicy.suggestionRowMinHeight)
                    .padding(.horizontal, CommandPaletteLayoutPolicy.suggestionRowHorizontalPadding)
                    .padding(.vertical, CommandPaletteLayoutPolicy.suggestionRowVerticalPadding)
                    .background(
                        isSelected
                            ? selectedBackground
                            : isHovered
                            ? tokens.floatingSurfaceHover
                            : .clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .font(ChromeThemeTypography.commandPaletteSuggestionRow)
                    .foregroundStyle(
                        isSelected
                            ? selectedForeground
                            : tokens.secondaryText
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .id(row.id)
                    .accessibilityElement(
                        children: row.secondaryAction == nil
                            ? .ignore
                            : .contain
                    )
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityAddTraits(.isButton)
                    .nativeSurfaceHover(
                        Binding(
                            get: { hoveredID == row.id },
                            set: { hovering in
                                if hovering {
                                    hoveredID = row.id
                                } else if hoveredID == row.id {
                                    hoveredID = nil
                                }
                            }
                        )
                    )
                    .onTapGesture { onSelect(row.id) }
                }
            }
            .scrollTargetLayout()
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .scrollPosition($scrollPosition)
        .environment(
            \.nativeSurfaceHoverUpdatesEnabled,
            scrollHoverCoordinator.hoverUpdatesEnabled
        )
        .suppressesNativeSurfaceHoverWhileScrolling(
            scrollHoverCoordinator,
            region: "command-palette-results"
        )
        .accessibilityIdentifier("command-palette-results")
        .scrollIndicators(.hidden, axes: .vertical)
        .frame(height: visibleHeight)
        .onChange(of: resultListTopRequestID, initial: true) { _, _ in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .onChange(of: selectedID) { _, newID in
            guard let newID else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if rows.first?.id == newID {
                    scrollPosition.scrollTo(edge: .top)
                } else {
                    scrollPosition.scrollTo(id: newID, anchor: .center)
                }
            }
        }
    }

}
