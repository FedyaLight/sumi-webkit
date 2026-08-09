import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class CommandPaletteNavigationTargetCatalogTests: XCTestCase {
    func testSnapshotIncludesUnloadedFavoriteAndPinnedLaunchers() {
        let profileID = UUID()
        let space = Space(name: "Personal", profileId: profileID)
        let favorite = makePin(
            title: "Drive",
            url: "https://drive.example",
            role: .favorite,
            profileID: profileID
        )
        let pinned = makePin(
            title: "GitHub",
            url: "https://github.example",
            role: .spacePinned,
            profileID: profileID,
            spaceID: space.id
        )
        let window = BrowserWindowState()
        window.currentProfileId = profileID
        window.currentSpaceId = space.id
        let catalog = makeCatalog(
            spaces: [space],
            favoritePins: [favorite],
            spacePinnedPins: [space.id: [pinned]]
        )

        let snapshot = catalog.snapshot(for: window)

        XCTAssertEqual(
            snapshot.targets.map(\.identity),
            [.shortcut(favorite.id), .shortcut(pinned.id)]
        )
        XCTAssertTrue(snapshot.eligibleRegularTabs.isEmpty)
    }

    func testLiveLauncherKeepsDurableShortcutIdentity() {
        let profileID = UUID()
        let space = Space(name: "Personal", profileId: profileID)
        let pin = makePin(
            title: "Example",
            url: "https://example.com",
            role: .spacePinned,
            profileID: profileID,
            spaceID: space.id
        )
        let liveTab = Tab(url: pin.launchURL)
        liveTab.name = "Example Live"
        liveTab.bindToShortcutPin(pin)
        let window = BrowserWindowState()
        window.currentProfileId = profileID
        window.currentSpaceId = space.id
        let catalog = makeCatalog(
            spaces: [space],
            spacePinnedPins: [space.id: [pin]],
            liveShortcutTabs: [window.id: [pin.id: liveTab]]
        )

        let target = catalog.snapshot(for: window).targets.first

        XCTAssertEqual(target?.identity, .shortcut(pin.id))
        XCTAssertEqual(target?.title, "Example Live")
        XCTAssertEqual(target?.action, .switchToTab)
    }

    func testSplitGroupReplacesItsLauncherMembersWithOneTarget() throws {
        let profileID = UUID()
        let space = Space(name: "Personal", profileId: profileID)
        let first = makePin(
            title: "First",
            url: "https://first.example",
            role: .spacePinned,
            profileID: profileID,
            spaceID: space.id
        )
        let second = makePin(
            title: "Second",
            url: "https://second.example",
            role: .spacePinned,
            profileID: profileID,
            spaceID: space.id
        )
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .shortcutPin(first.id),
                    .shortcutPin(second.id),
                ],
                layoutKind: .vertical,
                container: .shortcutSidebar(
                    spaceId: space.id,
                    profileId: profileID,
                    folderId: nil,
                    index: 0
                ),
                title: "Research"
            )
        )
        let window = BrowserWindowState()
        window.currentProfileId = profileID
        window.currentSpaceId = space.id
        let catalog = makeCatalog(
            spaces: [space],
            spacePinnedPins: [space.id: [first, second]],
            splitGroups: [group]
        )

        let snapshot = catalog.snapshot(for: window)

        XCTAssertEqual(snapshot.targets.map(\.identity), [.splitGroup(group.id)])
        XCTAssertEqual(snapshot.targets.first?.action, .switchToSplitView)
        XCTAssertEqual(
            snapshot.targets.first?.title,
            "First   Second"
        )
        XCTAssertEqual(
            snapshot.targets.first?.splitMembers.map(\.id),
            [.shortcutPin(first.id), .shortcutPin(second.id)]
        )
        let identities:
            [CommandPaletteNavigationTargetPresentation.Identity] =
            snapshot.suggestions().compactMap { suggestion in
                guard case .navigationTarget(let target) = suggestion.type
                else { return nil }
                return target.identity
            }
        XCTAssertEqual(
            identities,
            [.splitGroup(group.id)]
        )
    }

    func testRegularSplitGroupSuppressesMemberTabs() throws {
        let profileID = UUID()
        let space = Space(name: "Personal", profileId: profileID)
        let first = makeTab(
            title: "First",
            url: "https://first.example",
            spaceID: space.id
        )
        let second = makeTab(
            title: "Second",
            url: "https://second.example",
            spaceID: space.id
        )
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(first.id),
                    .regularTab(second.id),
                ],
                layoutKind: .horizontal,
                container: .regularTabs(spaceId: space.id),
                title: "Comparison"
            )
        )
        let window = BrowserWindowState()
        window.currentProfileId = profileID
        window.currentSpaceId = space.id
        let catalog = makeCatalog(
            spaces: [space],
            regularTabs: [first, second],
            splitGroups: [group]
        )

        let snapshot = catalog.snapshot(for: window)

        XCTAssertEqual(snapshot.targets.map(\.identity), [.splitGroup(group.id)])
        XCTAssertEqual(snapshot.targets.first?.title, "First   Second")
        XCTAssertEqual(
            snapshot.targets.first?.splitMembers.map(\.id),
            [.regularTab(first.id), .regularTab(second.id)]
        )
        XCTAssertTrue(snapshot.eligibleRegularTabs.isEmpty)
        XCTAssertEqual(
            snapshot.suggestions().map(\.id),
            [.navigationTarget(.splitGroup(group.id))]
        )
    }

    func testMatchingUsesLauncherTitleAndURL() {
        let profileID = UUID()
        let space = Space(name: "Personal", profileId: profileID)
        let pin = makePin(
            title: "Project Board",
            url: "https://linear.app/acme",
            role: .spacePinned,
            profileID: profileID,
            spaceID: space.id
        )
        let window = BrowserWindowState()
        window.currentProfileId = profileID
        window.currentSpaceId = space.id
        let catalog = makeCatalog(
            spaces: [space],
            spacePinnedPins: [space.id: [pin]]
        )

        XCTAssertEqual(
            catalog.suggestions(matching: "project", for: window)
                .map(\.text),
            ["Project Board"]
        )
        XCTAssertEqual(
            catalog.suggestions(matching: "linear.app", for: window)
                .map(\.text),
            ["Project Board"]
        )
    }

    func testContextualEmptyStateGuaranteesNavigationBeforeHistory() async {
        let target = CommandPaletteNavigationTargetPresentation(
            identity: .shortcut(UUID()),
            title: "Pinned",
            searchText: "Pinned pinned.example",
            primaryURL: URL(string: "https://pinned.example")!,
            faviconProfileID: nil,
            action: .switchToTab,
            recencyRank: 0
        )
        let entries = (0..<5).map {
            makeHistoryEntry(
                url: "https://site\($0).example",
                title: "Site \($0)"
            )
        }
        let owner = ContextualEmptyStateSuggestionOwner(
            topVisitedSites: { _ in entries },
            bookmarks: { [] },
            navigationSuggestions: {
                [
                    SearchManager.SearchSuggestion(
                        text: target.title,
                        type: .navigationTarget(target)
                    ),
                ]
            }
        )

        let suggestions = await owner.suggestions(limit: 5)

        XCTAssertEqual(suggestions.first?.text, "Pinned")
        XCTAssertEqual(suggestions.count, 5)
    }

    private func makeHistoryEntry(url: String, title: String) -> HistoryListItem {
        HistoryListItem(
            id: url,
            visitID: nil,
            url: URL(string: url)!,
            title: title,
            domain: "example.com",
            siteDomain: "example.com",
            visitedAt: Date(),
            timeText: "",
            visitCount: 1,
            isSiteAggregate: true
        )
    }

    private func makeCatalog(
        spaces: [Space],
        regularTabs: [Tab] = [],
        favoritePins: [ShortcutPin] = [],
        spacePinnedPins: [UUID: [ShortcutPin]] = [:],
        splitGroups: [SplitGroup] = [],
        liveShortcutTabs: [UUID: [UUID: Tab]] = [:]
    ) -> CommandPaletteNavigationTargetCatalog {
        CommandPaletteNavigationTargetCatalog(
            spaces: { spaces },
            regularTabs: { regularTabs },
            favoritePins: { _ in favoritePins },
            spacePinnedPins: { spacePinnedPins[$0] ?? [] },
            splitGroups: { splitGroups },
            liveShortcutTab: { pinID, windowID in
                liveShortcutTabs[windowID]?[pinID]
            },
            activeTabs: { _ in regularTabs }
        )
    }

    private func makePin(
        title: String,
        url: String,
        role: ShortcutPinRole,
        profileID: UUID,
        spaceID: UUID? = nil
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: role == .favorite ? profileID : nil,
            executionProfileId: profileID,
            spaceId: spaceID,
            index: 0,
            launchURL: URL(string: url)!,
            title: title
        )
    }

    private func makeTab(
        title: String,
        url: String,
        spaceID: UUID
    ) -> Tab {
        let tab = Tab(url: URL(string: url)!)
        tab.name = title
        tab.spaceId = spaceID
        return tab
    }
}
