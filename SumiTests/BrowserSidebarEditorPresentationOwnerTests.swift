import XCTest
@testable import Sumi

@MainActor
final class BrowserSidebarEditorPresentationOwnerTests: XCTestCase {
    func testSpaceCommitAppliesChangedNameIconAndProfile() {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let originalProfileID = UUID()
        let updatedProfileID = UUID()
        let space = Space(name: "Old", icon: "square.grid.2x2", profileId: originalProfileID)
        let session = SpaceEditorSession(space: space)
        session.name = "  New  "
        session.icon = "star"
        session.profileID = updatedProfileID

        owner.commitSpaceEditorSession(session)

        XCTAssertEqual(
            spy.events,
            [
                .renameSpace(space.id, "New"),
                .updateSpaceIcon(space.id, "star"),
                .assignSpaceProfile(space.id, updatedProfileID),
            ]
        )
    }

    func testSpaceCommitSkipsUnchangedAndInvalidSessions() {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let space = Space(name: "Old", icon: "square.grid.2x2", profileId: UUID())
        let unchangedSession = SpaceEditorSession(space: space)
        let invalidSession = SpaceEditorSession(space: space)
        invalidSession.name = " "
        invalidSession.icon = "star"

        owner.commitSpaceEditorSession(unchangedSession)
        owner.commitSpaceEditorSession(invalidSession)

        XCTAssertEqual(spy.events, [])
    }

    func testFolderCommitAppliesChangedNameAndIcon() {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let folder = TabFolder(name: "Old", spaceId: UUID(), icon: "folder")
        let session = FolderEditorSession(folder: folder)
        session.name = "  New Folder  "
        session.icon = "folder.badge.plus"

        owner.commitFolderEditorSession(session)

        XCTAssertEqual(
            spy.events,
            [
                .renameFolder(folder.id, "New Folder"),
                .updateFolderIcon(folder.id, "folder.badge.plus"),
            ]
        )
    }

    func testShortcutCommitNormalizesURLAndUpdatesPin() throws {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let pin = try makeShortcutPin()
        let session = ShortcutLinkEditorSession(pin: pin)
        session.title = "  New Title  "
        session.urlText = "new.example/path"
        session.iconAsset = "star"
        let expectedURL = try XCTUnwrap(URL(string: "https://new.example/path"))

        owner.commitShortcutEditorSession(session)

        XCTAssertEqual(
            spy.events,
            [
                .updateShortcutPin(pin.id, "New Title", expectedURL, "star"),
            ]
        )
    }

    func testShortcutCommitSkipsInvalidURL() throws {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let pin = try makeShortcutPin()
        let session = ShortcutLinkEditorSession(pin: pin)
        session.title = "Changed"
        session.urlText = " "

        owner.commitShortcutEditorSession(session)

        XCTAssertEqual(spy.events, [])
    }

    private func makeOwner(spy: Spy) -> BrowserSidebarEditorPresentationOwner {
        BrowserSidebarEditorPresentationOwner(
            dependencies: BrowserSidebarEditorPresentationOwner.Dependencies(
                sidebarPosition: { .left },
                settings: { SumiSettingsService() },
                profiles: { [] },
                renameSpace: { spaceID, name in
                    spy.events.append(.renameSpace(spaceID, name))
                },
                updateSpaceIcon: { spaceID, icon in
                    spy.events.append(.updateSpaceIcon(spaceID, icon))
                },
                assignSpaceProfile: { spaceID, profileID in
                    spy.events.append(.assignSpaceProfile(spaceID, profileID))
                },
                renameFolder: { folderID, name in
                    spy.events.append(.renameFolder(folderID, name))
                },
                updateFolderIcon: { folderID, icon in
                    spy.events.append(.updateFolderIcon(folderID, icon))
                },
                updateShortcutPin: { pin, title, launchURL, iconAsset in
                    spy.events.append(
                        .updateShortcutPin(pin.id, title, launchURL, iconAsset)
                    )
                }
            )
        )
    }

    private func makeShortcutPin() throws -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: UUID(),
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://old.example")),
            title: "Old Title"
        )
    }
}

private final class Spy {
    var events: [BrowserSidebarEditorPresentationOwnerTests.Event] = []
}

extension BrowserSidebarEditorPresentationOwnerTests {
    enum Event: Equatable {
        case renameSpace(UUID, String)
        case updateSpaceIcon(UUID, String)
        case assignSpaceProfile(UUID, UUID)
        case renameFolder(UUID, String)
        case updateFolderIcon(UUID, String)
        case updateShortcutPin(UUID, String, URL, String?)
    }
}
