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
                targetContainer: .essentials,
                targetAlreadyContainsDraggedItem: true
            )
        )
    }

    func testHideCommittedPlaceholderFalseWithoutSourceContainer() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                isCompletingDrop: true,
                sourceContainer: nil,
                targetContainer: .essentials,
                targetAlreadyContainsDraggedItem: true
            )
        )
    }

    func testHideCommittedPlaceholderTrueWhenRegularTabGainsLauncherIdentity() {
        // spaceRegular -> essentials/spacePinned/folder: gains a shortcut identity.
        for target: TabDragManager.DragContainer in [.essentials, .spacePinned(spaceId), .folder(folderId)] {
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
                sourceContainer: .essentials,
                targetContainer: .spacePinned(spaceId),
                targetAlreadyContainsDraggedItem: true
            )
        )
    }

    func testHideCommittedPlaceholderFalseWhenSameContainerEvenIfAlreadyContainsItem() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                isCompletingDrop: true,
                sourceContainer: .essentials,
                targetContainer: .essentials,
                targetAlreadyContainsDraggedItem: true
            )
        )
    }

    func testHideCommittedPlaceholderFalseWhenNotAlreadyContainedAndNoIdentityChange() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
                isCompletingDrop: true,
                sourceContainer: .essentials,
                targetContainer: .spacePinned(spaceId),
                targetAlreadyContainsDraggedItem: false
            )
        )
    }

    // MARK: - shouldSuppressCommitGapForExternalSource

    func testSuppressCommitGapFalseWhenNotCompletingDrop() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldSuppressCommitGapForExternalSource(
                isCompletingDrop: false,
                sourceContainer: .essentials,
                targetContainer: .spaceRegular(spaceId)
            )
        )
    }

    func testSuppressCommitGapFalseWithoutSourceContainer() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldSuppressCommitGapForExternalSource(
                isCompletingDrop: true,
                sourceContainer: nil,
                targetContainer: .spaceRegular(spaceId)
            )
        )
    }

    func testSuppressCommitGapFalseWhenSourceMatchesTarget() {
        XCTAssertFalse(
            SidebarDragPlaceholderPolicy.shouldSuppressCommitGapForExternalSource(
                isCompletingDrop: true,
                sourceContainer: .spaceRegular(spaceId),
                targetContainer: .spaceRegular(spaceId)
            )
        )
    }

    func testSuppressCommitGapTrueWhenShortcutHostedSourceDropsIntoRegular() {
        for source: TabDragManager.DragContainer in [.essentials, .spacePinned(spaceId), .folder(folderId)] {
            XCTAssertTrue(
                SidebarDragPlaceholderPolicy.shouldSuppressCommitGapForExternalSource(
                    isCompletingDrop: true,
                    sourceContainer: source,
                    targetContainer: .spaceRegular(spaceId)
                ),
                "expected true for source \(source)"
            )
        }
    }

    func testSuppressCommitGapFalseWhenSourceIsRegularOrNone() {
        for source: TabDragManager.DragContainer in [.spaceRegular(UUID()), .none] {
            XCTAssertFalse(
                SidebarDragPlaceholderPolicy.shouldSuppressCommitGapForExternalSource(
                    isCompletingDrop: true,
                    sourceContainer: source,
                    targetContainer: .spaceRegular(spaceId)
                ),
                "expected false for source \(source)"
            )
        }
    }
}
