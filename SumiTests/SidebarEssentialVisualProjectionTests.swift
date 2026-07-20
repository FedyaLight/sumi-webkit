import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarEssentialVisualProjectionTests: XCTestCase {
    func testProjectionCollapsesOrderedMembersIntoOneVisualItem() throws {
        let profileID = UUID()
        let first = pin(index: 0, profileID: profileID)
        let second = pin(index: 1, profileID: profileID)
        let third = pin(index: 2, profileID: profileID)
        let group = try XCTUnwrap(SplitGroup.make(
            members: [first, second].map { .shortcutPin($0.id) },
            layoutKind: .horizontal,
            container: .essentialSidebar(profileId: profileID, index: 0)
        ))

        let projection = SidebarEssentialVisualProjection.make(
            pins: [first, second, third],
            splitGroups: [group],
            profileID: profileID
        )

        XCTAssertEqual(projection.map(\.id), [group.id, third.id])
        guard case .splitGroup(let projectedGroup) = projection.first else {
            return XCTFail("Expected the split group to occupy one visual slot")
        }
        XCTAssertEqual(projectedGroup.memberIDs, group.memberIDs)
    }

    func testProjectionRejectsSplitGroupOwnedByAnotherProfile() throws {
        let profileID = UUID()
        let pins = [pin(index: 0, profileID: profileID), pin(index: 1, profileID: profileID)]
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.map { .shortcutPin($0.id) },
            layoutKind: .horizontal,
            container: .essentialSidebar(profileId: UUID(), index: 0)
        ))

        let projection = SidebarEssentialVisualProjection.make(
            pins: pins,
            splitGroups: [group],
            profileID: profileID
        )

        XCTAssertEqual(projection.map(\.id), pins.map(\.id))
    }

    private func pin(index: Int, profileID: UUID) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: index,
            launchURL: URL(string: "https://\(index).example")!,
            title: "Essential \(index)"
        )
    }
}
