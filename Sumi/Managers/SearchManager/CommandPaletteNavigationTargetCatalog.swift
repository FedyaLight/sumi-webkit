//
//  CommandPaletteNavigationTargetCatalog.swift
//  Sumi
//
//

import Foundation
import SumiDomain

struct CommandPaletteNavigationTargetPresentation: Equatable {
    enum Identity: Hashable {
        case shortcut(UUID)
        case splitGroup(UUID)
    }

    enum Action: Equatable {
        case switchToTab
        case switchToSplitView
    }

    let identity: Identity
    let title: String
    let searchText: String
    let primaryURL: URL?
    let faviconProfileID: UUID?
    let action: Action
    let recencyRank: Int?
    var splitMembers: [CommandPaletteSplitMemberPresentation] = []
}

/// Projects shared durable navigation structure into command-palette targets.
/// Runtime shortcut tabs enrich presentation but never become result identity.
@MainActor
final class CommandPaletteNavigationTargetCatalog {
    @MainActor
    struct Snapshot {
        let targets: [CommandPaletteNavigationTargetPresentation]
        let eligibleRegularTabs: [Tab]

        func suggestions(
            matching query: String? = nil
        ) -> [SearchManager.SearchSuggestion] {
            let normalizedQuery = query.map(Self.normalize) ?? ""
            let durable = targets
                .filter {
                    normalizedQuery.isEmpty
                        || Self.normalize($0.searchText)
                            .localizedStandardContains(normalizedQuery)
                }
                .sorted { lhs, rhs in
                    let lhsPrefix =
                        Self.normalize(lhs.title).hasPrefix(normalizedQuery)
                    let rhsPrefix =
                        Self.normalize(rhs.title).hasPrefix(normalizedQuery)
                    if lhsPrefix != rhsPrefix { return lhsPrefix }
                    return Self.targetOrder(lhs, rhs)
                }
                .map {
                    SearchManager.SearchSuggestion(
                        text: $0.title,
                        type: .navigationTarget($0)
                    )
                }
            let tabs = eligibleRegularTabs
                .filter {
                    normalizedQuery.isEmpty
                        || Self.normalize(
                            "\($0.name) \($0.url.absoluteString)"
                        ).localizedStandardContains(normalizedQuery)
                }
                .map {
                    SearchManager.SearchSuggestion(
                        text: $0.name,
                        type: .tab($0)
                    )
                }
            return durable + tabs
        }

