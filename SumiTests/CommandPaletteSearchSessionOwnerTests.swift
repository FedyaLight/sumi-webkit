import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class CommandPaletteSearchSessionOwnerTests: XCTestCase {
    func testTypingPublishesAndSelectsStableInputRowImmediately() {
        let owner = CommandPaletteSearchSessionOwner()
        let initialTopRequest = owner.resultListTopRequestID

        owner.text = "example.com"

        XCTAssertEqual(owner.visibleRows.first?.id, .url("http://example.com/"))
        XCTAssertEqual(owner.selectedRowID, owner.visibleRows.first?.id)
        XCTAssertGreaterThan(owner.resultListTopRequestID, initialTopRequest)
        XCTAssertEqual(
            owner.commitIntentForReturn(),
            .browserNavigation(.input("http://example.com/"))
        )
    }

    func testPreviousResultsRemainUntilReplacementBatchArrives() async {
        let manager = SearchManager(
            suggestionDataProvider: QuerySearchSuggestionDataProvider(
                payloads: [
                    "old": #"[{"phrase":"old result","is_nav":false}]"#,
                    "new": #"[{"phrase":"new result","is_nav":false}]"#,
                ]
            )
        )
        let owner = CommandPaletteSearchSessionOwner(searchManager: manager)

        owner.text = "old"
        manager.searchSuggestions(for: "old")
        await waitUntil {
            owner.visibleRows.contains { $0.title == "old result" }
        }

        owner.text = "new"

        XCTAssertTrue(owner.visibleRows.contains { $0.title == "old result" })
        XCTAssertEqual(owner.selectedRowID, owner.visibleRows.first?.id)

        manager.searchSuggestions(for: "new")
        await waitUntil {
            owner.visibleRows.contains { $0.title == "new result" }
                && !owner.visibleRows.contains { $0.title == "old result" }
        }
    }

    func testClearingActiveRequestDoesNotRecursivelyClearAgain() async throws {
        let manager = SearchManager(
            suggestionDataProvider: QuerySearchSuggestionDataProvider(
                payloads: [
                    "old": #"[{"phrase":"old result","is_nav":false}]"#,
                ]
            )
        )
        let owner = CommandPaletteSearchSessionOwner(searchManager: manager)
        let windowState = BrowserWindowState()

        owner.text = "old"
        owner.handleTextChanged(
            "old",
            isCommandPaletteVisible: true,
            presentationReason: .keyboard,
            windowState: windowState
        )
        await waitUntil {
            owner.visibleRows.contains { $0.title == "old result" }
        }

        let forwardStateChange = try XCTUnwrap(manager.onStateChange)
        var didClearActiveRequest = false
        manager.onStateChange = {
            forwardStateChange()
            guard manager.isLoadingSuggestions,
                  !didClearActiveRequest else { return }
            didClearActiveRequest = true
            manager.clearSuggestions()
        }

        owner.text = "new"
        owner.handleTextChanged(
            "new",
            isCommandPaletteVisible: true,
            presentationReason: .keyboard,
            windowState: windowState
        )
        await waitUntil {
            didClearActiveRequest
                && !manager.isLoadingSuggestions
                && !owner.isWaitingForSearchDebounce
        }

        XCTAssertFalse(manager.isLoadingSuggestions)
        XCTAssertNil(manager.suggestionSourceQuery)
    }

    func testNavigationKeepsQueryAndClampsAtBothEnds() {
        let owner = CommandPaletteSearchSessionOwner()
        owner.updateAvailableBrowserActions([
            .viewHistory,
            .openSettings,
        ])
        owner.enterActionsMode()

        owner.navigateSuggestions(direction: 1)
        owner.navigateSuggestions(direction: 1)
        owner.navigateSuggestions(direction: 1)

        XCTAssertEqual(owner.selectedSuggestionIndex, 1)
        XCTAssertEqual(owner.text, "")

        owner.navigateSuggestions(direction: -1)
        owner.navigateSuggestions(direction: -1)
        owner.navigateSuggestions(direction: -1)

        XCTAssertEqual(owner.selectedSuggestionIndex, -1)
        XCTAssertEqual(owner.text, "")
    }

    func testActionsModeUsesReferenceOrderAndSemanticCommitIntent() {
        let owner = CommandPaletteSearchSessionOwner()
        owner.updateAvailableBrowserActions([
            .viewHistory,
            .customizeSpaceGradient,
            .newTab,
        ])

        owner.enterActionsMode()

        XCTAssertEqual(
            owner.visibleRows.compactMap(\.browserAction),
            [.customizeSpaceGradient, .viewHistory]
        )
        let first = try? XCTUnwrap(owner.visibleRows.first)
        XCTAssertEqual(
            first.flatMap { owner.commitIntent(for: $0.id) },
            .browserAction(.customizeSpaceGradient)
        )
    }

    func testActionsModeUsesContextualTitleAndShortcutAccessory() {
        let owner = CommandPaletteSearchSessionOwner()
        owner.updateAvailableBrowserActions([
            CommandPaletteBrowserActionPresentation(
                action: .closeTab,
                title: "Unload",
                shortcutLabel: "⌘W"
            ),
        ])
        owner.enterActionsMode()
        owner.text = "Close Tab"

        XCTAssertEqual(owner.visibleRows.map(\.title), ["Unload"])
        XCTAssertEqual(owner.visibleRows.first?.accessory, .chip("⌘W"))
    }

    func testActionsModeContainsEveryAvailablePaletteAction() {
        let owner = CommandPaletteSearchSessionOwner()
        owner.updateAvailableBrowserActions(Set(ShortcutAction.allCases))

        owner.enterActionsMode()

        XCTAssertEqual(
            Set(owner.visibleRows.compactMap(\.browserAction)),
            Set(ShortcutAction.allCases.filter(\.isPresentedInCommandPalette))
        )
        XCTAssertEqual(
            owner.visibleRows.compactMap(\.browserAction),
            ShortcutAction.commandPaletteCatalogOrder
        )
    }

    func testActionsModeIncludesSpacesAndExtensionsByStableIdentity() {
        let owner = CommandPaletteSearchSessionOwner()
        let spaceID = UUID()
        owner.updateAvailableSpaces([
            .init(id: spaceID, title: "Work"),
        ])
        owner.updateAvailableExtensionActions([
            .init(id: "notes", title: "Notes"),
        ])

        owner.enterActionsMode()

        XCTAssertTrue(owner.visibleRows.contains {
            $0.id == .space(spaceID) && $0.activation == .space(spaceID)
        })
        XCTAssertTrue(owner.visibleRows.contains {
            $0.id == .extensionAction("notes")
                && $0.activation == .extensionAction("notes")
        })
    }

    func testSiteSearchStartsEmptyAndCommitsThroughSelectedEngine() {
        let owner = CommandPaletteSearchSessionOwner()
        let site = SumiSearchEngine(
            name: "Example",
            domain: "example.com",
            searchURLTemplate: "https://example.com/search?q={query}",
            colorHex: "#0000ff",
            tabSearchEnabled: true
        )
        owner.text = "stale"

        owner.enterSiteSearch(site)

        XCTAssertEqual(owner.mode, .siteSearch(site))
        XCTAssertEqual(owner.text, "")
        XCTAssertTrue(owner.visibleRows.isEmpty)

        owner.text = "swift"

        XCTAssertEqual(
            owner.commitIntentForReturn(),
            .siteSearch(site, query: "swift")
        )
    }

    func testLeavingScopedModeClearsRowsAndRequestsTop() {
        let owner = CommandPaletteSearchSessionOwner()
        owner.enterActionsMode()
        let previousTopRequest = owner.resultListTopRequestID

        XCTAssertTrue(owner.leaveScopedMode())

        XCTAssertEqual(owner.mode, .everything)
        XCTAssertEqual(owner.text, "")
        XCTAssertTrue(owner.visibleRows.isEmpty)
        XCTAssertGreaterThan(owner.resultListTopRequestID, previousTopRequest)
    }

    func testResetForHiddenBarClearsEntireSessionState() {
        let owner = CommandPaletteSearchSessionOwner()
        owner.updateAvailableBrowserActions([.viewHistory])
        owner.updateAvailableSpaces([.init(id: UUID(), title: "Work")])
        owner.enterActionsMode()
        owner.hoveredRowID = owner.visibleRows.first?.id

        owner.resetForHiddenBar()

        XCTAssertEqual(owner.mode, .everything)
        XCTAssertEqual(owner.text, "")
        XCTAssertNil(owner.selectedRowID)
        XCTAssertNil(owner.hoveredRowID)
        XCTAssertTrue(owner.visibleRows.isEmpty)
        XCTAssertTrue(owner.availableSpaces.isEmpty)
        XCTAssertNil(owner.availableBrowserActions)
        XCTAssertEqual(owner.suggestionLayoutCount, 0)
    }

    func testEquivalentInputRowsKeepIdentityAcrossRebuilds() {
        let owner = CommandPaletteSearchSessionOwner()
        owner.text = "Sumi Browser"
        let firstID = owner.visibleRows.first?.id

        owner.updateAvailableSpaces([])

        XCTAssertEqual(owner.visibleRows.first?.id, firstID)
    }

    func testEmptyReturnDoesNothing() {
        let owner = CommandPaletteSearchSessionOwner()

        XCTAssertNil(owner.commitIntentForReturn())
    }

    private func waitUntil(
        attempts: Int = 100,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for Command Palette state")
    }
}

@MainActor
private struct QuerySearchSuggestionDataProvider:
    SearchSuggestionDataProviding {
    let payloads: [String: String]

    func data(for query: String) async -> Data {
        Data((payloads[query] ?? "[]").utf8)
    }
}

private extension CommandPaletteRow {
    var browserAction: ShortcutAction? {
        guard case .browserAction(let action) = activation else {
            return nil
        }
        return action
    }
}
