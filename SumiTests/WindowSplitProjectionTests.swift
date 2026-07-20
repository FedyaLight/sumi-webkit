import Foundation
@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class WindowSplitProjectionTests: XCTestCase {
    func testProjectsOneDurableGroupToExactWindowLocalShortcutTabs() throws {
        let regularTabID = UUID()
        let pinID = UUID()
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let firstShortcutTabID = UUID()
        let secondShortcutTabID = UUID()
        let group = try XCTUnwrap(makeGroup(
            regularTabID: regularTabID,
            pinID: pinID
        ))
        let projection = makeProjection(
            group: group,
            regularTabIDs: [regularTabID],
            pinIDs: [pinID],
            liveTabIDs: [
                Slot(windowID: firstWindowID, pinID: pinID): firstShortcutTabID,
                Slot(windowID: secondWindowID, pinID: pinID): secondShortcutTabID,
            ]
        )

        let first = try readyPresentation(projection.resolve(
            selection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(regularTabID)
            ),
            in: firstWindowID
        ))
        let second = try readyPresentation(projection.resolve(
            selection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(pinID)
            ),
            in: secondWindowID
        ))

        XCTAssertEqual(first.group, group)
        XCTAssertEqual(second.group, group)
        XCTAssertEqual(first.visibleTabIDs, [regularTabID, firstShortcutTabID])
        XCTAssertEqual(second.visibleTabIDs, [regularTabID, secondShortcutTabID])
        XCTAssertEqual(first.activeTabID, regularTabID)
        XCTAssertEqual(second.activeTabID, secondShortcutTabID)
        XCTAssertNotEqual(
            first.tabID(for: .shortcutPin(pinID)),
            second.tabID(for: .shortcutPin(pinID))
        )
        XCTAssertEqual(group.memberIDs, [
            .regularTab(regularTabID),
            .shortcutPin(pinID),
        ])
    }

    func testMissingWindowLiveTabRequestsMaterializationWithoutMutation() throws {
        let regularTabID = UUID()
        let pinID = UUID()
        let group = try XCTUnwrap(makeGroup(
            regularTabID: regularTabID,
            pinID: pinID
        ))
        var liveLookupCount = 0
        let projection = WindowSplitProjection(
            group: { $0 == group.id ? group : nil },
            regularTabExists: { $0 == regularTabID },
            shortcutPinExists: { $0 == pinID },
            shortcutLiveTabID: { _, _ in
                liveLookupCount += 1
                return nil
            }
        )
        let selection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .shortcutPin(pinID)
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
        XCTAssertEqual(shortcutPinIDs, [pinID])
        XCTAssertEqual(liveLookupCount, 1)
        XCTAssertFalse(resolution.hasReadyPresentation)
        XCTAssertEqual(group.memberIDs, [
            .regularTab(regularTabID),
            .shortcutPin(pinID),
        ])
    }

    func testRejectsMissingDurableMemberBeforePresentation() throws {
        let regularTabID = UUID()
        let pinID = UUID()
        let group = try XCTUnwrap(makeGroup(
            regularTabID: regularTabID,
            pinID: pinID
        ))
        let projection = makeProjection(
            group: group,
            regularTabIDs: [],
            pinIDs: [pinID],
            liveTabIDs: [:]
        )

        let resolution = projection.resolve(
            selection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(regularTabID)
            ),
            in: UUID()
        )

        XCTAssertEqual(
            resolution,
            .invalid(
                groupID: group.id,
                reason: .missingMembers([.regularTab(regularTabID)])
            )
        )
        XCTAssertFalse(resolution.hasReadyPresentation)
    }

    func testRejectsSelectionFromAnotherGroup() throws {
        let regularTabID = UUID()
        let pinID = UUID()
        let staleMemberID = SplitMemberID.regularTab(UUID())
        let group = try XCTUnwrap(makeGroup(
            regularTabID: regularTabID,
            pinID: pinID
        ))
        let projection = makeProjection(
            group: group,
            regularTabIDs: [regularTabID],
            pinIDs: [pinID],
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
        let regularTabID = UUID()
        let pinID = UUID()
        let windowID = UUID()
        let group = try XCTUnwrap(makeGroup(
            regularTabID: regularTabID,
            pinID: pinID
        ))
        let projection = makeProjection(
            group: group,
            regularTabIDs: [regularTabID],
            pinIDs: [pinID],
            liveTabIDs: [
                Slot(windowID: windowID, pinID: pinID): regularTabID,
            ]
        )

        XCTAssertEqual(
            projection.resolve(
                selection: WindowSplitSelection(
                    groupID: group.id,
                    activeMemberID: .shortcutPin(pinID)
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
        regularTabID: UUID,
        pinID: UUID
    ) -> SumiDomain.SplitGroup? {
        SumiDomain.SplitGroup.make(
            members: [
                .regularTab(regularTabID),
                .shortcutPin(pinID),
            ],
            layoutKind: .vertical
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
