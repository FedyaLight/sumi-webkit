import Combine
import SumiDomain
import SumiWebRuntime
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class ShortcutTabPromotionServiceTests: XCTestCase {
    func testGroupedPinPromotionDissolvesShortcutGroupInEveryWindow() throws {
        let first = BrowserWindowState()
        let second = BrowserWindowState()
        let probe = PromotionProbe()
        let harness = makeHarness(
            windows: [first, second],
            probe: probe
        )
        let tabManager = harness.browser
        let space = makeSpace(in: tabManager, name: "Space")
        let pin = makePin(spaceId: space.id)
        let companionPin = makePin(spaceId: space.id, index: 1)
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin, companionPin], for: space.id)
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(pin.id),
                .shortcutPin(companionPin.id),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        for windowState in [first, second] {
            let live = tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: space.id
            )!
            windowState.currentSpaceId = space.id
            windowState.currentTabId = live.id
            windowState.currentShortcutPinId = pin.id
            windowState.currentShortcutPinRole = pin.role
            windowState.splitSelection = WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(pin.id)
            )
        }

        XCTAssertTrue(
            harness.pinToRegular.convert(
                pin,
                into: space.id,
                at: 0,
                preferredWindowId: second.id
            )
        )

        let promoted = try XCTUnwrap(
            tabManager.regularTabCollectionOwner.tabs(in: space).first
        )
        XCTAssertNil(tabManager.splitGroupStore.group(id: group.id))
        XCTAssertNil(first.splitSelection)
        XCTAssertNil(second.splitSelection)
        XCTAssertNil(first.currentTabId)
        XCTAssertEqual(second.currentTabId, promoted.id)
        XCTAssertNotNil(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(
                by: companionPin.id
            )
        )
        XCTAssertTrue(tabManager.liveShortcutTabs.entries(for: pin.id).isEmpty)
    }

    func testPreferredWindowInstanceIsPromotedAndOtherInstancesRetireAfterCommit() throws {
        let first = BrowserWindowState(id: try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        ))
        let preferred = BrowserWindowState(id: try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        ))
        let probe = PromotionProbe()
        let harness = makeHarness(
            windows: [first, preferred],
            probe: probe
        )
        let tabManager = harness.browser
        let space = makeSpace(in: tabManager, name: "Space")
        let pin = makePin(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        let firstLive = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: first.id,
            currentSpaceId: space.id
        )!
        let preferredLive = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: preferred.id,
            currentSpaceId: space.id
        )!
        first.currentTabId = firstLive.id
        first.currentShortcutPinId = pin.id
        first.currentShortcutPinRole = pin.role
        preferred.currentTabId = preferredLive.id
        preferred.currentShortcutPinId = pin.id
        preferred.currentShortcutPinRole = pin.role
        let cancellable: AnyCancellable? = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { probe.structuralEvents += 1 }
        probe.structuralEvents = 0

        let didPromote = tabManager.structuralLookupCoordinator.withTransaction {
            harness.pinToRegular.convert(
                pin,
                into: space.id,
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
        let harness = makeHarness(
            windows: [higher, lower],
            probe: probe
        )
        let tabManager = harness.browser
        let space = makeSpace(in: tabManager, name: "Space")
        let pin = makePin(spaceId: space.id)
        let lowerLive = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: lower.id,
            currentSpaceId: space.id
        )!
        let higherLive = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: higher.id,
            currentSpaceId: space.id
        )!

        let plan = try XCTUnwrap(harness.promotion.preparePromotion(
            pin,
            into: space.id,
            allowsGroupedPin: false
        ))
        let prepared = try XCTUnwrap(
            tabManager.structuralLookupCoordinator.withTransaction {
                harness.promotion.commit(plan, splitTransition: .none)
            }
        )
        let result = harness.promotion.finish(prepared)

        XCTAssertIdentical(result.tab, lowerLive)
        XCTAssertEqual(result.retirement.retiredTabIds, [higherLive.id])
    }

    func testInvalidTargetDoesNotConsumeLiveInstanceAndNoLivePromotionCreatesRegularTab() throws {
        let window = BrowserWindowState()
        let probe = PromotionProbe()
        let harness = makeHarness(windows: [window], probe: probe)
        let tabManager = harness.browser
        let space = makeSpace(in: tabManager, name: "Space")
        let pin = makePin(spaceId: space.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: window.id,
            currentSpaceId: space.id
        )!

        XCTAssertNil(
            harness.promotion.promote(pin, into: UUID())
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
            harness.promotion.promote(freshPin, into: space.id)
        )
        XCTAssertEqual(result.tab.url, freshPin.launchURL)
        XCTAssertFalse(result.tab.isShortcutLiveInstance)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(result.tab))
    }

    func testMissingRuntimeFailsBeforeConsumingAnyLiveRegistryEntry() throws {
        let tabManager = BrowserManager()
        tabManager.tabRuntimeLifecycle.shutdown()
        let promotion = makePromotion(in: tabManager)
        let space = makeSpace(in: tabManager, name: "Space")
        let pin = makePin(spaceId: space.id)
        let windowId = UUID()
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )!

        XCTAssertNil(
            promotion.promote(pin, into: space.id)
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
        let harness = makeHarness(windows: [window], probe: probe)
        let tabManager = harness.browser
        let sourceSpace = makeSpace(in: tabManager, name: "Source")
        let visibleSpace = makeSpace(in: tabManager, name: "Visible")
        let targetSpace = makeSpace(in: tabManager, name: "Target")
        let pin = makePin(spaceId: sourceSpace.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )!
        let selectedTabId = UUID()
        window.currentSpaceId = visibleSpace.id
        window.currentTabId = selectedTabId
        window.currentShortcutPinId = pin.id
        window.currentShortcutPinRole = pin.role

        let result = try XCTUnwrap(
            harness.promotion.promote(
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

    private func makeHarness(
        windows: [BrowserWindowState],
        probe: PromotionProbe
    ) -> PromotionHarness {
        let profile = Profile(name: "Promotion")
        let states = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profileExists: { $0 == profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { windows.map { ($0.id, $0) } },
            windowStates: { windows },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .accepting
            ),
            persistWindowSession: { probe.persistedWindowIds.append($0.id) }
        )
        let browser = BrowserManager(runtimePorts: runtime)
        browser.profileManager.profiles = [profile]
        browser.currentProfile = profile
        windows.forEach { _ = browser.windowRegistry.register($0) }
        let promotion = makePromotion(in: browser)
        return PromotionHarness(
            browser: browser,
            promotion: promotion,
            pinToRegular: ShortcutPinToRegularTabService.compose(
                promotion: promotion,
                splitGroups: browser.splitGroupStore,
                splitMutations: browser.splitGroupMutations,
                pinStore: browser.shortcutPinStoreOwner,
                pins: browser.shortcutPinCollectionStateOwner,
                persistence: browser.structuralPersistence,
                structuralLookup: browser.structuralLookupCoordinator
            )
        )
    }

    private func makePromotion(
        in browser: BrowserManager
    ) -> ShortcutTabPromotionService {
        ShortcutTabPromotionService.compose(
            registry: browser.liveShortcutTabs,
            spaces: browser.spaceStateOwner,
            splitGroups: browser.splitGroupStore,
            tabFactory: browser.tabFactory,
            regularTabs: browser.regularTabCollectionOwner,
            runtimeConnection: browser.runtimePortConnection,
            retirement: browser.shortcutLiveTabRetirement,
            membership: browser.tabCollectionMembershipOwner,
            structuralLookup: browser.structuralLookupCoordinator
        )
    }

    private func makeSpace(
        in browser: BrowserManager,
        name: String
    ) -> Space {
        let space = Space(
            name: name,
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileId: browser.currentProfile?.id
        )
        browser.spaceStateOwner.append(space)
        return space
    }

    private func makePin(spaceId: UUID, index: Int = 0) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: index,
            launchURL: URL(string: "https://promotion.example")!,
            title: "Promotion"
        )
    }
}

@MainActor
private struct PromotionHarness {
    let browser: BrowserManager
    let promotion: ShortcutTabPromotionService
    let pinToRegular: ShortcutPinToRegularTabService
}

@MainActor
private final class PromotionProbe {
    var structuralEvents = 0
    var persistedWindowIds: [UUID] = []
}
