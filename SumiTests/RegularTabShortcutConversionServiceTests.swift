import Combine
import XCTest

@testable import Sumi

@MainActor
final class RegularTabShortcutConversionServiceTests: XCTestCase {
    func testPrimarySelectedWindowKeepsOriginalAndSecondaryMaterializesAfterCommit() throws {
        let primary = BrowserWindowState()
        let secondary = BrowserWindowState()
        let states = [primary.id: primary, secondary.id: secondary]
        var structuralEvents = 0
        var eventsSeenAtMaterialization: [Int] = []
        var materialized: [(UUID, UUID)] = []
        var cancellable: AnyCancellable?
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { tabId in
                primary.currentTabId == tabId ? primary.id : nil
            },
            materializeVisibleTabWebViewIfNeeded: { tab, window in
                eventsSeenAtMaterialization.append(structuralEvents)
                materialized.append((tab.id, window.id))
            }
        )
        primary.tabManager = tabManager
        secondary.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://convert.example",
            in: space,
            activate: false
        )
        primary.currentSpaceId = space.id
        secondary.currentSpaceId = space.id
        primary.currentTabId = tab.id
        secondary.currentTabId = tab.id
        cancellable = tabManager.tabStructureEventBus.structureChangedPublisher
            .sink { structuralEvents += 1 }
        structuralEvents = 0

        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: secondary.id
            )
        )

        let secondaryTab = try XCTUnwrap(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: secondary.id)
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: primary.id),
            tab
        )
        XCTAssertNotEqual(secondaryTab.id, tab.id)
        XCTAssertEqual(primary.currentTabId, tab.id)
        XCTAssertEqual(secondary.currentTabId, secondaryTab.id)
        XCTAssertEqual(materialized.map(\.0), [secondaryTab.id])
        XCTAssertEqual(materialized.map(\.1), [secondary.id])
        XCTAssertEqual(eventsSeenAtMaterialization, [1])
        XCTAssertEqual(structuralEvents, 1)
        _ = cancellable
    }

    func testSplitVisibleInAnotherWindowRejectsConversionWithoutPartialMutation() throws {
        let selected = BrowserWindowState()
        let splitOnly = BrowserWindowState()
        let states = [selected.id: selected, splitOnly.id: splitOnly]
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            visibleSplitTabIds: { windowId in
                windowId == splitOnly.id ? [selected.currentTabId].compactMap(\.self) : []
            }
        )
        selected.tabManager = tabManager
        splitOnly.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let original = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split.example/original",
            in: space,
            activate: false
        )
        let fallback = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split.example/fallback",
            in: space,
            activate: false
        )
        selected.currentSpaceId = space.id
        selected.currentTabId = original.id
        splitOnly.currentSpaceId = space.id
        splitOnly.currentTabId = fallback.id
        splitOnly.activeTabForSpace[space.id] = original.id
        splitOnly.selectionHistory.recordRegularTabSelection(
            original.id,
            in: space.id
        )
        XCTAssertNil(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                original,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0,
                preferredWindowId: selected.id
            )
        )

        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(original))
        XCTAssertFalse(original.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
        XCTAssertEqual(splitOnly.currentTabId, fallback.id)
        XCTAssertEqual(splitOnly.activeTabForSpace[space.id], original.id)
        XCTAssertEqual(
            splitOnly.selectionHistory.recentRegularTabIdsBySpace[space.id]?
                .contains(original.id),
            true
        )
    }

    func testPrimaryLeaseChangeRejectsPreparedConversionWithoutMutation() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let states = [first.id: first, second.id: second]
        var primaryWindowId: UUID?
        var persistedWindowIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { _ in primaryWindowId },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        first.tabManager = tabManager
        second.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://primary-lease.example",
            in: space,
            activate: false
        )
        for window in [first, second] {
            window.currentSpaceId = space.id
            window.currentTabId = tab.id
        }
        primaryWindowId = first.id
        let preparation = tabManager.regularTabShortcutConversion.prepare(
            tab,
            preferredWindowId: second.id
        )
        guard case .displayed = preparation else {
            return XCTFail("Expected displayed conversion preparation")
        }
        let firstSession = ShortcutConversionWindowSessionState(first)
        let secondSession = ShortcutConversionWindowSessionState(second)
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        primaryWindowId = second.id
        let converted = tabManager.regularTabShortcutConversion.commit(
            tab,
            preparation: preparation,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: true
            )
        )

        XCTAssertNil(converted)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertFalse(tab.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(first),
            firstSession
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(second),
            secondSession
        )
        _ = cancellable
    }

    func testPlanPreparedForAnotherTabRejectsBeforeStructuralMutation() throws {
        let window = BrowserWindowState()
        var visibleSplitIds: [UUID] = []
        var sourceTabId: UUID?
        var persistedWindowIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            visibleSplitTabIds: { $0 == window.id ? visibleSplitIds : [] },
            primaryTrackedWindowId: { tabId in
                tabId == sourceTabId ? window.id : nil
            },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-source.example",
            in: space,
            activate: false
        )
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-companion.example",
            in: space,
            activate: false
        )
        let other = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://plan-other.example",
            in: space,
            activate: false
        )
        sourceTabId = source.id
        window.tabManager = tabManager
        window.currentSpaceId = space.id
        window.currentTabId = source.id
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [source.id, companion.id],
                layoutKind: .vertical,
                host: .regular(spaceId: space.id)
            )
        )
        visibleSplitIds = group.tabIds
        tabManager.splitGroupStructureOwner.upsertSplitGroup(
            group,
            schedulePersistence: false
        )
        let preparation = tabManager.regularTabShortcutConversion
            .prepare(
                source,
                preferredWindowId: window.id
            )
        guard case .displayed = preparation else {
            return XCTFail("Expected a valid displayed conversion plan")
        }
        let windowSession = ShortcutConversionWindowSessionState(window)
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let converted = tabManager.regularTabShortcutConversion
            .commit(
                other,
                preparation: preparation,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: true
                )
            )

        XCTAssertNil(converted)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(source))
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(other))
        XCTAssertFalse(source.isShortcutLiveInstance)
        XCTAssertFalse(other.isShortcutLiveInstance)
        XCTAssertEqual(
            tabManager.splitGroupCollectionStateOwner.group(with: group.id),
            group
        )
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(window),
            windowSession
        )
        _ = cancellable
    }

    func testNoDisplayingWindowPreparesDetachedConversionWithoutMutation() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://hidden.example",
            in: space,
            activate: false
        )
        let preparation = tabManager.regularTabShortcutConversion
            .prepare(tab)

        guard case .detached(let plan) = preparation else {
            return XCTFail("Expected a detached conversion plan")
        }
        XCTAssertEqual(plan.sourceTabId, tab.id)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertFalse(tab.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot.isEmpty)
    }
}
