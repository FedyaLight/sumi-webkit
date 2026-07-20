//
//  FloatingBarCommandSuggestionProvider.swift
//  Sumi
//
//

import Foundation

/// Browser command exposed as a floating-bar suggestion (Zen's URL-bar
/// "global actions" surface).
enum FloatingBarCommand: String {
    case newSplitView

    var title: String {
        switch self {
        case .newSplitView:
            return String(localized: "New Split View")
        }
    }

    var symbolName: String {
        switch self {
        case .newSplitView:
            return "rectangle.split.2x1"
        }
    }
}

/// Matches the floating-bar query against browser commands. Kept outside
/// `SearchManager` so command surfacing stays a synchronous session concern
/// and never enters the async web/history suggestion pipeline.
@MainActor
final class FloatingBarCommandSuggestionProvider {
    private static let newSplitViewPhrases = [
        "split",
        "new split",
        "split view",
        "new split view",
    ]

    // A single cached instance keeps the suggestion's identity stable across
    // `visibleSuggestions` recomputations (SearchSuggestion.id is fresh per init).
    private let newSplitViewSuggestion = SearchManager.SearchSuggestion(
        text: FloatingBarCommand.newSplitView.title,
        type: .command(.newSplitView)
    )

    func suggestions(for query: String) -> [SearchManager.SearchSuggestion] {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.count >= 2 else { return [] }

        let matches = Self.newSplitViewPhrases.contains { $0.hasPrefix(normalized) }
            || FloatingBarCommand.newSplitView.title.lowercased().hasPrefix(normalized)
        guard matches else { return [] }
        return [newSplitViewSuggestion]
    }
}
