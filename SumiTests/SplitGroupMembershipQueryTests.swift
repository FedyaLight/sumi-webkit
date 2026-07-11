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
        let query = SplitGroupMembershipQuery(
            store: SplitGroupStore(),
            tab: { _ in nil },
            shortcutPinExists: { _ in false }
        )

        XCTAssertEqual(query.memberID(for: regular), .regularTab(regular.id))
        XCTAssertEqual(query.memberID(for: shortcut), .shortcutPin(pinID))
    }

    func testRuntimeShortcutTabFindsGroupByStablePinIdentity() throws {
        let regular = Tab(url: URL(string: "https://regular.example")!)
        let shortcut = Tab(url: URL(string: "https://shortcut.example")!)
        let pinID = UUID()
        shortcut.shortcutPinId = pinID
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(regular.id),
                    .shortcutPin(
                        pinID,
                        returnPlacement: .spacePinned(
                            spaceId: UUID(),
                            folderId: nil,
                            index: 3
                        )
                    ),
                ],
                layoutKind: .vertical
            )
        )
        let store = SplitGroupStore()
        store.replaceAll(with: [group])
        let query = SplitGroupMembershipQuery(
            store: store,
            tab: { id in
                [regular, shortcut].first { $0.id == id }
            },
            shortcutPinExists: { $0 == pinID }
        )

        XCTAssertEqual(query.group(containing: regular), group)
        XCTAssertEqual(query.group(containing: shortcut), group)
        XCTAssertEqual(query.group(forLookupID: shortcut.id), group)
        XCTAssertEqual(query.group(forLookupID: pinID), group)
        XCTAssertFalse(group.contains(.regularTab(shortcut.id)))
    }

    func testRawLookupPrioritizesDurablePinWhenUUIDExistsInBothCatalogs() {
        let sharedID = UUID()
        let tab = Tab(
            id: sharedID,
            url: URL(string: "https://regular.example")!
        )
        let query = SplitGroupMembershipQuery(
            store: SplitGroupStore(),
            tab: { $0 == sharedID ? tab : nil },
            shortcutPinExists: { $0 == sharedID }
        )

        XCTAssertEqual(
            query.memberID(forLookupID: sharedID),
            .shortcutPin(sharedID)
        )
    }

    func testRawLookupDoesNotInventIdentityForUnknownUUID() {
        let query = SplitGroupMembershipQuery(
            store: SplitGroupStore(),
            tab: { _ in nil },
            shortcutPinExists: { _ in false }
        )

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
                    .shortcutPin(
                        sharedID,
                        returnPlacement: .essential(
                            profileId: nil,
                            index: 0
                        )
                    ),
                    .shortcutPin(
                        UUID(),
                        returnPlacement: .essential(
                            profileId: nil,
                            index: 1
                        )
                    ),
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
}
