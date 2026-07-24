import Foundation
import SumiDomain

struct CommandPaletteBrowserActionPresentation: Equatable {
    let action: ShortcutAction
    let title: String
    let shortcutLabel: String?

    init(
        action: ShortcutAction,
        title: String? = nil,
        shortcutLabel: String? = nil
    ) {
        self.action = action
        self.title = title ?? action.commandPaletteTitle
        self.shortcutLabel = shortcutLabel
    }
}

/// Presents the same browser actions used by keyboard shortcuts. Matching is
/// synchronous so local actions are visible before web suggestions arrive.
@MainActor
final class CommandPaletteCommandSuggestionProvider {
    private struct Match {
        let presentation: CommandPaletteBrowserActionPresentation
        let score: Int
    }

    func suggestions(
        for query: String,
        showsAllWhenEmpty: Bool,
        availableActions:
            [ShortcutAction: CommandPaletteBrowserActionPresentation]?
    ) -> [SearchManager.SearchSuggestion] {
        let normalizedQuery = Self.normalize(query)
        if !showsAllWhenEmpty,
           normalizedQuery.count <= 2
            || normalizedQuery.range(
                of: #"^[a-z][a-z0-9+.-]*:"#,
                options: .regularExpression
            ) != nil {
            return []
        }
        let actions = ShortcutAction.commandPaletteCatalogOrder.compactMap {
            action -> CommandPaletteBrowserActionPresentation? in
            guard action.isPresentedInCommandPalette else { return nil }
            if let availableActions {
                return availableActions[action]
            }
            return CommandPaletteBrowserActionPresentation(action: action)
        }

        if normalizedQuery.isEmpty {
            guard showsAllWhenEmpty else { return [] }
            return actions.map(Self.suggestion)
        }

        let matches = actions.compactMap { presentation -> Match? in
            let score = Self.score(
                presentation,
                query: normalizedQuery
            )
            let minimumScore = showsAllWhenEmpty ? 30 : 92
            guard score > minimumScore else {
                return nil
            }
            return Match(presentation: presentation, score: score)
        }
        .sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return Self.catalogOrder(
                $0.presentation.action,
                $1.presentation.action
            )
        }

        let limit = showsAllWhenEmpty ? matches.count : 5
        return matches.prefix(limit).map {
            Self.suggestion($0.presentation)
        }
    }

    private static func suggestion(
        _ presentation: CommandPaletteBrowserActionPresentation
    ) -> SearchManager.SearchSuggestion {
        SearchManager.SearchSuggestion(
            text: presentation.title,
            type: .command(presentation.action)
        )
    }

    private static func score(
        _ presentation: CommandPaletteBrowserActionPresentation,
        query: String
    ) -> Int {
        let action = presentation.action
        let searchable = [
            normalize(presentation.title),
            normalize(action.displayName),
        ]
            + action.commandPaletteKeywords.map(normalize)
            + [normalize(action.category.displayName)]

        return searchable.map {
            fuzzyScore(target: $0, query: query)
        }.max() ?? 0
    }

    /// Zen's VS Code-style scorer, kept deterministic by using catalog order
    /// as the tie-break instead of its opaque negative-feedback learner.
    private static func fuzzyScore(target: String, query: String) -> Int {
        guard !target.isEmpty,
              !query.isEmpty,
              query.count <= target.count else {
            return 0
        }
        if target == query {
            return 200
        }
        if target.hasPrefix(query) {
            return 100 + query.count
        }

        let targetCharacters = Array(target)
        let queryCharacters = Array(query)
        var score = 0
        var queryIndex = 0
        var lastMatchIndex = -1
        var consecutiveMatches = 0

        for targetIndex in targetCharacters.indices {
            guard queryIndex < queryCharacters.count,
                  targetCharacters[targetIndex]
                    == queryCharacters[queryIndex] else {
                continue
            }
            var bonus = 10
            if targetIndex == 0
                || [" ", "-", "_"].contains(
                    String(targetCharacters[targetIndex - 1])
                ) {
                bonus += 15
            }
            if lastMatchIndex == targetIndex - 1 {
                consecutiveMatches += 1
                bonus += 20 * consecutiveMatches
            } else {
                consecutiveMatches = 0
            }
            if lastMatchIndex != -1 {
                bonus -= min(targetIndex - lastMatchIndex - 1, 10)
            }
            score += bonus
            lastMatchIndex = targetIndex
            queryIndex += 1
        }
        return queryIndex == queryCharacters.count ? score : 0
    }

    private static func catalogOrder(
        _ lhs: ShortcutAction,
        _ rhs: ShortcutAction
    ) -> Bool {
        let actions = ShortcutAction.commandPaletteCatalogOrder
        return (actions.firstIndex(of: lhs) ?? actions.endIndex)
            < (actions.firstIndex(of: rhs) ?? actions.endIndex)
    }

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }
}
