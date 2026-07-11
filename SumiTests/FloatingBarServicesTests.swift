@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class FloatingBarServicesTests: XCTestCase {
    func testRetainedServicesDoNotRetainBrowserKernel() {
        var browserManager: BrowserManager? = BrowserManager()
        weak var releasedBrowserManager = browserManager
        weak var releasedTabManager = browserManager?.tabManager
        weak var releasedSplitManager = browserManager?.splitManager
        let retainedServices = browserManager?.urlBarBundle.floatingBar

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(releasedTabManager)
        XCTAssertNil(releasedSplitManager)
        withExtendedLifetime(retainedServices) { /* prove retained capabilities are harmless */ }
    }

    func testPresentationPreservesDraftAndPersistsEachStateActionOnce() {
        let persistence = FloatingBarPersistenceSpy()
        let split = FloatingBarSplitPlaceholderSpy()
        var themeDismissCount = 0
        let presentation = makePresentation(
            split: split,
            persistence: persistence,
            dismissThemePicker: { themeDismissCount += 1 }
        )
        let windowState = BrowserWindowState()
        windowState.floatingBarDraftText = "preserved"

        presentation.focus(
            in: windowState,
            prefill: "",
            navigateCurrentTab: false,
            reason: .keyboard
        )

        XCTAssertEqual(windowState.floatingBarDraftText, "preserved")
        XCTAssertTrue(windowState.isFloatingBarVisible)
        XCTAssertEqual(themeDismissCount, 1)
        XCTAssertEqual(persistence.persistedWindowIDs, [windowState.id])

        presentation.updateDraft(in: windowState, text: "changed")
        presentation.updateDraft(in: windowState, text: "changed")

        XCTAssertEqual(persistence.scheduled, [
            .init(windowID: windowState.id, delayNanoseconds: 450_000_000),
        ])

        presentation.dismiss(in: windowState, preserveDraft: true)

        XCTAssertEqual(windowState.floatingBarDraftText, "changed")
        XCTAssertFalse(windowState.isFloatingBarVisible)
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
        activeWindow.isFloatingBarVisible = true
        activeWindow.floatingBarDraftText = "active draft"
        otherWindow.isFloatingBarVisible = true
        let persistence = FloatingBarPersistenceSpy()
        let presentation = makePresentation(
            registry: registry,
            persistence: persistence
        )

        presentation.dismissActiveWindow(preserveDraft: true)

        XCTAssertFalse(activeWindow.isFloatingBarVisible)
        XCTAssertEqual(activeWindow.floatingBarDraftText, "active draft")
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
        windowState.floatingBarDraftNavigatesCurrentTab = true
        windowState.isFloatingBarVisible = true
        let persistence = FloatingBarPersistenceSpy()
        let split = FloatingBarSplitPlaceholderSpy()
        let opening = FloatingBarTabOpeningSpy()
        var loadedPages: [FloatingBarLoadedPage] = []
        let presentation = makePresentation(
            split: split,
            persistence: persistence
        )
        let commit = makeCommit(
            presentation: presentation,
            opening: opening,
            split: split,
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

        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)
        XCTAssertEqual(persistence.persistedWindowIDs, [windowState.id])
        XCTAssertEqual(split.committed, [
            .init(tabID: pageTab.id, windowID: windowState.id),
        ])
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
        windowState.floatingBarDraftNavigatesCurrentTab = true
        XCTAssertFalse(noPageCommit.commitNavigatesCurrentTab(in: windowState))
        XCTAssertTrue(pageCommit.commitNavigatesCurrentTab(in: windowState))
    }

    func testConfiguredNewTabPageBypassesFloatingBar() throws {
        let suiteName = "FloatingBarServicesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SumiSettingsService(userDefaults: defaults)
        settings.newTabMode = .specificPage
        settings.newTabPageURLString = "start.example"
        let windowState = BrowserWindowState()
        let opening = FloatingBarTabOpeningSpy()
        let presentation = makePresentation()
        let commit = makeCommit(
            presentation: presentation,
            opening: opening,
            settings: settings
        )

        commit.openNewTabSurface(in: windowState)

        XCTAssertEqual(opening.createdURLs, ["https://start.example"])
        XCTAssertFalse(windowState.isFloatingBarVisible)
    }

    private func makePresentation(
        registry: WindowRegistry? = nil,
        split: FloatingBarSplitPlaceholderSpy = .init(),
        persistence: FloatingBarPersistenceSpy = .init(),
        dismissThemePicker: @escaping @MainActor () -> Void = { /* no-op */ }
    ) -> FloatingBarPresentationService {
        FloatingBarPresentationService(
            windowRegistry: { registry },
            hasValidCurrentSelection: { _ in false },
            splitPlaceholders: { split },
            dismissThemePickerDiscardingIfNeeded: dismissThemePicker,
            persistence: { persistence }
        )
    }

    private func makeCommit(
        presentation: FloatingBarPresentationService,
        opening: FloatingBarTabOpeningSpy = .init(),
        split: FloatingBarSplitPlaceholderSpy = .init(),
        activePageTab: @escaping @MainActor (BrowserWindowState) -> Tab? = { _ in nil },
        settings: SumiSettingsService? = nil,
        loadPage: @escaping @MainActor (URL, Tab, BrowserWindowState) -> Void = { _, _, _ in /* no-op */ }
    ) -> FloatingBarCommitService {
        FloatingBarCommitService(
            presentation: presentation,
            tabOpening: { opening },
            splitPlaceholders: { split },
            activePageTab: activePageTab,
            selectTab: { _, _ in /* no-op */ },
            pageNavigation: FloatingBarPageNavigationService(
                settings: { settings },
                loadPage: loadPage
            )
        )
    }
}

@MainActor
private final class FloatingBarPersistenceSpy: FloatingBarStatePersisting {
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
private final class FloatingBarSplitPlaceholderSpy:
    FloatingBarSplitPlaceholderHandling {
    struct Commit: Equatable {
        let tabID: UUID
        let windowID: UUID
    }

    var cancelledWindowIDs: [UUID] = []
    var committed: [Commit] = []

    func cancelEmptySplitPlaceholder(in windowState: BrowserWindowState) -> Bool {
        cancelledWindowIDs.append(windowState.id)
        return true
    }

    func commitEmptySplitPlaceholder(
        tabId: UUID,
        in windowState: BrowserWindowState
    ) {
        committed.append(.init(tabID: tabId, windowID: windowState.id))
    }

    func replaceEmptySplitPlaceholder(
        with _: Tab,
        in _: BrowserWindowState
    ) -> Bool {
        false
    }
}

@MainActor
private final class FloatingBarTabOpeningSpy: FloatingBarTabOpening {
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

private struct FloatingBarLoadedPage {
    let url: URL
    let tabID: UUID
    let windowID: UUID
}
