@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class SidebarRegularTabsControllerTests: XCTestCase {
    func testExactRolesProjectCanonicalRegularTabStores() throws {
        let browserManager = BrowserManager()
        let profileID = UUID()
        let space = Space(name: "Work", profileId: profileID)
        let otherSpace = Space(name: "Other", profileId: profileID)
        let tab = makeTab(spaceId: space.id)
        let otherTab = makeTab(spaceId: otherSpace.id)
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://example.com/pin")),
            title: "Pinned"
        )
        let folder = TabFolder(name: "User", spaceId: space.id)
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(tab.id),
                    .regularTab(otherTab.id),
                ],
                layoutKind: .vertical
            )
        )

        browserManager.spaceStateOwner.replaceSpaces([space, otherSpace])
        browserManager.tabStateStore.regularTabs.replaceTabsBySpace([
            space.id: [tab],
            otherSpace.id: [otherTab],
        ])
        browserManager.shortcutPinCollectionStateOwner
            .replaceSpacePinnedShortcuts([space.id: [pin]])
        browserManager.folderCollectionStateOwner
            .replaceFoldersBySpace([space.id: [folder]])
        browserManager.splitGroupStore.replaceAll(with: [group])

        let catalog = browserManager.composeSidebarRegularTabCatalog()
        let targets = browserManager.composeSidebarRegularTabTargetQuery()
        let windowState = BrowserWindowState()

        XCTAssertEqual(catalog.allSpaces.map(\.id), [space.id, otherSpace.id])
        XCTAssertEqual(
            catalog.tabs(in: space, windowState: windowState).map(\.id),
            [tab.id]
        )
        XCTAssertTrue(catalog.hasPersistedTabs(in: space))
        XCTAssertIdentical(catalog.tab(for: tab.id), tab)
        XCTAssertEqual(
            targets.splitGroup(containing: .regularTab(tab.id))?.id,
            group.id
        )
        XCTAssertEqual(targets.shortcutPin(by: pin.id)?.id, pin.id)
        XCTAssertEqual(targets.userFolders(for: space.id).map(\.id), [folder.id])
        XCTAssertTrue(
            targets.canAddToFavorite(
                tab,
                in: space,
                windowState: windowState
            )
        )
    }

    func testIncognitoTabsComeFromWindowStateWithoutReadingPersistedTabs() {
        let browserManager = BrowserManager()
        let space = Space(name: "Private")
        let persisted = makeTab(spaceId: space.id, index: 2)
        let first = makeTab(spaceId: space.id, index: 1)
        let second = makeTab(spaceId: space.id, index: 0)
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        windowState.replaceEphemeralTabs([first, second])
        browserManager.tabStateStore.regularTabs.replaceTabsBySpace([
            space.id: [persisted],
        ])

        let catalog = browserManager.composeSidebarRegularTabCatalog()

        XCTAssertEqual(
            catalog.tabs(in: space, windowState: windowState).map(\.id),
            [second.id, first.id]
        )
        XCTAssertEqual(
            browserManager.tabStateStore.regularTabs
                .tabs(in: space.id)
                .map(\.id),
            [persisted.id]
        )
    }

    private func makeTab(spaceId: UUID, index: Int = 0) -> Tab {
        Tab(
            url: URL(string: "https://example.com/\(index)")!,
            name: "Example \(index)",
            favicon: "globe",
            spaceId: spaceId,
            index: index
        )
    }
}
