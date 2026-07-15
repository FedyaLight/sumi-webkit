import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class PublicationFixture {
    let tabManager: TabManager
    let window: BrowserWindowState
    let pins: [ShortcutPin]
    let liveTabs: [Tab]
    let group: SplitGroup
    let folder: TabFolder?

    init(
        pinCount: Int,
        foldered: Bool = false,
        hostedSplit: Bool = false
    ) throws {
        let window = BrowserWindowState()
        self.window = window
        var manager: TabManager!
        manager = try makeInMemoryTabManager(
            windowState: { [window] id in id == window.id ? window : nil },
            windows: { [window] in [(window.id, window)] }
        )
        tabManager = manager
        window.tabManager = manager
        let space = manager.spaceServices.catalog.createSpace(name: "Space")
        window.currentSpaceId = space.id
        let createdFolder = foldered
            ? manager.folderMutationOwner.createFolder(for: space.id)
            : nil
        folder = createdFolder
        let createdPins = try (0..<pinCount).map { index in
            try XCTUnwrap(manager.shortcutPinStoreOwner.insert(
                Self.makePin(
                    index: index,
                    spaceID: space.id,
                    folderID: createdFolder?.id
                ),
                at: index
            ))
        }
        pins = createdPins
        let createdLiveTabs = try createdPins.map { pin in
            try XCTUnwrap(manager.shortcutTabMaterializer.materialize(
                pin, in: window.id, currentSpaceId: space.id
            ))
        }
        liveTabs = createdLiveTabs
        let createdGroup = try XCTUnwrap(SplitGroup.make(
            members: createdPins.enumerated().map { index, pin in
                .shortcutPin(
                    pin.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: createdFolder?.id,
                        index: index
                    )
                )
            },
            layoutKind: .vertical,
            container: hostedSplit
                ? .shortcutSidebar(
                    spaceId: space.id,
                    profileId: nil,
                    folderId: createdFolder?.id,
                    index: 0
                )
                : .regularTabs(spaceId: space.id)
        ))
        group = createdGroup
        XCTAssertTrue(manager.splitGroupMutations.insert(
            createdGroup, persist: false
        ))
        window.currentTabId = createdLiveTabs[0].id
        window.currentShortcutPinId = createdPins[0].id
        window.currentShortcutPinRole = createdPins[0].role
        window.splitSelection = WindowSplitSelection(
            groupID: createdGroup.id,
            activeMemberID: .shortcutPin(createdPins[0].id)
        )
    }

    static func makePin(
        index: Int,
        spaceID: UUID,
        folderID: UUID? = nil
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(), role: .spacePinned, spaceId: spaceID, index: index,
            folderId: folderID,
            launchURL: URL(string: "https://pin-\(index).example")!,
            title: "Pin \(index)"
        )
    }
}

@MainActor
final class PublicationOracle {
    var structuralCallbacks = 0
    var windowCallbacks = 0
    var failures = 0

    func assertTerminal(
        fixture: PublicationFixture,
        removedPin: ShortcutPin,
        removedTab: Tab,
        remaining: SplitGroup
    ) {
        let isTerminal = fixture.tabManager.shortcutPinCollectionStateOwner
            .shortcutPin(by: removedPin.id) == nil
            && fixture.tabManager.liveShortcutTabs
                .entries(for: removedPin.id).isEmpty
            && fixture.tabManager.tabCollectionMembershipOwner
                .tab(for: removedTab.id) == nil
            && fixture.tabManager.splitGroupStore.group(id: remaining.id)
                == remaining
            && fixture.window.splitSelection?.groupID == remaining.id
            && fixture.window.currentShortcutPinId != removedPin.id
        if isTerminal == false { failures += 1 }
        XCTAssertTrue(isTerminal)
    }
}
