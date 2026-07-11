import Combine
import SumiWebRuntime
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class ShortcutTabPromotionServiceTests: XCTestCase {
    func testPreferredWindowInstanceIsPromotedAndOtherInstancesRetireAfterCommit() throws {
        let first = BrowserWindowState(id: try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        ))
        let preferred = BrowserWindowState(id: try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        ))
        let probe = PromotionProbe()
        let tabManager = try makeTabManager(
            windows: [first, preferred],
            probe: probe
        )
        first.tabManager = tabManager
        preferred.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        let firstLive = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: first.id,
            currentSpaceId: space.id
        )
        let preferredLive = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: preferred.id,
            currentSpaceId: space.id
        )
        first.currentTabId = firstLive.id
        first.currentShortcutPinId = pin.id
        first.currentShortcutPinRole = pin.role
        preferred.currentTabId = preferredLive.id
        preferred.currentShortcutPinId = pin.id
        preferred.currentShortcutPinRole = pin.role
        var cancellable: AnyCancellable? = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { probe.structuralEvents += 1 }
        probe.structuralEvents = 0

        let didPromote = tabManager.structuralLookupCoordinator.withTransaction {
            tabManager.shortcutPinCommandOwner.convertShortcutPinToRegularTab(
                pin,
                in: space.id,
                at: 0,
                preferredWindowId: preferred.id
            )
        }

        XCTAssertTrue(didPromote)

        XCTAssertIdentical(
            tabManager.regularTabCollectionOwner.tabs(in: space).first,
            preferredLive
        )
        XCTAssertFalse(preferredLive.isShortcutLiveInstance)
        XCTAssertNil(preferredLive.shortcutPinId)
        XCTAssertEqual(preferred.currentTabId, preferredLive.id)
        XCTAssertNil(preferred.currentShortcutPinId)
        XCTAssertEqual(preferred.activeTabForSpace[space.id], preferredLive.id)
        XCTAssertEqual(
            preferred.selectionHistory.recentRegularTabIdsBySpace[space.id]?.first,
            preferredLive.id
        )
        XCTAssertEqual(probe.persistedWindowIds.filter { $0 == preferred.id }.count, 1)
        XCTAssertNil(first.currentTabId)
        XCTAssertTrue(tabManager.liveShortcutTabs.entries(for: pin.id).isEmpty)
        XCTAssertEqual(probe.unloadedTabIds, [firstLive.id])
        XCTAssertEqual(probe.closedTabBatches, [[firstLive.id]])
        XCTAssertEqual(probe.eventsSeenAtUnload, [1])
        XCTAssertEqual(probe.structuralEvents, 1)
        XCTAssertNil(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id)
        )
        _ = cancellable
    }

    func testFallbackPromotionChoosesLowestWindowUUIDDeterministically() throws {
        let lower = BrowserWindowState(id: try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        ))
        let higher = BrowserWindowState(id: try XCTUnwrap(
            UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
        ))
        let probe = PromotionProbe()
        let tabManager = try makeTabManager(
            windows: [higher, lower],
            probe: probe
        )
        lower.tabManager = tabManager
        higher.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        let lowerLive = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: lower.id,
            currentSpaceId: space.id
        )
        let higherLive = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: higher.id,
            currentSpaceId: space.id
        )

        let result = try XCTUnwrap(
            tabManager.shortcutTabPromotion.promote(pin, into: space.id)
        )

        XCTAssertIdentical(result.tab, lowerLive)
        XCTAssertEqual(probe.unloadedTabIds, [higherLive.id])
        XCTAssertEqual(result.retirement.retiredTabIds, [higherLive.id])
    }

    func testInvalidTargetDoesNotConsumeLiveInstanceAndNoLivePromotionCreatesRegularTab() throws {
        let window = BrowserWindowState()
        let probe = PromotionProbe()
        let tabManager = try makeTabManager(windows: [window], probe: probe)
        window.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: window.id,
            currentSpaceId: space.id
        )

        XCTAssertNil(
            tabManager.shortcutTabPromotion.promote(pin, into: UUID())
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: window.id),
            liveTab
        )

        _ = tabManager.shortcutLiveTabRetirement.retire(
            pinId: pin.id,
            in: window.id
        )
        let freshPin = makePin(spaceId: space.id)
        let result = try XCTUnwrap(
            tabManager.shortcutTabPromotion.promote(freshPin, into: space.id)
        )
        XCTAssertEqual(result.tab.url, freshPin.launchURL)
        XCTAssertFalse(result.tab.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(result.tab))
    }

    func testMissingRuntimeFailsBeforeConsumingAnyLiveRegistryEntry() throws {
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let pin = makePin(spaceId: space.id)
        let windowId = UUID()
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )

        XCTAssertNil(
            tabManager.shortcutTabPromotion.promote(pin, into: space.id)
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: windowId),
            liveTab
        )
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space).isEmpty)
        XCTAssertTrue(liveTab.isShortcutLiveInstance)
    }

    func testStaleShortcutMetadataDoesNotSelectPromotedTabOrSwitchSpace() throws {
        let window = BrowserWindowState()
        let probe = PromotionProbe()
        let tabManager = try makeTabManager(windows: [window], probe: probe)
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(name: "Source")
        let visibleSpace = tabManager.spaceServices.catalog.createSpace(name: "Visible")
        let targetSpace = tabManager.spaceServices.catalog.createSpace(name: "Target")
        let pin = makePin(spaceId: sourceSpace.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )
        let selectedTabId = UUID()
        window.currentSpaceId = visibleSpace.id
        window.currentTabId = selectedTabId
        window.currentShortcutPinId = pin.id
        window.currentShortcutPinRole = pin.role

        let result = try XCTUnwrap(
            tabManager.shortcutTabPromotion.promote(
                pin,
                into: targetSpace.id,
                preferredWindowId: window.id
            )
        )

        XCTAssertIdentical(result.tab, liveTab)
        XCTAssertEqual(window.currentSpaceId, visibleSpace.id)
        XCTAssertEqual(window.currentTabId, selectedTabId)
        XCTAssertNil(window.currentShortcutPinId)
    }

    private func makeTabManager(
        windows: [BrowserWindowState],
        probe: PromotionProbe
    ) throws -> TabManager {
        let states = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let runtime = TestRuntimePorts.make(
            windowState: { states[$0] },
            windows: { windows.map { ($0.id, $0) } },
            windowStates: { windows },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                unloadTab: {
                    probe.eventsSeenAtUnload.append(probe.structuralEvents)
                    probe.unloadedTabIds.append($0.id)
                }
            ),
            handleTabClosures: { probe.closedTabBatches.append($0) },
            persistWindowSession: { probe.persistedWindowIds.append($0.id) }
        )
        let container = try makeInMemoryStartupModelContainer()
        return TabManager(
            runtimePorts: runtime,
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
    }

    private func makePin(spaceId: UUID) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            launchURL: URL(string: "https://promotion.example")!,
            title: "Promotion"
        )
    }
}

@MainActor
private final class PromotionProbe {
    var structuralEvents = 0
    var unloadedTabIds: [UUID] = []
    var closedTabBatches: [Set<UUID>] = []
    var eventsSeenAtUnload: [Int] = []
    var persistedWindowIds: [UUID] = []
}
