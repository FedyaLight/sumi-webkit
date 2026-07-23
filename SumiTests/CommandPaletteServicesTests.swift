@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class CommandPaletteServicesTests: XCTestCase {
    func testRetainedServicesDoNotRetainBrowserKernel() {
        var browserManager: BrowserManager? = BrowserManager(
            windowRegistry: WindowRegistry()
        )
        weak var releasedBrowserManager = browserManager
        weak var releasedEmptySplitPlaceholders =
            browserManager?.splitEmptyPlaceholders
        var retainedServices = browserManager?.urlBarBundle.commandPalette

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNotNil(releasedEmptySplitPlaceholders)

        retainedServices = nil

        XCTAssertNil(releasedEmptySplitPlaceholders)
    }

    func testPresentationPreservesDraftAndPersistsEachStateActionOnce() {
        let persistence = CommandPalettePersistenceSpy()
        let split = CommandPaletteSplitPlaceholderSpy()
        var themeDismissCount = 0
        let windowState = BrowserWindowState()
        let splitCancellation = makeSplitCancellation(
            recorder: split,
            windowID: windowState.id
        )
        splitCancellation.register(Tab(), in: windowState.id)
        let presentation = makePresentation(
            splitCancellation: splitCancellation,
            persistence: persistence,
            dismissThemePicker: { themeDismissCount += 1 }
        )
        windowState.commandPaletteDraftText = "preserved"

        presentation.focus(
            in: windowState,
            prefill: "",
            navigateCurrentTab: false,
            reason: .keyboard
        )

        XCTAssertEqual(windowState.commandPaletteDraftText, "preserved")
        XCTAssertTrue(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(themeDismissCount, 1)
        XCTAssertEqual(persistence.persistedWindowIDs, [windowState.id])

        presentation.updateDraft(in: windowState, text: "changed")
        presentation.updateDraft(in: windowState, text: "changed")

        XCTAssertEqual(persistence.scheduled, [
            .init(windowID: windowState.id, delayNanoseconds: 450_000_000),
        ])

        presentation.dismiss(in: windowState, preserveDraft: true)

        XCTAssertEqual(windowState.commandPaletteDraftText, "changed")
        XCTAssertFalse(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(split.cancelledWindowIDs, [windowState.id])
        XCTAssertEqual(
            persistence.persistedWindowIDs,
            [windowState.id, windowState.id]
        )
    }

    func testDismissLookupUsesOnlyVisibleRegisteredWindow() {
        let registry = WindowRegistry()
        let activeWindow = BrowserWindowState()
        let otherWindow = BrowserWindowState()
        registry.register(activeWindow)
        registry.register(otherWindow)
        registry.setActive(activeWindow)
        activeWindow.presentationState.isCommandPaletteVisible = true
        activeWindow.commandPaletteDraftText = "active draft"
        otherWindow.presentationState.isCommandPaletteVisible = true
        let persistence = CommandPalettePersistenceSpy()
        let presentation = makePresentation(
            registry: registry,
            persistence: persistence
        )

        presentation.dismissActiveWindow(preserveDraft: true)

        XCTAssertFalse(activeWindow.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(activeWindow.commandPaletteDraftText, "active draft")
        XCTAssertFalse(
            presentation.dismissIfVisible(in: UUID(), preserveDraft: false)
        )
        XCTAssertTrue(
            presentation.dismissIfVisible(
                in: otherWindow.id,
                preserveDraft: false
            )
        )
        XCTAssertEqual(
            persistence.persistedWindowIDs,
            [activeWindow.id, otherWindow.id]
        )
    }

    func testCommitCapturesCurrentPageBeforeDismissResetsDraft() {
        let windowState = BrowserWindowState()
        let pageTab = Tab(
            url: URL(string: "https://example.com")
                ?? SumiSurface.emptyTabURL
        )
        windowState.commandPaletteDraftNavigatesCurrentTab = true
        windowState.presentationState.isCommandPaletteVisible = true
        let persistence = CommandPalettePersistenceSpy()
        let splitBrowser = BrowserManager()
        splitBrowser.emptySplitSession.register(
            pageTab,
            in: windowState.id
        )
        let opening = CommandPaletteTabOpeningSpy()
        var loadedPages: [CommandPaletteLoadedPage] = []
        let presentation = makePresentation(
            persistence: persistence
        )
        let commit = makeCommit(
            presentation: presentation,
            opening: opening,
            split: splitBrowser.splitEmptyPlaceholders,
            activePageTab: { _ in pageTab },
            loadPage: { url, tab, window in
                loadedPages.append(.init(
                    url: url,
                    tabID: tab.id,
                    windowID: window.id
                ))
            }
        )

        commit.commitNavigation(
            to: "https://target.example/",
            in: windowState
        )

        XCTAssertFalse(windowState.commandPaletteDraftNavigatesCurrentTab)
        XCTAssertEqual(persistence.persistedWindowIDs, [windowState.id])
        XCTAssertFalse(
            splitBrowser.emptySplitSession.accepts(
                pageTab,
                in: windowState.id
            )
        )
        XCTAssertEqual(loadedPages.first?.url.absoluteString, "https://target.example/")
        XCTAssertEqual(loadedPages.first?.tabID, pageTab.id)
        XCTAssertEqual(loadedPages.first?.windowID, windowState.id)
        XCTAssertTrue(opening.insertedURLs.isEmpty)
    }

    func testCommitTargetRequiresDraftIntentAndActivePage() {
        let windowState = BrowserWindowState()
        let pageTab = Tab(
            url: URL(string: "https://example.com")
                ?? SumiSurface.emptyTabURL
        )
        let presentation = makePresentation()
        let noPageCommit = makeCommit(
            presentation: presentation,
            activePageTab: { _ in nil }
        )
        let pageCommit = makeCommit(
            presentation: presentation,
            activePageTab: { _ in pageTab }
        )

        XCTAssertFalse(pageCommit.commitNavigatesCurrentTab(in: windowState))
        windowState.commandPaletteDraftNavigatesCurrentTab = true
        XCTAssertFalse(noPageCommit.commitNavigatesCurrentTab(in: windowState))
        XCTAssertTrue(pageCommit.commitNavigatesCurrentTab(in: windowState))
    }

    func testConfiguredNewTabPageBypassesCommandPalette() throws {
        let suiteName = "CommandPaletteServicesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SumiSettingsService(userDefaults: defaults)
        settings.newTabMode = .specificPage
        settings.newTabPageURLString = "start.example"
        let windowState = BrowserWindowState()
        let opening = CommandPaletteTabOpeningSpy()
        let presentation = makePresentation()
        let commit = makeCommit(
            presentation: presentation,
            opening: opening,
            settings: settings
        )

        commit.openNewTabSurface(in: windowState)

        XCTAssertEqual(opening.createdURLs, ["https://start.example"])
        XCTAssertFalse(windowState.presentationState.isCommandPaletteVisible)
    }

    func testRejectedExistingTabSelectionKeepsCommandPaletteOpen() {
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
        windowState.commandPaletteDraftText = "keep me"
        let presentation = makePresentation()
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let commit = makeCommit(
            presentation: presentation,
            selectTab: { _, _ in .rejected }
        )

        commit.commitSuggestion(
            SearchManager.SearchSuggestion(
                text: tab.name,
                type: .tab(tab)
            ),
            in: windowState
        )

        XCTAssertTrue(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPaletteDraftText, "keep me")
    }

    private func makePresentation(
        registry: WindowRegistry? = nil,
        splitCancellation: EmptySplitSession? = nil,
        persistence: CommandPalettePersistenceSpy = .init(),
        dismissThemePicker: @escaping @MainActor () -> Void = { /* no-op */ }
    ) -> CommandPalettePresentationService {
        let splitCancellation = splitCancellation ?? makeSplitCancellation()
        return CommandPalettePresentationService(
            windowRegistry: { registry },
            hasValidCurrentSelection: { _ in false },
            splitCancellation: splitCancellation,
            dismissThemePickerDiscardingIfNeeded: dismissThemePicker,
            persistence: { persistence }
        )
    }

    private func makeCommit(
        presentation: CommandPalettePresentationService,
        opening: CommandPaletteTabOpeningSpy = .init(),
        split: EmptySplitService? = nil,
        activePageTab: @escaping @MainActor (BrowserWindowState) -> Tab? = { _ in nil },
        settings: SumiSettingsService? = nil,
        selectTab: @escaping @MainActor (
            Tab,
            BrowserWindowState
        ) -> BrowserTabSelectionOutcome = { _, _ in .committed },
        loadPage: @escaping @MainActor (URL, Tab, BrowserWindowState) -> Void = { _, _, _ in /* no-op */ }
    ) -> CommandPaletteCommitService {
        let split = split ?? BrowserManager().splitEmptyPlaceholders
        return CommandPaletteCommitService(
            presentation: presentation,
            tabOpening: { opening },
            tabTargets: CommandPaletteTabTargetCommitter(
                splitPlaceholders: split,
                selectTab: selectTab
            ),
            activePageTab: activePageTab,
            pageNavigation: CommandPalettePageNavigationService(
                settings: { settings },
                loadPage: loadPage
            ),
            newSplitView: { _ in /* no-op */ }
        )
    }

    private func makeSplitCancellation(
        recorder: CommandPaletteSplitPlaceholderSpy? = nil,
        windowID: UUID = UUID()
    ) -> EmptySplitSession {
        EmptySplitSession(
            structuralTransactions:
                CommandPaletteEmptySplitStructuralTransactions(),
            terminalMutations: CommandPaletteEmptySplitTerminalMutations(),
            placeholderRetirement: CommandPaletteEmptySplitRetirementPreparer(
                recorder: recorder,
                windowID: windowID
            )
        )
    }
}

@MainActor
private final class CommandPalettePersistenceSpy: CommandPaletteStatePersisting {
    struct ScheduledWrite: Equatable {
        let windowID: UUID
        let delayNanoseconds: UInt64
    }

    var persistedWindowIDs: [UUID] = []
    var scheduled: [ScheduledWrite] = []

    func persist(_ windowState: BrowserWindowState) {
        persistedWindowIDs.append(windowState.id)
    }

    func schedule(_ windowState: BrowserWindowState, delayNanoseconds: UInt64) {
        scheduled.append(.init(
            windowID: windowState.id,
            delayNanoseconds: delayNanoseconds
        ))
    }
}

@MainActor
private final class CommandPaletteSplitPlaceholderSpy {
    var cancelledWindowIDs: [UUID] = []
}

@MainActor
private final class CommandPaletteEmptySplitStructuralTransactions:
    EmptySplitStructuralTransactionAuthority {
    func withTransaction<T>(
        _ operation: @MainActor @Sendable () throws -> T
    ) rethrows -> T {
        try operation()
    }
}

@MainActor
private final class CommandPaletteEmptySplitTerminalMutations:
    EmptySplitTerminalMutationAuthority {
    func withReversibleSideEffects(_ operation: () -> Bool) -> Bool {
        operation()
    }
}

@MainActor
private final class CommandPaletteEmptySplitRetirementPreparer:
    EmptySplitPlaceholderRetirementPreparing {
    private let recorder: CommandPaletteSplitPlaceholderSpy?
    private let windowID: UUID

    init(recorder: CommandPaletteSplitPlaceholderSpy?, windowID: UUID) {
        self.recorder = recorder
        self.windowID = windowID
    }

    func prepareRetirement(
        _ placeholder: Tab
    ) -> (any EmptySplitPlaceholderRetirementMutation)? {
        CommandPaletteEmptySplitRetirementMutation(
            placeholder: placeholder,
            recorder: recorder,
            windowID: windowID
        )
    }
}

@MainActor
private final class CommandPaletteEmptySplitRetirementMutation:
    EmptySplitPlaceholderRetirementMutation {
    private enum State { case prepared, committed, published, cancelled }

    private let placeholder: Tab
    private let recorder: CommandPaletteSplitPlaceholderSpy?
    private let windowID: UUID
    private var state = State.prepared

    init(
        placeholder: Tab,
        recorder: CommandPaletteSplitPlaceholderSpy?,
        windowID: UUID
    ) {
        self.placeholder = placeholder
        self.recorder = recorder
        self.windowID = windowID
    }

    func isCurrent() -> Bool {
        if case .prepared = state { return true }
        return false
    }

    func commitModel() -> Bool {
        guard isCurrent() else { return false }
        _ = placeholder
        state = .committed
        recorder?.cancelledWindowIDs.append(windowID)
        return true
    }

    func publish() {
        guard case .committed = state else { return }
        state = .published
    }

    func rollback() {
        guard case .prepared = state else { return }
        state = .cancelled
    }
}

@MainActor
private final class CommandPaletteTabOpeningSpy: CommandPaletteTabOpening {
    var createdURLs: [String] = []
    var insertedURLs: [String] = []

    func createNewTab(in _: BrowserWindowState, url: String) -> Tab {
        createdURLs.append(url)
        return Tab(url: URL(string: url) ?? SumiSurface.emptyTabURL)
    }

    func createNewTabAfterSidebarInsertion(
        in _: BrowserWindowState,
        url: String
    ) -> Tab {
        insertedURLs.append(url)
        return Tab(url: URL(string: url) ?? SumiSurface.emptyTabURL)
    }
}

private struct CommandPaletteLoadedPage {
    let url: URL
    let tabID: UUID
    let windowID: UUID
}
