import Combine
import Foundation
import SumiDomain
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class SpaceCatalogCommandsTests: XCTestCase {
    func testCreateFirstSpaceUsesDefaultProfileAndSelectsWithoutActivation() throws {
        let profileID = UUID()
        let spy = Spy()
        let fixture = try SpaceCatalogFixture(
            defaultProfileID: { profileID },
            spy: spy
        )
        fixture.spaces.removeAll()

        let created = fixture.commands.createSpace(name: "Work")

        XCTAssertEqual(created.profileId, profileID)
        XCTAssertEqual(
            created.workspaceTheme,
            SumiWorkspaceThemePresets.rotatingTheme(at: 0)
        )
        XCTAssertIdentical(fixture.spaces.currentSpace, created)
        XCTAssertEqual(fixture.spaces.spaces.map(\.id), [created.id])
        XCTAssertEqual(
            fixture.regularTabs.tabsBySpaceSnapshot()[created.id],
            []
        )
        XCTAssertEqual(spy.changeAnnouncements, 1)
        XCTAssertTrue(
            fixture.persistence.dirtySet.dirtySpaceIds
                .contains(created.id)
        )
    }

    func testCreateAdditionalSpacePreservesExplicitValuesWithoutChangingSelection() throws {
        let fixture = try SpaceCatalogFixture(spy: Spy())
        let current = Space(name: "Current")
        fixture.spaces.replaceSpaces([current])
        fixture.spaces.replaceCurrentSpace(current)
        let reservedSpaceID = UUID()
        let explicitProfileID = UUID()
        let explicitTheme = WorkspaceTheme.default

        let created = fixture.commands.createSpace(
            id: reservedSpaceID,
            name: "Focus",
            icon: "star",
            workspaceTheme: explicitTheme,
            profileId: explicitProfileID
        )

        XCTAssertEqual(created.id, reservedSpaceID)
        XCTAssertEqual(created.profileId, explicitProfileID)
        XCTAssertEqual(created.workspaceTheme, explicitTheme)
        XCTAssertEqual(
            created.icon,
            SumiPersistentGlyph.normalizedSpaceIconValue("star")
        )
        XCTAssertIdentical(fixture.spaces.currentSpace, current)
    }

    func testReorderPreservesCurrentSpaceIdentityAndMarksCatalogDirty() throws {
        let spy = Spy()
        let fixture = try SpaceCatalogFixture(spy: spy)
        let first = Space(name: "First")
        let second = Space(name: "Second")
        let third = Space(name: "Third")
        fixture.spaces.replaceSpaces([first, second, third])
        fixture.spaces.replaceCurrentSpace(second)

        XCTAssertTrue(fixture.commands.reorderSpace(spaceId: first.id, to: 99))

        XCTAssertEqual(
            fixture.spaces.spaces.map(\.id),
            [second.id, third.id, first.id]
        )
        XCTAssertIdentical(fixture.spaces.currentSpace, second)
        XCTAssertEqual(spy.changeAnnouncements, 1)
        XCTAssertEqual(
            fixture.persistence.dirtySet.dirtySpaceIds,
            Set([first.id, second.id, third.id])
        )
        XCTAssertFalse(fixture.commands.reorderSpace(spaceId: UUID(), to: 0))
        XCTAssertEqual(spy.changeAnnouncements, 1)
    }

    func testRenameNotifiesOnlyForARealChangeAndMissingSpaceThrows() throws {
        let notifications = NotificationPresentingSpy()
        let spy = Spy()
        let fixture = try SpaceCatalogFixture(
            notifications: notifications,
            spy: spy
        )
        let space = Space(name: "Work")
        fixture.spaces.replaceSpaces([space])
        fixture.spaces.replaceCurrentSpace(space)

        try fixture.commands.renameSpace(spaceId: space.id, newName: "Work")
        XCTAssertEqual(spy.changeAnnouncements, 0)
        XCTAssertTrue(notifications.presentSpaceRenamedNotificationCalls.isEmpty)

        try fixture.commands.renameSpace(spaceId: space.id, newName: "Focus")
        XCTAssertEqual(space.name, "Focus")
        XCTAssertEqual(spy.changeAnnouncements, 1)
        XCTAssertEqual(
            notifications.presentSpaceRenamedNotificationCalls.map(\.name),
            ["Focus"]
        )

        XCTAssertThrowsError(
            try fixture.commands.renameSpace(spaceId: UUID(), newName: "Missing")
        )
    }

    func testUpdateIconNormalizesStoredValueAndMissingSpaceThrows() throws {
        let spy = Spy()
        let fixture = try SpaceCatalogFixture(spy: spy)
        let space = Space(name: "Work")
        fixture.spaces.replaceSpaces([space])
        fixture.spaces.replaceCurrentSpace(space)

        try fixture.commands.updateSpaceIcon(spaceId: space.id, icon: "house")

        XCTAssertEqual(
            space.icon,
            SumiPersistentGlyph.normalizedSpaceIconValue("house")
        )
        XCTAssertEqual(spy.changeAnnouncements, 1)
        XCTAssertThrowsError(
            try fixture.commands.updateSpaceIcon(spaceId: UUID(), icon: "star")
        )
    }

    func testCreateSpaceRejectsBlockedProfileBeforeCatalogMutation() throws {
        let blockedProfileID = UUID()
        let spy = Spy()
        let fixture = try SpaceCatalogFixture(
            profileReferenceAdmission: .failClosed(),
            spy: spy
        )
        fixture.spaces.removeAll()

        let rejected = fixture.commands.createSpaceIfAdmitted(
            name: "Blocked",
            profileId: blockedProfileID
        )

        XCTAssertNil(rejected)
        XCTAssertTrue(fixture.spaces.spaces.isEmpty)
        XCTAssertEqual(spy.changeAnnouncements, 0)
    }
}

