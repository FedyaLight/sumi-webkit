import Foundation
@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class BrowserWindowSpaceContextTransitionTests: XCTestCase {
    func testProgrammaticChangeCommitsContextBeforeThemeUpdate() throws {
        let tabManager = BrowserManager()
        let source = Space(name: "Source", profileId: UUID())
        let destination = Space(
            name: "Destination",
            workspaceTheme: WorkspaceTheme(gradientTheme: .incognito),
            profileId: UUID()
        )
        tabManager.spaceStateOwner.replaceSpaces([source, destination])
        let windowState = BrowserWindowState()
        tabManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        tabManager.windowRegistry.register(windowState)
        windowState.currentSpaceId = source.id
        windowState.currentProfileId = source.profileId
        let transition = makeTransition(tabManager: tabManager)

        transition.commitContext(destination, to: windowState)
        transition.completeVisualTransition(
            to: destination,
            in: windowState,
            identity: nil
        )

        XCTAssertEqual(windowState.currentSpaceId, destination.id)
        XCTAssertEqual(windowState.currentProfileId, destination.profileId)
        XCTAssertEqual(
            windowState.windowThemeState.targetTheme,
            destination.workspaceTheme
        )
    }

    func testInteractiveChangeFinishesOnlyMatchingVisualTransition() throws {
        let tabManager = BrowserManager()
        let source = Space(name: "Source", profileId: UUID())
        let destination = Space(
            name: "Destination",
            workspaceTheme: WorkspaceTheme(gradientTheme: .incognito),
            profileId: UUID()
        )
        tabManager.spaceStateOwner.replaceSpaces([source, destination])
        let windowState = BrowserWindowState()
        tabManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        tabManager.windowRegistry.register(windowState)
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
        let transition = makeTransition(tabManager: tabManager)

        transition.commitContext(destination, to: windowState)
        transition.completeVisualTransition(
            to: destination,
            in: windowState,
            identity: identity
        )

        XCTAssertEqual(windowState.currentSpaceId, destination.id)
        XCTAssertEqual(
            windowState.windowThemeState.committedTheme,
            destination.workspaceTheme
        )
        XCTAssertNil(
            windowState.windowThemeState.interactiveSpaceTransitionIdentity
        )
    }

    func testPreservedSelectionRefreshSanitizesBeforeContextAndShortcutSync() throws {
        let tabManager = BrowserManager()
        let space = Space(name: "Current", profileId: UUID())
        tabManager.spaceStateOwner.replaceSpaces([space])
        let windowState = BrowserWindowState()
        tabManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        tabManager.windowRegistry.register(windowState)
        windowState.currentSpaceId = space.id
        let transition = makeTransition(tabManager: tabManager)

        transition.sanitizePreservedSelection(in: windowState)
        transition.commitContext(space, to: windowState)
        transition.completePreservedSelectionRefresh(in: windowState)

        XCTAssertEqual(windowState.currentProfileId, space.profileId)
    }

    private func makeTransition(
        tabManager: BrowserManager
    ) -> BrowserWindowSpaceContextTransition {
        BrowserWindowSpaceContextTransition(
            contextReconciler: BrowserWindowSpaceContextReconciler(
                membership: tabManager.tabCollectionMembershipOwner,
                spaces: tabManager.spaceStateOwner
            ),
            commandPalette: tabManager.commandPalettePresentation,
            selection: tabManager.browserTabSelection,
            workspaceThemes: tabManager.workspaceThemeTransitionOwner
        )
    }
}
