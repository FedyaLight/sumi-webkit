import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SplitGroupMembershipQueryTests: XCTestCase {
    func testRegularAndShortcutRuntimeTabsResolveToDifferentDurableKinds() {
        let regular = Tab(url: URL(string: "https://regular.example")!)
        let shortcut = Tab(url: URL(string: "https://shortcut.example")!)
        let pinID = UUID()
        shortcut.shortcutPinId = pinID
        let query = makeQuery(store: SplitGroupStore())

        XCTAssertEqual(query.memberID(for: regular), .regularTab(regular.id))
        XCTAssertEqual(query.memberID(for: shortcut), .shortcutPin(pinID))
    }

    func testRuntimeShortcutTabFindsGroupByStablePinIdentity() throws {
        let regular = Tab(url: URL(string: "https://regular.example")!)
        let shortcut = Tab(url: URL(string: "https://shortcut.example")!)
        let pinID = UUID()
        let siblingPinID = UUID()
        shortcut.shortcutPinId = pinID
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .shortcutPin(pinID),
                    .shortcutPin(siblingPinID),
                ],
                layoutKind: .vertical,
                container: .shortcutSidebar(
                    spaceId: UUID(),
                    profileId: nil,
                    folderId: nil,
                    index: 0
                )
            )
        )
        let store = SplitGroupStore()
        store.replaceAll(with: [group])
        let query = makeQuery(
            store: store,
            tabs: [regular, shortcut],
            pins: [makePin(id: pinID), makePin(id: siblingPinID)]
        )

        XCTAssertNil(query.group(containing: regular))
        XCTAssertEqual(query.group(containing: shortcut), group)
        XCTAssertEqual(query.group(forLookupID: shortcut.id), group)
        XCTAssertEqual(query.group(forLookupID: pinID), group)
        XCTAssertFalse(group.contains(.regularTab(regular.id)))
    }

    func testRawLookupPrioritizesDurablePinWhenUUIDExistsInBothCatalogs() {
        let sharedID = UUID()
        let tab = Tab(
            id: sharedID,
            url: URL(string: "https://regular.example")!
        )
        let query = makeQuery(
            store: SplitGroupStore(),
            tabs: [tab],
            pins: [makePin(id: sharedID)]
        )

        XCTAssertEqual(
            query.memberID(forLookupID: sharedID),
            .shortcutPin(sharedID)
        )
    }

    func testRawLookupDoesNotInventIdentityForUnknownUUID() {
        let query = makeQuery(store: SplitGroupStore())

        XCTAssertNil(query.memberID(forLookupID: UUID()))
        XCTAssertNil(query.group(forLookupID: UUID()))
    }

    func testTypedStoreNeverConflatesEqualTabAndPinUUIDs() throws {
        let sharedID = UUID()
        let regularGroup = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(sharedID), .regularTab(UUID())],
                layoutKind: .vertical
            )
        )
        let shortcutGroup = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .shortcutPin(sharedID),
                    .shortcutPin(UUID()),
                ],
                layoutKind: .horizontal,
                container: .shortcutSidebar(
                    spaceId: UUID(),
                    profileId: nil,
                    folderId: nil,
                    index: 0
                )
            )
        )
        let store = SplitGroupStore()
        store.replaceAll(with: [regularGroup, shortcutGroup])

        XCTAssertEqual(
            store.group(containing: .regularTab(sharedID)),
            regularGroup
        )
        XCTAssertEqual(
            store.group(containing: .shortcutPin(sharedID)),
            shortcutGroup
        )
    }

    private func makeQuery(
        store: SplitGroupStore,
        tabs: [Tab] = [],
        pins: [ShortcutPin] = []
    ) -> SplitGroupMembershipQuery {
        let state = TabStateStore()
        let spaceID = UUID()
        state.regularTabs.replaceTabsBySpace(
            [spaceID: tabs],
            publish: false
        )
        state.shortcutPins.replacePinnedByProfile([UUID(): pins])
        let runtimeConnection = TabRuntimePortConnection()
        let membership = TabCollectionMembershipOwner(
            structuralLookupOwner: TabStructuralLookupOwner(),
            state: state,
            runtimePreparation: TabRuntimePreparationOwner(
                runtimeConnection: runtimeConnection
            ),
            runtimeConnection: runtimeConnection
        )
        return SplitGroupMembershipQuery(
            store: store,
            tabs: membership,
            pins: state.shortcutPins
        )
    }

    private func makePin(id: UUID) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: .essential,
            profileId: UUID(),
            index: 0,
            launchURL: URL(string: "https://pin.example")!,
            title: "Pin"
        )
    }
}
