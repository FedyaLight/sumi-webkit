import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarSplitGroupDuplicationTests: XCTestCase {
    func testRegularDuplicateIsAdjacentInactiveAndCopiesMetadata() throws {
        let browser = BrowserManager()
        let space = Space(name: "Work")
        browser.spaceStateOwner.replaceSpaces([space])
        let first = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://one.example",
            in: space,
            activate: false
        )
        let second = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://two.example",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(first.id), .regularTab(second.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id),
            title: "Research",
            iconAsset: "sparkles"
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        let window = BrowserWindowState()
        window.currentSpaceId = space.id

        let service = RegularSplitGroupDuplicationService(
            groups: browser.splitGroupStore,
            mutations: browser.splitGroupMutations,
            regularTabs: browser.regularTabCollectionOwner,
            duplication: SplitTabDuplicationService(
                spaces: browser.spaceStateOwner,
                regularTabs: browser.regularTabLifecycleOwner,
                closure: browser.tabClosureService
            )
        )
        XCTAssertTrue(service.duplicate(group, in: window))

        let duplicate = try XCTUnwrap(
            browser.splitGroupStore.groups.first { $0.id != group.id }
        )
        XCTAssertEqual(duplicate.title, "Research (2)")
        XCTAssertEqual(duplicate.iconAsset, "sparkles")
        XCTAssertEqual(duplicate.layoutKind, group.layoutKind)
        XCTAssertEqual(
            browser.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            group.memberIDs.compactMap(\.regularTabID)
                + duplicate.memberIDs.compactMap(\.regularTabID)
        )
        XCTAssertNil(window.splitSelection)
    }

    func testSavedDuplicateCreatesFreshUnloadedLaunchersAndSuffixesName() throws {
        let browser = BrowserManager()
        browser.tabRuntimeLifecycle.shutdown()
        let space = Space(name: "Work")
        browser.spaceStateOwner.replaceSpaces([space])
        let pins = ["one", "two"].enumerated().map { index, name in
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: index,
                launchURL: URL(string: "https://\(name).example")!,
                title: name.capitalized
            )
        }
        for pin in pins {
            XCTAssertNotNil(browser.shortcutPinStoreOwner.insert(
                pin,
                at: pin.index,
                openTargetFolder: false
            ))
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.map { .shortcutPin($0.id) },
            layoutKind: .grid,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            ),
            title: "Workspace",
            iconAsset: "🧭"
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        let service = SavedSplitGroupDuplicationService(
            groups: browser.splitGroupStore,
            mutations: browser.splitGroupMutations,
            pins: browser.shortcutPinCollectionStateOwner,
            pinStore: browser.shortcutPinStoreOwner
        )

        XCTAssertTrue(service.duplicate(group))

        let duplicate = try XCTUnwrap(
            browser.splitGroupStore.groups.first { $0.id != group.id }
        )
        XCTAssertEqual(duplicate.title, "Workspace (2)")
        XCTAssertEqual(duplicate.iconAsset, "🧭")
        XCTAssertEqual(duplicate.layoutKind, .grid)
        XCTAssertEqual(
            browser.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).count,
            4
        )
        for memberID in duplicate.memberIDs {
            let pinID = try XCTUnwrap(memberID.shortcutPinID)
            XCTAssertNil(browser.liveShortcutTabs.tab(for: pinID, in: UUID()))
        }
    }

    func testDuplicateTitleSkipsExistingSuffixes() throws {
        let source = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(UUID()), .regularTab(UUID())],
            layoutKind: .vertical,
            title: "Research"
        ))
        let second = try XCTUnwrap(source.editingMetadata(
            title: "Research (2)",
            iconAsset: nil
        ))

        XCTAssertEqual(
            SplitGroupDuplicateTitleResolver.title(
                copiedFrom: source,
                existingGroups: [source, second]
            ),
            "Research (3)"
        )
    }
}

private extension SplitMemberID {
    var regularTabID: UUID? {
        guard case .regularTab(let id) = self else { return nil }
        return id
    }

    var shortcutPinID: UUID? {
        guard case .shortcutPin(let id) = self else { return nil }
        return id
    }
}