        private static func targetOrder(
            _ lhs: CommandPaletteNavigationTargetPresentation,
            _ rhs: CommandPaletteNavigationTargetPresentation
        ) -> Bool {
            if lhs.recencyRank != rhs.recencyRank {
                return (lhs.recencyRank ?? Int.max)
                    < (rhs.recencyRank ?? Int.max)
            }
            return lhs.title.localizedStandardCompare(rhs.title)
                == .orderedAscending
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

    private let spaces: @MainActor () -> [Space]
    private let regularTabs: @MainActor () -> [Tab]
    private let essentialPins: @MainActor (UUID?) -> [ShortcutPin]
    private let spacePinnedPins: @MainActor (UUID) -> [ShortcutPin]
    private let splitGroups: @MainActor () -> [SplitGroup]
    private let liveShortcutTab: @MainActor (UUID, UUID) -> Tab?
    private let activeTabs: @MainActor (BrowserWindowState) -> [Tab]

    init(
        spaces: @escaping @MainActor () -> [Space],
        regularTabs: @escaping @MainActor () -> [Tab],
        essentialPins: @escaping @MainActor (UUID?) -> [ShortcutPin],
        spacePinnedPins: @escaping @MainActor (UUID) -> [ShortcutPin],
        splitGroups: @escaping @MainActor () -> [SplitGroup],
        liveShortcutTab: @escaping @MainActor (UUID, UUID) -> Tab?,
        activeTabs: @escaping @MainActor (BrowserWindowState) -> [Tab] = {
            _ in []
        }
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.essentialPins = essentialPins
        self.spacePinnedPins = spacePinnedPins
        self.splitGroups = splitGroups
        self.liveShortcutTab = liveShortcutTab
        self.activeTabs = activeTabs
    }

    func snapshot(for windowState: BrowserWindowState) -> Snapshot {
        guard !windowState.isIncognito else {
            return Snapshot(
                targets: [],
                eligibleRegularTabs: []
            )
        }

        let allSpaces = spaces()
        let profileID = windowState.currentProfileId
            ?? allSpaces.first {
                $0.id == windowState.currentSpaceId
            }?.profileId
        let profileSpaces = allSpaces.filter { space in
            guard let profileID else { return false }
            return space.profileId == profileID
        }
        let spaceIDs = Set(profileSpaces.map(\.id))
        let tabsByID = Dictionary(
            uniqueKeysWithValues: regularTabs()
                .filter { tab in
                    guard let spaceID = tab.spaceId else { return false }
                    return spaceIDs.contains(spaceID)
                }
                .map { ($0.id, $0) }
        )
        let pins = essentialPins(profileID)
            + profileSpaces.flatMap { spacePinnedPins($0.id) }
        let pinsByID = Dictionary(
            uniqueKeysWithValues: pins.map { ($0.id, $0) }
        )
        let recency = recencyRanks(for: windowState)
        var groupedRegularTabIDs = Set<UUID>()
        var groupedShortcutPinIDs = Set<UUID>()
        var groupTargets: [CommandPaletteNavigationTargetPresentation] = []

        for group in splitGroups()
            where isGroup(group, inProfile: profileID, spaceIDs: spaceIDs) {
            let resolved = group.memberIDs.compactMap { memberID -> Member? in
                switch memberID {
                case .regularTab(let tabID):
                    return tabsByID[tabID].map(Member.regular)
                case .shortcutPin(let pinID):
                    return pinsByID[pinID].map {
                        Member.shortcut(
                            $0,
                            liveShortcutTab(pinID, windowState.id)
                        )
                    }
                }
            }
            guard resolved.count == group.memberIDs.count else { continue }

            let title = resolved.map(\.title).joined(separator: "   ")
            let groupTitle = SplitGroupSidebarModel.displayTitle(for: group)
            let memberSearchText = resolved.map(\.searchText).joined(separator: " ")
            groupTargets.append(
                CommandPaletteNavigationTargetPresentation(
                    identity: .splitGroup(group.id),
                    title: title,
                    searchText: "\(groupTitle) \(memberSearchText)",
                    primaryURL: resolved.first?.url,
                    faviconProfileID: profileID,
                    action: .switchToSplitView,
                    recencyRank: resolved.compactMap {
                        recency[$0.selectionIdentity]
                    }.min(),
                    splitMembers: resolved.map(\.palettePresentation)
                )
            )
            for memberID in group.memberIDs {
                switch memberID {
                case .regularTab(let tabID):
                    groupedRegularTabIDs.insert(tabID)
                case .shortcutPin(let pinID):
                    groupedShortcutPinIDs.insert(pinID)
                }
            }
        }

        let shortcutTargets = pins.compactMap { pin
            -> CommandPaletteNavigationTargetPresentation? in
            guard !groupedShortcutPinIDs.contains(pin.id) else { return nil }
            let liveTab = liveShortcutTab(pin.id, windowState.id)
            let title = pin.resolvedDisplayTitle(liveTab: liveTab)
            let url = liveTab?.url ?? pin.launchURL
            return CommandPaletteNavigationTargetPresentation(
                identity: .shortcut(pin.id),
                title: title,
                searchText: "\(title) \(url.absoluteString)",
                primaryURL: url,
                faviconProfileID: pin.executionProfileId,
                action: .switchToTab,
                recencyRank: recency[.shortcutPin(pin.id)]
            )
        }

        let eligibleRegularTabs = activeTabs(windowState).filter {
            !$0.isShortcutLiveInstance
                && !groupedRegularTabIDs.contains($0.id)
        }

        return Snapshot(
            targets: (groupTargets + shortcutTargets).sorted(by: targetOrder),
            eligibleRegularTabs: eligibleRegularTabs
        )
    }

    func suggestions(
        matching query: String,
        for windowState: BrowserWindowState
    ) -> [SearchManager.SearchSuggestion] {
        snapshot(for: windowState).suggestions(matching: query)
    }

    @MainActor
    private enum Member {
        case regular(Tab)
        case shortcut(ShortcutPin, Tab?)

        var title: String {
            switch self {
            case .regular(let tab):
                return tab.name
            case .shortcut(let pin, let liveTab):
                return pin.resolvedDisplayTitle(liveTab: liveTab)
            }
        }

        var searchText: String {
            switch self {
            case .regular(let tab):
                return "\(tab.name) \(tab.url.absoluteString)"
            case .shortcut(let pin, let liveTab):
                return "\(title) \((liveTab?.url ?? pin.launchURL).absoluteString)"
            }
        }

        var url: URL {
            switch self {
            case .regular(let tab): tab.url
            case .shortcut(let pin, let liveTab):
                liveTab?.url ?? pin.launchURL
            }
        }

        var selectionIdentity: SelectionIdentity {
            switch self {
            case .regular(let tab): .regularTab(tab.id)
            case .shortcut(let pin, _): .shortcutPin(pin.id)
            }
        }

        var palettePresentation: CommandPaletteSplitMemberPresentation {
            switch self {
            case .regular(let tab):
                return CommandPaletteSplitMemberPresentation(
                    id: .regularTab(tab.id),
                    icon: tab.faviconIsTemplateGlobePlaceholder
                        ? .favicon(tab.url)
                        : .tab(tab.faviconPresentation)
                )
            case .shortcut(let pin, let liveTab):
                let icon: CommandPaletteSplitMemberPresentation.Icon
                if let glyph = pin.glyphText {
                    icon = .glyph(glyph)
                } else if let systemName =
                            pin.chromeTemplateSystemImageName {
                    icon = .systemSymbol(systemName)
                } else if let liveTab,
                          !liveTab.faviconIsTemplateGlobePlaceholder {
                    icon = .tab(liveTab.faviconPresentation)
                } else {
                    icon = .favicon(liveTab?.url ?? pin.launchURL)
                }
                return CommandPaletteSplitMemberPresentation(
                    id: .shortcutPin(pin.id),
                    icon: icon
                )
            }
        }
    }

    private enum SelectionIdentity: Hashable {
        case regularTab(UUID)
        case shortcutPin(UUID)
    }

    private func isGroup(
        _ group: SplitGroup,
        inProfile profileID: UUID?,
        spaceIDs: Set<UUID>
    ) -> Bool {
        switch group.container {
        case .regularTabs(let spaceID):
            return spaceID.map(spaceIDs.contains) ?? true
        case .essentialSidebar(let groupProfileID, _):
            return groupProfileID == nil || groupProfileID == profileID
        case .shortcutSidebar(let spaceID, let groupProfileID, _, _):
            return spaceIDs.contains(spaceID)
                && (groupProfileID == nil || groupProfileID == profileID)
        }
    }

    private func recencyRanks(
        for windowState: BrowserWindowState
    ) -> [SelectionIdentity: Int] {
        var ordered: [SelectionIdentity] = []
        var seen = Set<SelectionIdentity>()
        let currentSpaceID = windowState.currentSpaceId
        let orderedSpaceIDs = ([currentSpaceID].compactMap { $0 }
            + windowState.selectionHistory.recentSelectionItemsBySpace.keys
                .filter { $0 != currentSpaceID }
                .sorted { $0.uuidString < $1.uuidString })
        for spaceID in orderedSpaceIDs {
            for item in windowState.selectionHistory
                .recentSelectionItemsBySpace[spaceID] ?? [] {
                let identity: SelectionIdentity
                switch item {
                case .regularTab(let tabID):
                    identity = .regularTab(tabID)
                case .shortcutPin(let pinID):
                    identity = .shortcutPin(pinID)
                }
                if seen.insert(identity).inserted {
                    ordered.append(identity)
                }
            }
        }
        return Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map {
                ($0.element, $0.offset)
            }
        )
    }

