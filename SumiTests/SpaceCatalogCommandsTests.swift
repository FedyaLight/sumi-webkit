import Foundation
@testable import Sumi
import XCTest

@MainActor
final class SpaceCatalogCommandsTests: XCTestCase {
    func testCreateFirstSpaceUsesDefaultProfileAndSelectsWithoutActivation() throws {
        let tabManager = try makeInMemoryTabManager()
        tabManager.spaceStateOwner.removeAll()
        let profileID = UUID()
        let spy = Spy()
        let commands = makeCommands(
            tabManager: tabManager,
            defaultProfileID: { profileID },
            spy: spy
        )

        let created = commands.createSpace(name: "Work")

        XCTAssertEqual(created.profileId, profileID)
        XCTAssertEqual(
            created.workspaceTheme,
            SumiWorkspaceThemePresets.rotatingTheme(at: 0)
        )
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, created)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [created.id])
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner
                .tabsBySpaceSnapshot()[created.id],
            []
        )
        XCTAssertEqual(spy.changeAnnouncements, 1)
        XCTAssertTrue(
            tabManager.structuralPersistence.dirtySet.dirtySpaceIds
                .contains(created.id)
        )
    }

    func testCreateAdditionalSpacePreservesExplicitValuesWithoutChangingSelection() throws {
        let tabManager = try makeInMemoryTabManager()
        let current = Space(name: "Current")
        tabManager.spaceStateOwner.replaceSpaces([current])
        tabManager.spaceStateOwner.replaceCurrentSpace(current)
        let explicitProfileID = UUID()
        let explicitTheme = WorkspaceTheme.default
        let spy = Spy()
        let commands = makeCommands(tabManager: tabManager, spy: spy)

        let created = commands.createSpace(
            name: "Focus",
            icon: "star",
            workspaceTheme: explicitTheme,
            profileId: explicitProfileID
        )

        XCTAssertEqual(created.profileId, explicitProfileID)
        XCTAssertEqual(created.workspaceTheme, explicitTheme)
        XCTAssertEqual(
            created.icon,
            SumiPersistentGlyph.normalizedSpaceIconValue("star")
        )
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, current)
    }

    func testReorderPreservesCurrentSpaceIdentityAndMarksCatalogDirty() throws {
        let tabManager = try makeInMemoryTabManager()
        let first = Space(name: "First")
        let second = Space(name: "Second")
        let third = Space(name: "Third")
        tabManager.spaceStateOwner.replaceSpaces([first, second, third])
        tabManager.spaceStateOwner.replaceCurrentSpace(second)
        let spy = Spy()
        let commands = makeCommands(tabManager: tabManager, spy: spy)

        XCTAssertTrue(commands.reorderSpace(spaceId: first.id, to: 99))

        XCTAssertEqual(
            tabManager.spaceStateOwner.spaces.map(\.id),
            [second.id, third.id, first.id]
        )
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, second)
        XCTAssertEqual(spy.changeAnnouncements, 1)
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.dirtySpaceIds,
            Set([first.id, second.id, third.id])
        )
        XCTAssertFalse(commands.reorderSpace(spaceId: UUID(), to: 0))
        XCTAssertEqual(spy.changeAnnouncements, 1)
    }

    func testRenameNotifiesOnlyForARealChangeAndMissingSpaceThrows() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = Space(name: "Work")
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        let notifications = NotificationPresentingSpy()
        let spy = Spy()
        let commands = makeCommands(
            tabManager: tabManager,
            notifications: { notifications },
            spy: spy
        )

        try commands.renameSpace(spaceId: space.id, newName: "Work")
        XCTAssertEqual(spy.changeAnnouncements, 0)
        XCTAssertTrue(notifications.presentSpaceRenamedNotificationCalls.isEmpty)

        try commands.renameSpace(spaceId: space.id, newName: "Focus")
        XCTAssertEqual(space.name, "Focus")
        XCTAssertEqual(spy.changeAnnouncements, 1)
        XCTAssertEqual(
            notifications.presentSpaceRenamedNotificationCalls.map(\.name),
            ["Focus"]
        )

        XCTAssertThrowsError(
            try commands.renameSpace(spaceId: UUID(), newName: "Missing")
        )
    }

    func testUpdateIconNormalizesStoredValueAndMissingSpaceThrows() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = Space(name: "Work")
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        let spy = Spy()
        let commands = makeCommands(tabManager: tabManager, spy: spy)

        try commands.updateSpaceIcon(spaceId: space.id, icon: "house")

        XCTAssertEqual(
            space.icon,
            SumiPersistentGlyph.normalizedSpaceIconValue("house")
        )
        XCTAssertEqual(spy.changeAnnouncements, 1)
        XCTAssertThrowsError(
            try commands.updateSpaceIcon(spaceId: UUID(), icon: "star")
        )
    }

    private func makeCommands(
        tabManager: TabManager,
        defaultProfileID: @escaping @MainActor () -> UUID? = { nil },
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)? = { nil },
        spy: Spy
    ) -> SpaceCatalogCommands {
        SpaceCatalogCommands(
            transactions: tabManager.structuralLookupCoordinator,
            spaces: tabManager.spaceStateOwner,
            structuralMutations: tabManager.structuralCollectionMutationOwner,
            persistence: tabManager.structuralPersistence,
            defaultProfileID: defaultProfileID,
            announceChange: { spy.changeAnnouncements += 1 },
            notifications: notifications
        )
    }
}

@MainActor
private final class Spy {
    var changeAnnouncements = 0
}
