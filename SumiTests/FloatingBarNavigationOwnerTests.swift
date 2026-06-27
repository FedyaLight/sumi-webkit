import XCTest

@testable import Sumi

@MainActor
final class FloatingBarNavigationOwnerTests: XCTestCase {
    func testDismissActiveWindowAndWindowLookupAreOwnedByFloatingBarOwner() {
        let owner = FloatingBarNavigationOwner()
        let activeWindow = BrowserWindowState()
        let otherWindow = BrowserWindowState()
        activeWindow.isFloatingBarVisible = true
        activeWindow.floatingBarDraftText = "active draft"
        otherWindow.isFloatingBarVisible = true

        var cancelledWindows: [UUID] = []
        var persistedWindows: [UUID] = []
        let actions = makeActions(
            activeWindow: activeWindow,
            windows: [
                activeWindow.id: activeWindow,
                otherWindow.id: otherWindow
            ],
            cancelEmptySplitPlaceholder: { windowState in
                cancelledWindows.append(windowState.id)
            },
            persistWindowSession: { windowState in
                persistedWindows.append(windowState.id)
            }
        )

        owner.dismissActiveWindow(preserveDraft: true, actions: actions)

        XCTAssertFalse(activeWindow.isFloatingBarVisible)
        XCTAssertEqual(activeWindow.floatingBarDraftText, "active draft")
        XCTAssertEqual(cancelledWindows, [activeWindow.id])
        XCTAssertEqual(persistedWindows, [activeWindow.id])

        XCTAssertFalse(owner.dismissIfVisible(in: UUID(), preserveDraft: false, actions: actions))
        XCTAssertTrue(owner.dismissIfVisible(in: otherWindow.id, preserveDraft: false, actions: actions))
        XCTAssertFalse(otherWindow.isFloatingBarVisible)
    }

    func testCommitTargetResolutionRequiresDraftIntentAndActivePageTab() {
        let owner = FloatingBarNavigationOwner()
        let windowState = BrowserWindowState()
        let pageTab = Tab(url: URL(string: "https://example.com")!)
        let noPageActions = makeActions(activePageTab: { _ in nil })
        let pageActions = makeActions(activePageTab: { _ in pageTab })

        windowState.floatingBarDraftNavigatesCurrentTab = false
        XCTAssertFalse(owner.commitNavigatesCurrentTab(in: windowState, actions: pageActions))

        windowState.floatingBarDraftNavigatesCurrentTab = true
        XCTAssertFalse(owner.commitNavigatesCurrentTab(in: windowState, actions: noPageActions))

        XCTAssertTrue(owner.commitNavigatesCurrentTab(in: windowState, actions: pageActions))
    }

    func testOpenNewTabSurfaceOwnsConfiguredPageFallbackToFloatingBar() {
        let owner = FloatingBarNavigationOwner()
        let configuredWindow = BrowserWindowState()
        let floatingBarWindow = BrowserWindowState()
        var createdTabs: [(UUID, String)] = []
        var persistedWindows: [UUID] = []
        let configuredActions = makeActions(
            createNewTab: { windowState, url in
                createdTabs.append((windowState.id, url))
            },
            configuredNewTabPageURL: { "https://start.example/" },
            persistWindowSession: { windowState in
                persistedWindows.append(windowState.id)
            }
        )
        let floatingBarActions = makeActions(
            createNewTab: { windowState, url in
                createdTabs.append((windowState.id, url))
            },
            persistWindowSession: { windowState in
                persistedWindows.append(windowState.id)
            }
        )

        owner.openNewTabSurface(in: configuredWindow, actions: configuredActions)

        XCTAssertEqual(createdTabs.count, 1)
        XCTAssertEqual(createdTabs[0].0, configuredWindow.id)
        XCTAssertEqual(createdTabs[0].1, "https://start.example/")
        XCTAssertFalse(configuredWindow.isFloatingBarVisible)

        owner.openNewTabSurface(in: floatingBarWindow, actions: floatingBarActions)

        XCTAssertTrue(floatingBarWindow.isFloatingBarVisible)
        XCTAssertEqual(floatingBarWindow.floatingBarPresentationReason, .emptySpace)
        XCTAssertEqual(persistedWindows, [floatingBarWindow.id])
    }

    private func makeActions(
        activeWindow: BrowserWindowState? = nil,
        windows: [UUID: BrowserWindowState] = [:],
        activePageTab: @escaping @MainActor (BrowserWindowState) -> Tab? = { _ in nil },
        cancelEmptySplitPlaceholder: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
        createNewTab: @escaping @MainActor (BrowserWindowState, String) -> Void = { _, _ in },
        configuredNewTabPageURL: @escaping @MainActor () -> String? = { nil },
        persistWindowSession: @escaping @MainActor (BrowserWindowState) -> Void = { _ in }
    ) -> FloatingBarNavigationOwner.Actions {
        FloatingBarNavigationOwner.Actions(
            activeWindow: { activeWindow },
            window: { windows[$0] },
            activePageTab: activePageTab,
            cancelEmptySplitPlaceholder: cancelEmptySplitPlaceholder,
            commitEmptySplitPlaceholder: { _, _ in },
            replaceEmptySplitPlaceholder: { _, _ in false },
            selectTab: { _, _ in },
            createNewTab: createNewTab,
            createNewTabAfterSidebarInsertion: { _, _ in },
            configuredNewTabPageURL: configuredNewTabPageURL,
            normalizeURL: { $0 },
            dismissWorkspaceThemePickerIfNeededDiscarding: {},
            persistWindowSession: persistWindowSession,
            schedulePersistWindowSession: { _ in }
        )
    }
}