@MainActor
private final class SpaceCatalogFixture {
    let spaces: TabSpaceCollectionStateOwner
    let regularTabs: RegularTabCollectionStateOwner
    let persistence: TabStructuralPersistenceService
    let commands: SpaceCatalogCommands

    init(
        defaultProfileID: @escaping @MainActor () -> UUID? = { nil },
        profileReferenceAdmission: ProfileReferenceAdmissionLedger =
            .testingAllowingReferences(),
        notifications: (any BrowserNotificationPresenting)? = nil,
        spy: Spy
    ) throws {
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            profileReferenceAdmission: profileReferenceAdmission,
            loadPersistedState: false,
            automaticallyStartPersistedStateLoad: false
        )
        let state = tabManager.stateStore
        let transactions = TabStructuralLookupCoordinator(
            eventBus: tabManager.tabStructureEventBus,
            stateStore: state
        )
        let changes = ObservableObjectPublisher()
        let structuralMutations = TabStructuralCollectionMutationOwner(
            store: TabStructuralCollectionStore(
                regularTabs: state.regularTabs,
                folders: state.folders,
                shortcutPins: state.shortcutPins
            ),
            snapshots: TabStructuralCollectionSnapshotStore(
                regularTabs: state.regularTabs,
                folders: state.folders,
                shortcutPins: state.shortcutPins
            ),
            publisher: TabStructuralMutationPublisher(
                persistence: tabManager.structuralPersistence,
                faviconService: tabManager.faviconService,
                lookup: transactions,
                changes: changes,
                regularTabs: state.regularTabs
            )
        )
        let runtimeConnection = TabRuntimePortConnection(TestRuntimePorts.make(
            defaultProfileId: defaultProfileID,
            notifications: { notifications }
        ))
        let creation = SpaceCreationTransaction(
            transactions: transactions,
            spaces: state.spaces,
            runtimeConnection: runtimeConnection,
            profileReferenceAdmission: profileReferenceAdmission,
            committer: SpaceCreationCommitter(
                structuralMutations: structuralMutations,
                persistence: tabManager.structuralPersistence
            )
        )
        spaces = state.spaces
        regularTabs = state.regularTabs
        persistence = tabManager.structuralPersistence
        commands = SpaceCatalogCommands(
            transactions: transactions,
            spaces: state.spaces,
            creation: creation,
            runtimeConnection: runtimeConnection,
            publication: SpaceCatalogMutationPublication(
                persistence: tabManager.structuralPersistence,
                changes: changes
            )
        )
        spy.observe(changes)
    }
}

@MainActor
private final class Spy {
    var changeAnnouncements = 0
    private var observation: AnyCancellable?

    func observe(_ changes: ObservableObjectPublisher) {
        observation = changes.sink { [weak self] in
            self?.changeAnnouncements += 1
        }
    }
}
