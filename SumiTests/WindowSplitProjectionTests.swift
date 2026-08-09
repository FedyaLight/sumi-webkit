import Foundation
@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class WindowSplitProjectionTests: XCTestCase {
    func testProjectsOneDurableGroupToExactWindowLocalShortcutTabs() throws {
        let firstPinID = UUID()
        let secondPinID = UUID()
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let firstWindowTabIDs = [UUID(), UUID()]
        let secondWindowTabIDs = [UUID(), UUID()]
        let group = try XCTUnwrap(makeGroup(
            firstPinID: firstPinID,
            secondPinID: secondPinID
        ))
        let projection = makeProjection(
            group: group,
            regularTabIDs: [],
            pinIDs: [firstPinID, secondPinID],
            liveTabIDs: [
                Slot(windowID: firstWindowID, pinID: firstPinID): firstWindowTabIDs[0],
                Slot(windowID: firstWindowID, pinID: secondPinID): firstWindowTabIDs[1],
                Slot(windowID: secondWindowID, pinID: firstPinID): secondWindowTabIDs[0],
                Slot(windowID: secondWindowID, pinID: secondPinID): secondWindowTabIDs[1],
            ]
        )

        let first = try readyPresentation(projection.resolve(
            selection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(firstPinID)
            ),
            in: firstWindowID
        ))
        let second = try readyPresentation(projection.resolve(
            selection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(secondPinID)
            ),
            in: secondWindowID
        ))

        XCTAssertEqual(first.group, group)
        XCTAssertEqual(second.group, group)
        XCTAssertEqual(first.visibleTabIDs, firstWindowTabIDs)
        XCTAssertEqual(second.visibleTabIDs, secondWindowTabIDs)
        XCTAssertEqual(first.activeTabID, firstWindowTabIDs[0])
        XCTAssertEqual(second.activeTabID, secondWindowTabIDs[1])
        XCTAssertNotEqual(
            first.tabID(for: .shortcutPin(firstPinID)),
            second.tabID(for: .shortcutPin(firstPinID))
        )
        XCTAssertEqual(group.memberIDs, [
            .shortcutPin(firstPinID),
            .shortcutPin(secondPinID),
        ])
    }

    func testMissingWindowLiveTabRequestsMaterializationWithoutMutation() throws {
        let firstPinID = UUID()
        let secondPinID = UUID()
        let group = try XCTUnwrap(makeGroup(
            firstPinID: firstPinID,
            secondPinID: secondPinID
        ))
        var liveLookupCount = 0
        let projection = WindowSplitProjection(
            group: { $0 == group.id ? group : nil },
            regularTabExists: { _ in false },
            shortcutPinExists: { $0 == firstPinID || $0 == secondPinID },
            shortcutLiveTabID: { pinID, _ in
                liveLookupCount += 1
                return pinID == firstPinID ? UUID() : nil
            }
        )
        let selection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .shortcutPin(secondPinID)
        )

        let resolution = projection.resolve(
            selection: selection,
            in: UUID()
        )

        guard case let .needsMaterialization(
            resolvedGroup,
            resolvedSelection,
            shortcutPinIDs
        ) = resolution else {
            return XCTFail("Expected explicit shortcut materialization request")
        }
        XCTAssertEqual(resolvedGroup, group)
        XCTAssertEqual(resolvedSelection, selection)
        XCTAssertEqual(shortcutPinIDs, [secondPinID])
        XCTAssertEqual(liveLookupCount, 2)
        XCTAssertFalse(resolution.hasReadyPresentation)
        XCTAssertEqual(group.memberIDs, [
            .shortcutPin(firstPinID),
            .shortcutPin(secondPinID),
        ])
    }

    func testRejectsMissingDurableMemberBeforePresentation() throws {
        let firstPinID = UUID()
        let secondPinID = UUID()
        let group = try XCTUnwrap(makeGroup(
            firstPinID: firstPinID,
            secondPinID: secondPinID
        ))
        let projection = makeProjection(
            group: group,
            regularTabIDs: [],
            pinIDs: [secondPinID],
            liveTabIDs: [:]
        )

        let resolution = projection.resolve(
            selection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(secondPinID)
            ),
            in: UUID()
        )

        XCTAssertEqual(
            resolution,
            .invalid(
                groupID: group.id,
                reason: .missingMembers([.shortcutPin(firstPinID)])
            )
        )
        XCTAssertFalse(resolution.hasReadyPresentation)
    }

    func testRejectsSelectionFromAnotherGroup() throws {
        let firstPinID = UUID()
        let secondPinID = UUID()
        let staleMemberID = SplitMemberID.shortcutPin(UUID())
        let group = try XCTUnwrap(makeGroup(
            firstPinID: firstPinID,
            secondPinID: secondPinID
        ))
        let projection = makeProjection(
            group: group,
            regularTabIDs: [],
            pinIDs: [firstPinID, secondPinID],
            liveTabIDs: [:]
        )

        XCTAssertEqual(
            projection.resolve(
                selection: WindowSplitSelection(
                    groupID: group.id,
                    activeMemberID: staleMemberID
                ),
                in: UUID()
            ),
            .invalid(
                groupID: group.id,
                reason: .selectedMemberNotInGroup(staleMemberID)
            )
        )
    }

    func testRejectsTwoMembersMappedToTheSameLiveTab() throws {
        let firstPinID = UUID()
        let secondPinID = UUID()
        let windowID = UUID()
        let sharedLiveTabID = UUID()
        let group = try XCTUnwrap(makeGroup(
            firstPinID: firstPinID,
            secondPinID: secondPinID
        ))
        let projection = makeProjection(
            group: group,
            regularTabIDs: [],
            pinIDs: [firstPinID, secondPinID],
            liveTabIDs: [
                Slot(windowID: windowID, pinID: firstPinID): sharedLiveTabID,
                Slot(windowID: windowID, pinID: secondPinID): sharedLiveTabID,
            ]
        )

        XCTAssertEqual(
            projection.resolve(
                selection: WindowSplitSelection(
                    groupID: group.id,
                    activeMemberID: .shortcutPin(firstPinID)
                ),
                in: windowID
            ),
            .invalid(
                groupID: group.id,
                reason: .duplicateLiveTabIDs
            )
        )
    }

    func testInactiveWindowDoesNotReadAnyRuntimeCatalog() {
        var readCount = 0
        let projection = WindowSplitProjection(
            group: { _ in readCount += 1; return nil },
            regularTabExists: { _ in readCount += 1; return false },
            shortcutPinExists: { _ in readCount += 1; return false },
            shortcutLiveTabID: { _, _ in readCount += 1; return nil }
        )

        XCTAssertEqual(
            projection.resolve(selection: nil, in: UUID()),
            .inactive
        )
        XCTAssertEqual(readCount, 0)
    }

    func testWebsiteViewContextDoesNotRetainBrowserKernel() async throws {
        var browserManager: BrowserManager? = BrowserManager()
        weak let releasedBrowserManager = browserManager
        let context = try {
            let manager = try XCTUnwrap(browserManager)
            let shell = manager.shellRuntime
            return WebsiteViewContextFactory.websiteViewBrowserContext(
                windowTabs: shell.windowTabs,
                membership: manager.tabCollectionMembershipOwner,
                windowVisuals: shell.windowVisuals,
                repairFailure: { _, _, _ in },
                spaces: manager.spaceStateOwner,
                dragOperations: manager.sidebarDragRouter
            )
        }()

        browserManager = nil
        for _ in 0..<20 where releasedBrowserManager != nil {
            await Task.yield()
        }

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(context.currentTab(BrowserWindowState()))
        withExtendedLifetime(context) {}
    }

    private struct Slot: Hashable {
        let windowID: UUID
        let pinID: UUID
    }

    private func makeGroup(
        firstPinID: UUID,
        secondPinID: UUID
    ) -> SumiDomain.SplitGroup? {
        SumiDomain.SplitGroup.make(
            members: [
                .shortcutPin(firstPinID),
                .shortcutPin(secondPinID),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: UUID(),
                profileId: nil,
                folderId: nil,
                index: 0
            )
        )
    }

    private func makeProjection(
        group: SumiDomain.SplitGroup,
        regularTabIDs: Set<UUID>,
        pinIDs: Set<UUID>,
        liveTabIDs: [Slot: UUID]
    ) -> WindowSplitProjection {
        WindowSplitProjection(
            group: { $0 == group.id ? group : nil },
            regularTabExists: regularTabIDs.contains,
            shortcutPinExists: pinIDs.contains,
            shortcutLiveTabID: { pinID, windowID in
                liveTabIDs[Slot(windowID: windowID, pinID: pinID)]
            }
        )
    }

    private func readyPresentation(
        _ resolution: WindowSplitResolution
    ) throws -> WindowSplitPresentation {
        guard case .ready(let presentation) = resolution else {
            throw ProjectionTestError.expectedReadyPresentation
        }
        return presentation
    }

    private enum ProjectionTestError: Error {
        case expectedReadyPresentation
    }
}
