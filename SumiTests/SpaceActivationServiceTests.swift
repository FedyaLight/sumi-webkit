import Foundation
@testable import Sumi
import XCTest

@MainActor
final class SpaceActivationServiceTests: XCTestCase {
    func testActivationStoresPreviousTabAndSelectsRegularTab() throws {
        let tabManager = try makeInMemoryTabManager()
        let previousSpace = Space(name: "Previous", profileId: UUID())
        let targetSpace = Space(name: "Target", profileId: UUID())
        let previousTab = makeTab(in: previousSpace)
        let targetTab = makeTab(in: targetSpace)
        tabManager.spaceStateOwner.replaceSpaces([previousSpace, targetSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(previousSpace)
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            previousSpace.id: [previousTab],
            targetSpace.id: [targetTab],
        ])
        tabManager.selectionStateOwner.replaceCurrentTab(previousTab)
        let service = makeService(tabManager)

        service.setActiveSpace(targetSpace)

        XCTAssertEqual(previousSpace.activeTabId, previousTab.id)
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, targetSpace)
        XCTAssertIdentical(tabManager.selectionStateOwner.currentTab, targetTab)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
    }

    func testActivationUsesLiveSpacePinFromExactWindowContext() throws {
        let tabManager = try makeInMemoryTabManager()
        let currentSpace = Space(name: "Current", profileId: UUID())
        let targetSpace = Space(name: "Target", profileId: UUID())
        tabManager.spaceStateOwner.replaceSpaces([currentSpace, targetSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstPin = makePin(in: targetSpace, index: 0)
        let secondPin = makePin(in: targetSpace, index: 1)
        let firstLiveTab = makeLiveTab(for: firstPin)
        let secondLiveTab = makeLiveTab(for: secondPin)
        tabManager.shortcutPinCollectionStateOwner
            .replaceSpacePinnedShortcuts([
                targetSpace.id: [firstPin, secondPin],
            ])
        tabManager.transientTabRegistryOwner
            .replaceTransientShortcutTabsByWindow([
                firstWindowId: [firstPin.id: firstLiveTab],
                secondWindowId: [secondPin.id: secondLiveTab],
            ])
        targetSpace.activeTabId = secondLiveTab.id
        let service = makeService(tabManager)

        service.setActiveSpace(
            targetSpace,
            contextWindowId: firstWindowId
        )

        XCTAssertIdentical(
            tabManager.selectionStateOwner.currentTab,
            firstLiveTab
        )
    }

    func testSelectionFallbackOrderIsRegularThenSpacePinThenEssential() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceSpace = Space(name: "Source", profileId: UUID())
        let targetSpace = Space(name: "Target", profileId: UUID())
        let regular = makeTab(in: targetSpace)
        let pin = makePin(in: targetSpace, index: 0)
        let livePin = makeLiveTab(for: pin)
        let essential = makeTab(in: targetSpace)
        essential.isPinned = true
        let windowId = UUID()
        tabManager.spaceStateOwner.replaceSpaces([sourceSpace, targetSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(sourceSpace)
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            targetSpace.id: [regular],
        ])
        tabManager.shortcutPinCollectionStateOwner
            .replaceSpacePinnedShortcuts([targetSpace.id: [pin]])
        tabManager.transientTabRegistryOwner
            .replaceTransientShortcutTabsByWindow([
                windowId: [pin.id: livePin],
            ])
        var essentialReadCount = 0
        let service = makeService(
            tabManager,
            activeEssentialTabs: { _ in
                essentialReadCount += 1
                return [essential]
            }
        )

        service.setActiveSpace(targetSpace, contextWindowId: windowId)
        XCTAssertIdentical(tabManager.selectionStateOwner.currentTab, regular)
        XCTAssertEqual(essentialReadCount, 0)

        tabManager.selectionStateOwner.replaceCurrentTab(nil)
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([:])
        service.setActiveSpace(targetSpace, contextWindowId: windowId)
        XCTAssertIdentical(tabManager.selectionStateOwner.currentTab, livePin)
        XCTAssertEqual(essentialReadCount, 0)

        tabManager.selectionStateOwner.replaceCurrentTab(nil)
        tabManager.transientTabRegistryOwner
            .replaceTransientShortcutTabsByWindow([:])
        service.setActiveSpace(targetSpace, contextWindowId: windowId)
        XCTAssertIdentical(tabManager.selectionStateOwner.currentTab, essential)
        XCTAssertEqual(essentialReadCount, 1)
    }

    func testRegularSelectionDoesNotScanEssentialTabs() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceSpace = Space(name: "Source", profileId: UUID())
        let targetSpace = Space(name: "Target", profileId: UUID())
        let regular = makeTab(in: targetSpace)
        tabManager.spaceStateOwner.replaceSpaces([sourceSpace, targetSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(sourceSpace)
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            targetSpace.id: [regular],
        ])
        var essentialReadCount = 0
        let service = makeService(
            tabManager,
            activeEssentialTabs: { _ in
                essentialReadCount += 1
                return []
            }
        )

        service.setActiveSpace(targetSpace)

        XCTAssertIdentical(tabManager.selectionStateOwner.currentTab, regular)
        XCTAssertEqual(essentialReadCount, 0)
    }

    func testNilProfileBackfillUsesDefaultProfileWhenAvailable() throws {
        let tabManager = try makeInMemoryTabManager()
        let targetSpace = Space(name: "Target")
        tabManager.spaceStateOwner.replaceSpaces([targetSpace])
        let defaultProfileId = UUID()
        var assignments: [(UUID, UUID)] = []
        let service = makeService(
            tabManager,
            defaultProfileId: { defaultProfileId },
            assignSpaceProfile: { spaceId, profileId in
                assignments.append((spaceId, profileId))
                return .committed
            }
        )

        service.setActiveSpace(targetSpace)

        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments.first?.0, targetSpace.id)
        XCTAssertEqual(assignments.first?.1, defaultProfileId)
    }

    private func makeService(
        _ tabManager: TabManager,
        defaultProfileId: @escaping @MainActor () -> UUID? = { nil },
        currentProfileId: @escaping @MainActor () -> UUID? = { nil },
        assignSpaceProfile: @escaping @MainActor (
            UUID,
            UUID
        ) -> TabProfileAssignmentExecutionOutcome = { _, _ in .failed },
        activeEssentialTabs: @escaping @MainActor (UUID?) -> [Tab] = { _ in [] }
    ) -> SpaceActivationService {
        SpaceActivationService(
            state: tabManager.stateStore,
            projection: tabManager.spaceLauncherProjection,
            persistence: tabManager.structuralPersistence,
            profileIds: {
                (current: currentProfileId(), default: defaultProfileId())
            },
            assignSpaceProfile: assignSpaceProfile,
            activeEssentialTabs: activeEssentialTabs
        )
    }

    private func makeTab(in space: Space) -> Tab {
        Tab(
            url: URL(string: "https://example.com")
                ?? URL(fileURLWithPath: "/"),
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )
    }

    private func makePin(in space: Space, index: Int) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: index,
            launchURL: URL(string: "https://shortcut.example")
                ?? URL(fileURLWithPath: "/"),
            title: "Shortcut"
        )
    }

    private func makeLiveTab(for pin: ShortcutPin) -> Tab {
        let tab = Tab(
            url: pin.launchURL,
            spaceId: pin.spaceId,
            index: pin.index,
            loadsCachedFaviconOnInit: false
        )
        tab.bindToShortcutPin(pin)
        return tab
    }
}
