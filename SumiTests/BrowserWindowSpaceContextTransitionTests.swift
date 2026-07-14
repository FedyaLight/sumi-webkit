import Foundation
import SumiDomain
@testable import Sumi
import XCTest

@MainActor
final class BrowserWindowSpaceContextTransitionTests: XCTestCase {
    func testProgrammaticChangeCommitsContextBeforeThemeUpdate() throws {
        let tabManager = try makeInMemoryTabManager()
        let source = Space(name: "Source", profileId: UUID())
        let destination = Space(
            name: "Destination",
            workspaceTheme: WorkspaceTheme(gradientTheme: .incognito),
            profileId: UUID()
        )
        tabManager.spaceStateOwner.replaceSpaces([source, destination])
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = source.id
        windowState.currentProfileId = source.profileId
        var events: [String] = []
        var observedCommittedContext = false
        let transition = makeTransition(
            tabManager: tabManager,
            sanitize: { _ in events.append("sanitize") },
            syncShortcuts: { _ in events.append("shortcut-sync") },
            updateTheme: { updatedWindow, theme, animate in
                observedCommittedContext = updatedWindow.currentSpaceId == destination.id
                    && updatedWindow.currentProfileId == destination.profileId
                XCTAssertEqual(theme, destination.workspaceTheme)
                XCTAssertTrue(animate)
                events.append("theme")
            },
            finishInteractive: { _, _, _ in events.append("finish") }
        )

        transition.commitContext(destination, to: windowState)
        transition.completeVisualTransition(
            to: destination,
            in: windowState,
            identity: nil
        )

        XCTAssertTrue(observedCommittedContext)
        XCTAssertEqual(events, ["theme"])
    }

    func testInteractiveChangeFinishesOnlyMatchingVisualTransition() throws {
        let tabManager = try makeInMemoryTabManager()
        let source = Space(name: "Source", profileId: UUID())
        let destination = Space(
            name: "Destination",
            workspaceTheme: WorkspaceTheme(gradientTheme: .incognito),
            profileId: UUID()
        )
        tabManager.spaceStateOwner.replaceSpaces([source, destination])
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = source.id
        let identity = SpaceTransitionIdentity(
            sourceSpaceId: source.id,
            destinationSpaceId: destination.id
        )
        windowState.windowThemeState.beginInteractive(
            identity: identity,
            from: source.workspaceTheme,
            to: destination.workspaceTheme,
            initialProgress: 0.6
        )
        var events: [String] = []
        var finishedIdentity: SpaceTransitionIdentity?
        let transition = makeTransition(
            tabManager: tabManager,
            sanitize: { _ in events.append("sanitize") },
            syncShortcuts: { _ in events.append("shortcut-sync") },
            updateTheme: { _, _, _ in events.append("theme") },
            finishInteractive: { finishedSpace, updatedWindow, finished in
                XCTAssertIdentical(finishedSpace, destination)
                XCTAssertEqual(updatedWindow.currentSpaceId, destination.id)
                finishedIdentity = finished
                events.append("finish")
            }
        )

        transition.commitContext(destination, to: windowState)
        transition.completeVisualTransition(
            to: destination,
            in: windowState,
            identity: identity
        )

        XCTAssertEqual(finishedIdentity, identity)
        XCTAssertEqual(events, ["finish"])
    }

    func testPreservedSelectionRefreshSanitizesBeforeContextAndShortcutSync() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = Space(name: "Current", profileId: UUID())
        tabManager.spaceStateOwner.replaceSpaces([space])
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        var events: [String] = []
        var profileAtShortcutSync: UUID?
        let transition = makeTransition(
            tabManager: tabManager,
            sanitize: { _ in events.append("sanitize") },
            syncShortcuts: { updatedWindow in
                profileAtShortcutSync = updatedWindow.currentProfileId
                events.append("shortcut-sync")
            },
            updateTheme: { _, _, _ in events.append("theme") },
            finishInteractive: { _, _, _ in events.append("finish") }
        )

        transition.sanitizePreservedSelection(in: windowState)
        transition.commitContext(space, to: windowState)
        transition.completePreservedSelectionRefresh(in: windowState)

        XCTAssertEqual(profileAtShortcutSync, space.profileId)
        XCTAssertEqual(events, ["sanitize", "shortcut-sync"])
    }

    private func makeTransition(
        tabManager: TabManager,
        sanitize: @escaping (BrowserWindowState) -> Void,
        syncShortcuts: @escaping (BrowserWindowState) -> Void,
        updateTheme: @escaping (BrowserWindowState, WorkspaceTheme, Bool) -> Void,
        finishInteractive: @escaping (
            Space,
            BrowserWindowState,
            SpaceTransitionIdentity
        ) -> Void
    ) -> BrowserWindowSpaceContextTransition {
        BrowserWindowSpaceContextTransition(
            contextReconciler: BrowserWindowSpaceContextReconciler(
                tabManager: tabManager,
                commitWorkspaceTheme: { _, _ in
                    XCTFail("Context synchronization must not commit a second theme")
                }
            ),
            sanitizeFloatingBarState: sanitize,
            syncShortcutSelectionState: syncShortcuts,
            updateWorkspaceTheme: updateTheme,
            finishInteractiveTransition: finishInteractive
        )
    }
}
