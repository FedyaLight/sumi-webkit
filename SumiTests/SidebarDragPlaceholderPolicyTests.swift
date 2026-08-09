//
//  SidebarDragPlaceholderPolicyTests.swift
//  SumiTests
//

import XCTest

@testable import Sumi

final class SidebarDragPlaceholderPolicyTests: XCTestCase {
    private let spaceId = UUID()
    private let folderId = UUID()

    // MARK: - shouldHideCommittedCrossContainerPlaceholder

    func testHideCommittedPlaceholderFalseWhenNotCompletingDrop() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                isCompletingDrop: false,
                sourceContainer: .spaceRegular(spaceId),
                targetContainer: .favorite,
                targetAlreadyContainsDraggedItem: true
            )
        )
    }

    func testHideCommittedPlaceholderFalseWithoutSourceContainer() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                isCompletingDrop: true,
                sourceContainer: nil,
                targetContainer: .favorite,
                targetAlreadyContainsDraggedItem: true
            )
        )
    }

    func testHideCommittedPlaceholderTrueWhenRegularTabGainsLauncherIdentity() {
        // spaceRegular -> favorite/spacePinned/folder: gains a shortcut identity.
        for target: TabDragManager.DragContainer in [.favorite, .spacePinned(spaceId), .folder(folderId)] {
            XCTAssertTrue(
                SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                    isCompletingDrop: true,
                    sourceContainer: .spaceRegular(spaceId),
                    targetContainer: target,
                    targetAlreadyContainsDraggedItem: false
                ),
                "expected true for target \(target)"
            )
        }
    }

    func testHideCommittedPlaceholderFalseWhenRegularTabStaysRegular() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                isCompletingDrop: true,
                sourceContainer: .spaceRegular(spaceId),
                targetContainer: .spaceRegular(spaceId),
                targetAlreadyContainsDraggedItem: false
            )
        )
    }

    func testHideCommittedPlaceholderFallsBackToContainerMismatchWhenTargetAlreadyContainsItem() {
        // Source is not spaceRegular (no launcher-identity change), but the
        // fallback rule still applies: different containers + already present.
        XCTAssertTrue(
            SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                isCompletingDrop: true,
                sourceContainer: .favorite,
                targetContainer: .spacePinned(spaceId),
                targetAlreadyContainsDraggedItem: true
            )
        )
    }

    func testHideCommittedPlaceholderFalseWhenSameContainerEvenIfAlreadyContainsItem() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                isCompletingDrop: true,
                sourceContainer: .favorite,
                targetContainer: .favorite,
                targetAlreadyContainsDraggedItem: true
            )
        )
    }

    func testHideCommittedPlaceholderFalseWhenNotAlreadyContainedAndNoIdentityChange() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                isCompletingDrop: true,
                sourceContainer: .favorite,
                targetContainer: .spacePinned(spaceId),
                targetAlreadyContainsDraggedItem: false
            )
        )
    }
}
