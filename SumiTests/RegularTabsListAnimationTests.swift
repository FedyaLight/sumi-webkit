import XCTest

@testable import Sumi

final class RegularTabsListAnimationTests: XCTestCase {
    func testThreeMemberSplitDepartureCannotBecomeStandaloneRows() {
        let memberIDs = [UUID(), UUID(), UUID()]
        let groupID = UUID()
        let oldRun = SidebarVisualSceneProjection.RegularRun(
            rows: [
                .init(
                    identity: .splitGroup(groupID),
                    tabIDs: memberIDs
                ),
            ]
        )

        XCTAssertEqual(
            RegularSidebarVisualChange.resolve(
                from: oldRun,
                to: .init(rows: [])
            ),
            .immediateReplacement
        )
    }

    func testOneTabClosureKeepsTheOrdinaryRemovalAnimation() {
        let firstID = UUID()
        let secondID = UUID()
        let oldRun = SidebarVisualSceneProjection.RegularRun(
            rows: [
                .init(identity: .tab(firstID), tabIDs: [firstID]),
                .init(identity: .tab(secondID), tabIDs: [secondID]),
            ]
        )
        let newRun = SidebarVisualSceneProjection.RegularRun(
            rows: [
                .init(identity: .tab(secondID), tabIDs: [secondID]),
            ]
        )

        XCTAssertEqual(
            RegularSidebarVisualChange.resolve(
                from: oldRun,
                to: newRun
            ),
            .removal(firstID)
        )
    }

    func testSplitDissolutionIsOneImmediateVisualReplacement() {
        let memberIDs = [UUID(), UUID()]
        let groupID = UUID()
        let oldRun = SidebarVisualSceneProjection.RegularRun(
            rows: [
                .init(
                    identity: .splitGroup(groupID),
                    tabIDs: memberIDs
                ),
            ]
        )
        let newRun = SidebarVisualSceneProjection.RegularRun(
            rows: [
                .init(identity: .tab(memberIDs[1]), tabIDs: [memberIDs[1]]),
            ]
        )

        XCTAssertEqual(
            RegularSidebarVisualChange.resolve(
                from: oldRun,
                to: newRun
            ),
            .immediateReplacement
        )
    }
}
