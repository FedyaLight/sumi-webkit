import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class PublicationFixture {
    let browser: BrowserManager
    let window: BrowserWindowState
    let pins: [ShortcutPin]
    let liveTabs: [Tab]
    let group: SplitGroup
    let folder: TabFolder?

    init(
        pinCount: Int,
        foldered: Bool = false,
        hostedSplit: Bool = true
    ) throws {
        let profile = Profile(name: "Publication")
        let window = BrowserWindowState()
        self.window = window
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            windowStates: { [window] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .accepting
            )
        )
        let browser = BrowserManager(runtimePorts: runtime)
        self.browser = browser
        let registry = browser.windowRegistry
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        registry.register(window)
        let space = try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        window.currentSpaceId = space.id
        window.currentProfileId = profile.id
        let createdFolder = foldered
            ? browser.sidebarFolderCommands.createFolder(
                in: space.id,
                name: "Folder"
            )
            : nil
        folder = createdFolder
        let createdPins = try (0..<pinCount).map { index in
            try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
                Self.makePin(
                    index: index,
                    spaceID: space.id,
                    folderID: createdFolder?.id
                ),
                at: index
            ))
        }
        let createdLiveTabs = try createdPins.map { pin in
            try XCTUnwrap(browser.shortcutTabMaterializer.materialize(
                pin, in: window.id, currentSpaceId: space.id
            ))
        }
        liveTabs = createdLiveTabs
        let createdGroup = try XCTUnwrap(SplitGroup.make(
            members: createdPins.map { pin in
                .shortcutPin(pin.id)
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
        XCTAssertTrue(browser.splitGroupMutations.insert(
            createdGroup, persist: false
        ))
        pins = try createdPins.map { pin in
            try XCTUnwrap(
                browser.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id)
            )
        }
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
        let isTerminal = fixture.browser.shortcutPinCollectionStateOwner
            .shortcutPin(by: removedPin.id) == nil
            && fixture.browser.liveShortcutTabs
                .entries(for: removedPin.id).isEmpty
            && fixture.browser.tabCollectionMembershipOwner
                .tab(for: removedTab.id) == nil
            && fixture.browser.splitGroupStore.group(id: remaining.id)
                == remaining
            && fixture.window.splitSelection?.groupID == remaining.id
            && fixture.window.currentShortcutPinId != removedPin.id
        if isTerminal == false { failures += 1 }
        XCTAssertTrue(isTerminal)
    }
}