    private func targetOrder(
        _ lhs: CommandPaletteNavigationTargetPresentation,
        _ rhs: CommandPaletteNavigationTargetPresentation
    ) -> Bool {
        if lhs.recencyRank != rhs.recencyRank {
            return (lhs.recencyRank ?? Int.max)
                < (rhs.recencyRank ?? Int.max)
        }
        return lhs.title.localizedStandardCompare(rhs.title)
            == .orderedAscending
    }

    private func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }
}

/// Builds the one contextual no-query list shared by every command-palette
/// presentation. Navigation targets are admitted first so a full history
/// bucket cannot hide "Switch to Tab" or "Switch to Split View".
@MainActor
final class ContextualEmptyStateSuggestionOwner {
    private let topVisitedSites: @MainActor (_ limit: Int) async -> [HistoryListItem]
    private let bookmarks: @MainActor () -> [SumiBookmark]
    private let navigationSuggestions: @MainActor () -> [SearchManager.SearchSuggestion]

    init(
        topVisitedSites: @escaping @MainActor (_ limit: Int) async -> [HistoryListItem],
        bookmarks: @escaping @MainActor () -> [SumiBookmark],
        navigationSuggestions: @escaping @MainActor () -> [SearchManager.SearchSuggestion]
    ) {
        self.topVisitedSites = topVisitedSites
        self.bookmarks = bookmarks
        self.navigationSuggestions = navigationSuggestions
    }

    func suggestions(limit: Int) async -> [SearchManager.SearchSuggestion] {
        var suggestions: [SearchManager.SearchSuggestion] = []
        var seenKeys = Set<String>()

        func append(_ suggestion: SearchManager.SearchSuggestion) {
            guard suggestions.count < limit else { return }
            let key = SuggestionDeduplicationPolicy.deduplicationKey(
                for: suggestion
            )
            guard seenKeys.insert(key).inserted else { return }
            suggestions.append(suggestion)
        }

        let navigation = navigationSuggestions()
        navigation.prefix(min(2, limit)).forEach(append)

        let topSites = await topVisitedSites(max(limit, 1))
        for entry in topSites {
            append(
                SearchManager.SearchSuggestion(
                    text: entry.displayTitle,
                    type: .history(entry)
                )
            )
        }

        for bookmark in bookmarks() {
            append(
                SearchManager.SearchSuggestion(
                    text: bookmark.title,
                    type: .bookmark(bookmark)
                )
            )
        }

        navigation.dropFirst(min(2, limit)).forEach(append)

        return suggestions
    }
}
