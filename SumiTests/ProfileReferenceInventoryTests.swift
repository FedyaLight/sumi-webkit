@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class ProfileReferenceInventoryTests: XCTestCase {
    func testRuntimeStateCollectsEveryStructuralProfileReference() throws {
        let spaceProfileID = UUID()
        let tabProfileID = UUID()
        let pinnedKeyProfileID = UUID()
        let pinnedProfileID = UUID()
        let pinnedExecutionProfileID = UUID()
        let spacePinnedProfileID = UUID()
        let spacePinnedExecutionProfileID = UUID()
        let pendingProfileID = UUID()
        let pendingExecutionProfileID = UUID()
        let splitContainerProfileID = UUID()
        let splitReturnProfileID = UUID()
        let currentProfileID = UUID()
        let currentSpaceProfileID = UUID()
        let currentTabProfileID = UUID()

        let space = makeSpace(profileID: spaceProfileID)
        let tab = makeTab(profileID: tabProfileID)
        let pinned = makePin(
            profileID: pinnedProfileID,
            executionProfileID: pinnedExecutionProfileID
        )
        let spacePinned = makePin(
            profileID: spacePinnedProfileID,
            executionProfileID: spacePinnedExecutionProfileID
        )
        let pending = makePin(
            profileID: pendingProfileID,
            executionProfileID: pendingExecutionProfileID
        )
        let splitGroup = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(UUID()),
                .shortcutPin(UUID()),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: splitContainerProfileID,
                folderId: nil,
                index: 0
            )
        ))

        let state = SumiImportRuntimeState(
            profiles: [],
            currentProfile: Profile(id: currentProfileID),
            spaces: [space],
            tabsBySpace: [space.id: [tab]],
            foldersBySpace: [:],
            pinnedByProfile: [pinnedKeyProfileID: [pinned]],
            spacePinnedShortcuts: [space.id: [spacePinned]],
            pendingPinnedWithoutProfile: [pending],
            splitGroups: [splitGroup],
            currentSpace: makeSpace(profileID: currentSpaceProfileID),
            currentTab: makeTab(profileID: currentTabProfileID)
        )

        let inventory = ProfileReferenceInventory(runtimeState: state)

        XCTAssertEqual(inventory.profileIDs, [
            spaceProfileID,
            tabProfileID,
            pinnedKeyProfileID,
            pinnedProfileID,
            pinnedExecutionProfileID,
            spacePinnedProfileID,
            spacePinnedExecutionProfileID,
            pendingProfileID,
            pendingExecutionProfileID,
            splitContainerProfileID,
            splitReturnProfileID,
            currentProfileID,
            currentSpaceProfileID,
            currentTabProfileID,
        ])
        XCTAssertTrue(inventory.contains(splitReturnProfileID))
        XCTAssertFalse(inventory.contains(UUID()))
    }

    func testTabSnapshotCollectsSpaceTabExecutionAndSplitReferences() throws {
        let spaceProfileID = UUID()
        let tabProfileID = UUID()
        let executionProfileID = UUID()
        let splitContainerProfileID = UUID()
        let splitReturnProfileID = UUID()
        let spaceID = UUID()
        let splitGroup = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(UUID()),
                .shortcutPin(UUID()),
            ],
            layoutKind: .horizontal,
            container: .shortcutSidebar(
                spaceId: spaceID,
                profileId: splitContainerProfileID,
                folderId: nil,
                index: nil
            )
        ))
        let snapshot = TabPersistenceSnapshot(
            spaces: [
                TabPersistenceSpace(
                    id: spaceID,
                    name: "Space",
                    icon: "circle",
                    index: 0,
                    workspaceThemeData: nil,
                    profileId: spaceProfileID
                ),
            ],
            tabs: [
                TabPersistenceTab(
                    id: UUID(),
                    urlString: "https://example.com",
                    name: "Tab",
                    index: 0,
                    spaceId: spaceID,
                    isPinned: true,
                    isSpacePinned: false,
                    profileId: tabProfileID,
                    executionProfileId: executionProfileID,
                    folderId: nil,
                    iconAsset: nil,
                    currentURLString: nil,
                    canGoBack: false,
                    canGoForward: false
                ),
            ],
            folders: [],
            splitGroups: [splitGroup],
            state: TabPersistenceSelection(
                currentTabID: nil,
                currentSpaceID: spaceID
            )
        )

        let inventory = ProfileReferenceInventory(tabSnapshot: snapshot)

        XCTAssertEqual(inventory.profileIDs, [
            spaceProfileID,
            tabProfileID,
            executionProfileID,
            splitContainerProfileID,
            splitReturnProfileID,
        ])
    }

    func testWindowSnapshotsAndLiveWindowExposeCurrentProfileReference() {
        let profileID = UUID()
        let snapshot = makeWindowSnapshot(currentProfileID: profileID)

        XCTAssertEqual(
            ProfileReferenceInventory(windowSnapshot: snapshot).profileIDs,
            [profileID]
        )
        XCTAssertEqual(
            ProfileReferenceInventory(
                lastSessionWindowSnapshot: LastSessionWindowSnapshot(
                    id: UUID(),
                    session: snapshot
                )
            ).profileIDs,
            [profileID]
        )

        let windowState = BrowserWindowState()
        windowState.currentProfileId = profileID
        XCTAssertEqual(
            ProfileReferenceInventory(windowState: windowState).profileIDs,
            [profileID]
        )
    }

    func testNilAndDuplicateReferencesDoNotCreateFalseEntries() {
        let repeatedProfileID = UUID()
        let space = makeSpace(profileID: repeatedProfileID)
        let pin = makePin(
            profileID: repeatedProfileID,
            executionProfileID: repeatedProfileID
        )
        let state = SumiImportRuntimeState(
            profiles: [],
            currentProfile: nil,
            spaces: [space, makeSpace(profileID: nil)],
            tabsBySpace: [space.id: [makeTab(profileID: repeatedProfileID)]],
            foldersBySpace: [:],
            pinnedByProfile: [repeatedProfileID: [pin]],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [],
            splitGroups: [],
            currentSpace: nil,
            currentTab: nil
        )

        XCTAssertEqual(
            ProfileReferenceInventory(runtimeState: state).profileIDs,
            [repeatedProfileID]
        )
        XCTAssertTrue(
            ProfileReferenceInventory(
                windowSnapshot: makeWindowSnapshot(currentProfileID: nil)
            ).profileIDs.isEmpty
        )
    }

    private func makeSpace(profileID: UUID?) -> Space {
        Space(name: "Space", profileId: profileID)
    }

    private func makeTab(profileID: UUID?) -> Tab {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.profileId = profileID
        return tab
    }

    private func makePin(
        profileID: UUID?,
        executionProfileID: UUID?
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: profileID == nil ? .spacePinned : .essential,
            profileId: profileID,
            executionProfileId: executionProfileID,
            spaceId: nil,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Pin"
        )
    }

    private func makeWindowSnapshot(
        currentProfileID: UUID?
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: UUID(),
            currentSpaceId: UUID(),
            currentProfileId: currentProfileID,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: false,
            floatingBarReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: 240,
            savedSidebarWidth: 240,
            sidebarContentWidth: 220,
            isSidebarVisible: true,
            floatingBarDraft: FloatingBarDraftState(
                text: "",
                navigateCurrentTab: false
            )
        )
    }
}
