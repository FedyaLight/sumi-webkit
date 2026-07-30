import Combine
import SumiDomain
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
extension ShortcutPinAtomicityTests {
    func testPublicConversionCommitsCrossWindowSelectionAtomically() throws {
        let fixture = try makeCrossWindowConversionFixture()
        XCTAssertTrue(fixture.regularTabs.contains(fixture.input.tab))
        XCTAssertFalse(fixture.input.tab.isShortcutLiveInstance)
        XCTAssertFalse(
            fixture.input.tab.profileAssignment.hasUnsettledAssignment
        )
        let preparation = fixture.conversion.prepare(
            fixture.input.tab,
            preferredWindowId: fixture.input.selectedWindowID
        )
        switch preparation {
        case .displayed:
            break
        case .detached:
            return XCTFail("Cross-window selection was not visible to runtime")
        case .rejected:
            return XCTFail("Cross-window conversion structure was rejected")
        }

        let converted = fixture.conversion.commit(
            fixture.input.tab,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: fixture.input.space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )?.canonicalPin

        let pin = try XCTUnwrap(converted)
        XCTAssertFalse(fixture.regularTabs.contains(fixture.input.tab))
        XCTAssertTrue(fixture.input.tab.isShortcutLiveInstance)
        XCTAssertIdentical(
            fixture.liveTabs.tab(
                for: pin.id,
                in: fixture.input.selectedWindowID
            ),
            fixture.input.tab
        )
        XCTAssertNotNil(
            fixture.liveTabs.tab(
                for: pin.id,
                in: fixture.input.secondaryWindowID
            )
        )
        XCTAssertNotNil(fixture.pins.shortcutPin(by: pin.id))
    }

    func testPublicConversionRejectsMixedSelectedSplitWithoutMutation() throws {
        let fixture = try makeSelectedSplitConversionFixture()
        let input = fixture.input
        let group = input.group
        var structuralEvents = 0
        let cancellable = fixture.events
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let preparation = fixture.conversion.prepare(
            input.tab,
            preferredWindowId: input.window.id
        )
        guard case .displayed = preparation else {
            return XCTFail("Expected a displayed selected-split conversion plan")
        }

        let converted = fixture.conversion.commit(
            input.tab,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: input.space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )?.canonicalPin

        XCTAssertNil(converted)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(fixture.state().regularTabs.contains(input.tab))
        XCTAssertNil(fixture.state().liveTabs.entry(tabId: input.tab.id))
        XCTAssertEqual(fixture.state().groups.group(id: group.id), group)
        _ = cancellable
    }

    func testStaleSplitPlanRejectsBeforePinInsertionOrFolderOpening() throws {
        let fixture = try makeStaleSplitPlanFixture()
        let input = fixture.input
        let preparation = fixture.conversion
            .prepare(
                input.tab,
                preferredWindowId: input.window.id
            )
        guard case .displayed = preparation else {
            return XCTFail("Expected a valid single-window split plan")
        }
        let changedGroup = try XCTUnwrap(
            input.group.changingLayout(to: .horizontal)
        )
        var structuralEvents = 0
        let cancellable = fixture.events
            .structureChangedPublisher.sink { structuralEvents += 1 }
        XCTAssertTrue(fixture.splitMutations.replace(
            input.group,
            with: changedGroup,
            persist: false
        ))
        structuralEvents = 0
        let windowSession = ShortcutConversionWindowSessionState(input.window)

        let converted = fixture.conversion
            .commit(
                input.tab,
                preparation: preparation,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: input.space.id,
                    folderId: input.folder.id,
                    index: 0,
                    opensFolder: true
                )
            )

        XCTAssertNil(converted)
        XCTAssertFalse(input.folder.isOpen)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(fixture.state().persistedWindowIDs.isEmpty)
        XCTAssertTrue(fixture.state().regularTabs.contains(input.tab))
        XCTAssertFalse(input.tab.isShortcutLiveInstance)
        XCTAssertTrue(
            fixture.state().pins.spacePinnedPins(for: input.space.id).isEmpty
        )
        XCTAssertEqual(
            fixture.state().groups.group(id: input.group.id),
            changedGroup
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(input.window),
            windowSession
        )
        _ = cancellable
    }

    func testHeadlessConversionRejectsMixedSplitWithoutMutation() throws {
        let fixture = try makeHeadlessSplitConversionFixture()
        let converted = fixture.conversion.convert(
            fixture.input.tab,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: fixture.input.space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )

        XCTAssertNil(converted)
        XCTAssertTrue(fixture.input.tab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertTrue(fixture.state().regularTabs.contains(fixture.input.tab))
        XCTAssertTrue(
            fixture.state().pins.spacePinnedPins(for: fixture.input.space.id)
                .isEmpty
        )
        XCTAssertEqual(
            fixture.state().groups.group(id: fixture.input.group.id),
            fixture.input.group
        )
    }

    func testPublicConversionRepairsNonDisplayingWindowAfterCommit() throws {
        let fixture = try makeWindowRepairFixture()
        let cancellable = fixture.events.structureChangedPublisher.sink {
            fixture.oracle.structuralEvents += 1
        }
        fixture.oracle.structuralEvents = 0

        let preparation = fixture.prepare()
        guard case .displayed = preparation else {
            return XCTFail("Expected a displayed window-repair conversion plan")
        }
        let pin = fixture.commit(preparation)

        XCTAssertNotNil(pin)
        XCTAssertEqual(fixture.oracle.structuralEvents, 1)
        XCTAssertEqual(
            fixture.input.stale.activeTabForSpace[fixture.input.space.id],
            fixture.input.fallback.id
        )
        XCTAssertEqual(
            fixture.input.stale.selectionHistory
                .recentRegularTabIdsBySpace[fixture.input.space.id]?
                .contains(fixture.input.tab.id),
            false
        )
        let persisted = try XCTUnwrap(fixture.persistedStaleSnapshot())
        XCTAssertEqual(
            persisted.activeTabsBySpace.first {
                $0.spaceId == fixture.input.space.id
            }?.tabId,
            fixture.input.fallback.id
        )
        _ = cancellable
    }

}
