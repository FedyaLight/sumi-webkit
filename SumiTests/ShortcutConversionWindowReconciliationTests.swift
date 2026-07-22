import Combine
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class ShortcutConversionWindowTests: XCTestCase {
    func testHistoryOnlyCleanupDoesNotPersistUnchangedWindowSession() throws {
        let profile = Profile(name: "Conversion")
        let displayed = BrowserWindowState()
        let historyOnly = BrowserWindowState()
        let states = [displayed.id: displayed, historyOnly.id: historyOnly]
        var persistedWindowIds: [UUID] = []
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            windowStates: { Array(states.values) },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .accepting
            ),
            persistWindowSession: { persistedWindowIds.append($0.id) }
        ))
        states.values.forEach {
            tabManager.tabResidenceAuthority.establishResidenceSession(on: $0)
            tabManager.windowRegistry.register($0)
        }
        let space = try XCTUnwrap(tabManager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://history-only.example",
            in: space,
            activate: false
        )
        displayed.currentSpaceId = space.id
        displayed.currentProfileId = profile.id
        displayed.currentTabId = tab.id
        historyOnly.currentSpaceId = space.id
        historyOnly.currentProfileId = profile.id
        historyOnly.currentTabId = UUID()
        historyOnly.selectionHistory.recordRegularTabSelection(
            tab.id,
            in: space.id
        )
        historyOnly.selectionHistory.recordSelection(
            .regularTab(tab.id),
            in: space.id
        )

        let pin = tabManager.regularTabShortcutConversion.convert(
            tab,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            ),
            preferredWindowId: displayed.id
        )

        XCTAssertNotNil(pin)
        XCTAssertFalse(persistedWindowIds.contains(historyOnly.id))
        XCTAssertFalse(
            historyOnly.selectionHistory
                .recentRegularTabIdsBySpace[space.id]?.contains(tab.id) ?? false
        )
        XCTAssertFalse(
            historyOnly.selectionHistory
                .recentSelectionItemsBySpace[space.id]?
                .contains(.regularTab(tab.id)) ?? false
        )
    }

    func testDetachedConversionRepairsRememberedWindowAfterCommit() throws {
        let profile = Profile(name: "Conversion")
        let remembered = BrowserWindowState()
        var structuralEvents = 0
        var persisted: [(UUID, Int)] = []
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == remembered.id ? remembered : nil },
            windows: { [(remembered.id, remembered)] },
            windowStates: { [remembered] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .accepting
            ),
            persistWindowSession: {
                persisted.append(($0.id, structuralEvents))
            }
        ))
        tabManager.tabResidenceAuthority.establishResidenceSession(on: remembered)
        tabManager.windowRegistry.register(remembered)
        let space = try XCTUnwrap(tabManager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://detached.example",
            in: space,
            activate: false
        )
        let fallback = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://fallback.example",
            in: space,
            activate: false
        )
        remembered.currentSpaceId = space.id
        remembered.currentProfileId = profile.id
        remembered.currentTabId = UUID()
        remembered.activeTabForSpace[space.id] = tab.id
        remembered.selectionHistory.recordRegularTabSelection(
            tab.id,
            in: space.id
        )
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        let pin = tabManager.regularTabShortcutConversion.convert(
            tab,
            destination: TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )

        XCTAssertNotNil(pin)
        XCTAssertEqual(structuralEvents, 1)
        XCTAssertFalse(tabManager.regularTabCollectionOwner.contains(tab))
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: tab.id))
        XCTAssertEqual(remembered.activeTabForSpace[space.id], fallback.id)
        XCTAssertEqual(
            persisted.filter { $0.0 == remembered.id }.map(\.1),
            [1]
        )
        _ = cancellable
    }

}
