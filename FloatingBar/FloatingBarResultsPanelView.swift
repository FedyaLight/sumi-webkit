//
//  FloatingBarResultsPanelView.swift
//  Sumi
//
//  Created by Codex on 23/05/2026.
//

import SwiftUI

struct FloatingBarResultsPanelView: View {
    let tokens: ChromeThemeTokens
    let suggestions: [SearchManager.SearchSuggestion]
    let layoutSuggestionCount: Int
    @Binding var selectedIndex: Int
    @Binding var hoveredIndex: Int?
    let onSelect: (SearchManager.SearchSuggestion) -> Void
    let onDeleteHistoryEntry: (HistoryListItem) -> Void

    private var isExpanded: Bool {
        layoutSuggestionCount > 0
    }

    private var listHeight: CGFloat {
        FloatingBarLayoutPolicy.suggestionsHeight(for: layoutSuggestionCount)
    }

    private var panelHeight: CGFloat {
        FloatingBarLayoutPolicy.resultsPanelHeight(for: layoutSuggestionCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: isExpanded ? FloatingBarLayoutPolicy.resultsPanelTopSpacing : 0)

            RoundedRectangle(cornerRadius: 100)
                .fill(tokens.separator.opacity(0.9))
                .frame(height: isExpanded ? FloatingBarLayoutPolicy.resultsPanelDividerHeight : 0)
                .frame(maxWidth: .infinity)
                .opacity(isExpanded ? 1 : 0)

            Color.clear
                .frame(height: isExpanded ? FloatingBarLayoutPolicy.resultsPanelDividerSpacing : 0)

            FloatingBarSuggestionsListView(
                tokens: tokens,
                suggestions: suggestions,
                visibleHeight: listHeight,
                selectedIndex: $selectedIndex,
                hoveredIndex: $hoveredIndex,
                onSelect: onSelect,
                onDeleteHistoryEntry: onDeleteHistoryEntry
            )
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .opacity(isExpanded ? 1 : 0)
        }
        .frame(height: panelHeight, alignment: .top)
        .clipped()
    }
}

private struct FloatingBarSuggestionsListView: View {
    let tokens: ChromeThemeTokens
    let suggestions: [SearchManager.SearchSuggestion]
    let visibleHeight: CGFloat
    @Binding var selectedIndex: Int
    @Binding var hoveredIndex: Int?
    let onSelect: (SearchManager.SearchSuggestion) -> Void
    let onDeleteHistoryEntry: (HistoryListItem) -> Void

    var body: some View {
        let selectedBackground = tokens.accent.opacity(0.58)
        let selectedForeground = ThemeContrastResolver.preferredForeground(on: tokens.accent)
        let selectedChipBackground = selectedForeground.opacity(0.88)
        let selectedChipForeground = ThemeContrastResolver.preferredForeground(on: selectedForeground)
        let shouldScroll = suggestions.count > FloatingBarLayoutPolicy.suggestionsVisibleRowLimit

        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: FloatingBarLayoutPolicy.suggestionRowSpacing) {
                    ForEach(suggestions.indices, id: \.self) { index in
                        let suggestion = suggestions[index]
                        let isSelected = selectedIndex == index
                        let isHovered = hoveredIndex == index
                        row(
                            for: suggestion,
                            isSelected: isSelected,
                            isHovered: isHovered,
                            selectedForeground: selectedForeground,
                            selectedChipBackground: selectedChipBackground,
                            selectedChipForeground: selectedChipForeground
                        )
                        .frame(minHeight: FloatingBarLayoutPolicy.suggestionRowMinHeight)
                        .padding(.horizontal, FloatingBarLayoutPolicy.suggestionRowHorizontalPadding)
                        .padding(.vertical, FloatingBarLayoutPolicy.suggestionRowVerticalPadding)
                        .background(
                            isSelected
                                ? selectedBackground
                                : isHovered
                                ? tokens.floatingBarRowHover
                                : .clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            selectedIndex == index
                                ? tokens.primaryText
                                : tokens.secondaryText
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .id(index)
                        .onHover { hovering in
                            hoveredIndex = hovering ? index : nil
                        }
                        .onTapGesture { onSelect(suggestion) }
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .scrollIndicators(shouldScroll ? .visible : .hidden)
            .frame(height: visibleHeight)
            .onChange(of: selectedIndex) { _, newIndex in
                guard newIndex >= 0 else { return }
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func row(
        for suggestion: SearchManager.SearchSuggestion,
        isSelected: Bool,
        isHovered: Bool,
        selectedForeground: Color,
        selectedChipBackground: Color,
        selectedChipForeground: Color
    ) -> some View {
        switch suggestion.type {
        case .tab(let tab):
            TabSuggestionItem(
                tab: tab,
                isSelected: isSelected,
                selectedForeground: selectedForeground,
                selectedChipBackground: selectedChipBackground,
                selectedChipForeground: selectedChipForeground
            )
        case .history(let entry):
            HistorySuggestionItem(
                entry: entry,
                isSelected: isSelected,
                isHovered: isHovered,
                selectedForeground: selectedForeground,
                onDelete: {
                    onDeleteHistoryEntry(entry)
                }
            )
        case .bookmark(let bookmark):
            GenericSuggestionItem(
                icon: Image(systemName: "bookmark.fill"),
                text: bookmark.title,
                actionLabel: "Open Bookmark",
                isSelected: isSelected,
                selectedForeground: selectedForeground,
                selectedChipBackground: selectedChipBackground,
                selectedChipForeground: selectedChipForeground
            )
        case .url:
            GenericSuggestionItem(
                icon: Image(systemName: "link"),
                text: suggestion.text,
                actionLabel: "Open URL",
                isSelected: isSelected,
                selectedForeground: selectedForeground,
                selectedChipBackground: selectedChipBackground,
                selectedChipForeground: selectedChipForeground
            )
        case .search:
            GenericSuggestionItem(
                icon: Image(systemName: "magnifyingglass"),
                text: suggestion.text,
                isSelected: isSelected,
                selectedForeground: selectedForeground,
                selectedChipBackground: selectedChipBackground,
                selectedChipForeground: selectedChipForeground
            )
        }
    }
}
