import Foundation
import SumiDomain
import XCTest

final class SplitDomainCodingTests: XCTestCase {
    private let regularID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let pinID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let spaceID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let folderID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let profileID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

    func testMemberIDDecodesStableTaggedFixture() throws {
        let regularData = Data(
            #"{"kind":"regularTab","id":"11111111-1111-1111-1111-111111111111"}"#.utf8
        )
        let pinData = Data(
            #"{"kind":"shortcutPin","id":"22222222-2222-2222-2222-222222222222"}"#.utf8
        )

        XCTAssertEqual(
            try JSONDecoder().decode(SplitMemberID.self, from: regularData),
            .regularTab(regularID)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(SplitMemberID.self, from: pinData),
            .shortcutPin(pinID)
        )
    }

    func testTreeEncodingUsesExplicitCaseAndWeightKeys() throws {
        let tree = SplitLayoutTree.split(
            axis: .row,
            weight: 1,
            children: [
                .leaf(member: .regularTab(regularID), weight: 0.25),
                .leaf(member: .shortcutPin(pinID), weight: 0.75),
            ]
        )
        let data = try JSONEncoder().encode(tree)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["kind"] as? String, "split")
        XCTAssertEqual(object["axis"] as? String, "row")
        XCTAssertEqual(object["weight"] as? Double, 1)
        let children = try XCTUnwrap(object["children"] as? [[String: Any]])
        XCTAssertEqual(children.map { $0["kind"] as? String }, ["leaf", "leaf"])
        XCTAssertEqual(
            try JSONDecoder().decode(SplitLayoutTree.self, from: data),
            tree
        )
    }

    func testGroupRoundTripPreservesExplicitSidebarFolderPlacement() throws {
        let firstPin = SplitMember.shortcutPin(pinID)
        let secondPin = SplitMember.shortcutPin(
            UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        )
        let group = try XCTUnwrap(
            SplitGroup.make(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                members: [firstPin, secondPin],
                layoutKind: .vertical,
                container: .shortcutSidebar(
                    spaceId: spaceID,
                    profileId: profileID,
                    folderId: folderID,
                    index: 4
                ),
                title: "Research",
                iconAsset: "emoji:🧭"
            )
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(SplitGroup.self, from: data)

        XCTAssertEqual(decoded, group)
        XCTAssertEqual(decoded.container.shortcutSidebarFolderId, folderID)
        XCTAssertEqual(decoded.container.shortcutSidebarIndex, 4)
        XCTAssertEqual(decoded.container.spaceId, spaceID)
        XCTAssertEqual(decoded.title, "Research")
        XCTAssertEqual(decoded.iconAsset, "emoji:🧭")
    }

    func testLegacyGroupWithoutMetadataDecodesWithNilMetadata() throws {
        let group = try XCTUnwrap(SplitGroup.make(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            members: [
                .regularTab(regularID),
                .regularTab(UUID()),
            ],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: spaceID)
        ))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(group)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "title")
        object.removeValue(forKey: "iconAsset")

        let decoded = try JSONDecoder().decode(
            SplitGroup.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.iconAsset)
    }
}
