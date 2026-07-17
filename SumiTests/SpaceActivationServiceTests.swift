import Foundation
@testable import Sumi
import XCTest

@MainActor
final class SpaceActivationServiceTests: XCTestCase {
    func testActivationStoresPreviousTabAndSelectsRegularTab() throws {
        let tabManager = BrowserManager()
        let previousSpace = Space(name: "Previous", profileId: UUID())
        let targetSpace = Space(name: "Target", profileId: UUID())
        let previousTab = makeTab(in: previousSpace)
        let targetTab = makeTab(in: targetSpace)
        tabManager.spaceStateOwner.replaceSpaces([previousSpace, targetSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(previousSpace)
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            previousSpace.id: [previousTab],
            targetSpace.id: [targetTab],
        ])
        tabManager.tabStateStore.selection.replaceCurrentTab(previousTab)
        let service = makeService(tabManager)

        service.setActiveSpace(targetSpace)

        XCTAssertEqual(previousSpace.activeTabId, previousTab.id)
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, targetSpace)
        XCTAssertIdentical(tabManager.tabStateStore.selection.currentTab, targetTab)
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
    }

    func testActivationUsesLiveSpacePinFromExactWindowContext() throws {
        let tabManager = BrowserManager()
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
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            firstLiveTab,
            for: firstPin.id,
            in: firstWindowId,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: firstWindowId,
                spaceID: targetSpace.id,
                profileID: targetSpace.profileId
            )
        ))
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            secondLiveTab,
            for: secondPin.id,
            in: secondWindowId,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: secondWindowId,
                spaceID: targetSpace.id,
                profileID: targetSpace.profileId
            )
        ))
        targetSpace.activeTabId = secondLiveTab.id
        let service = makeService(tabManager)

        service.setActiveSpace(
            targetSpace,
            contextWindowId: firstWindowId
        )

        XCTAssertIdentical(
            tabManager.tabStateStore.selection.currentTab,
            firstLiveTab
        )
    }

    func testSelectionFallbackOrderIsRegularThenSpacePinThenEssential() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            currentProfileId: { profileID }
        ))
        let sourceSpace = Space(name: "Source", profileId: UUID())
        let targetSpace = Space(name: "Target", profileId: profileID)
        let regular = makeTab(in: targetSpace)
        let pin = makePin(in: targetSpace, index: 0)
        let livePin = makeLiveTab(for: pin)
        let essential = makeTab(in: targetSpace)
        essential.isPinned = true
        let essentialPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: essential.url,
            title: "Essential"
        )
        essential.bindToShortcutPin(essentialPin)
        let windowId = UUID()
        tabManager.spaceStateOwner.replaceSpaces([sourceSpace, targetSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(sourceSpace)
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            targetSpace.id: [regular],
        ])
        tabManager.shortcutPinCollectionStateOwner
            .replaceAll(
                pinnedByProfile: [profileID: [essentialPin]],
                spacePinnedShortcuts: [targetSpace.id: [pin]],
                pendingPinnedWithoutProfile: []
            )
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            livePin,
            for: pin.id,
            in: windowId,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: windowId,
                spaceID: targetSpace.id,
                profileID: targetSpace.profileId
            )
        ))
        let essentialWindowID = UUID()
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            essential,
            for: essentialPin.id,
            in: essentialWindowID,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: essentialWindowID,
                spaceID: targetSpace.id,
                profileID: profileID
            )
        ))
        let service = makeService(tabManager)

        service.setActiveSpace(targetSpace, contextWindowId: windowId)
        XCTAssertIdentical(tabManager.tabStateStore.selection.currentTab, regular)

        tabManager.tabStateStore.selection.replaceCurrentTab(nil)
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([:])
        service.setActiveSpace(targetSpace, contextWindowId: windowId)
        XCTAssertIdentical(tabManager.tabStateStore.selection.currentTab, livePin)

        tabManager.tabStateStore.selection.replaceCurrentTab(nil)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.remove(pinId: pin.id, in: windowId)?.tab,
            livePin
        )
        service.setActiveSpace(targetSpace, contextWindowId: windowId)
        XCTAssertIdentical(tabManager.tabStateStore.selection.currentTab, essential)
    }

    func testRegularSelectionWinsOverLiveEssentialTab() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            currentProfileId: { profileID }
        ))
        let sourceSpace = Space(name: "Source", profileId: UUID())
        let targetSpace = Space(name: "Target", profileId: profileID)
        let regular = makeTab(in: targetSpace)
        let essentialPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )
        let essential = makeLiveTab(for: essentialPin)
        tabManager.spaceStateOwner.replaceSpaces([sourceSpace, targetSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(sourceSpace)
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            targetSpace.id: [regular],
        ])
        tabManager.shortcutPinCollectionStateOwner.replacePinnedByProfile([
            profileID: [essentialPin],
        ])
        let essentialWindowID = UUID()
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            essential,
            for: essentialPin.id,
            in: essentialWindowID,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: essentialWindowID,
                spaceID: targetSpace.id,
                profileID: profileID
            )
        ))
        let service = makeService(tabManager)

        service.setActiveSpace(targetSpace)

        XCTAssertIdentical(tabManager.tabStateStore.selection.currentTab, regular)
    }

    func testNilProfileBackfillUsesDefaultProfileWhenAvailable() throws {
        let defaultProfile = Profile(name: "Default")
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            defaultProfileId: { defaultProfile.id },
            profileExists: { $0 == defaultProfile.id },
            profile: { $0 == defaultProfile.id ? defaultProfile : nil }
        ))
        let targetSpace = Space(name: "Target")
        tabManager.spaceStateOwner.replaceSpaces([targetSpace])
        let service = makeService(tabManager)

        service.setActiveSpace(targetSpace)

        XCTAssertEqual(targetSpace.profileId, defaultProfile.id)
    }

    func testDeferredProfileBackfillDoesNotActivateUntilCommit() throws {
        let profile = Profile(name: "Deferred")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            defaultProfileId: { profile.id },
            profileExists: { $0 == profile.id },
            profile: { $0 == profile.id ? profile : nil },
            webViewLifecycle: transition.makeLifecycle()
        ))
        let previousSpace = Space(name: "Previous", profileId: UUID())
        let targetSpace = Space(name: "Target")
        let previousTab = makeTab(in: previousSpace)
        tabManager.spaceStateOwner.replaceSpaces([previousSpace, targetSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(previousSpace)
        tabManager.tabStateStore.selection.replaceCurrentTab(previousTab)
        let service = makeService(tabManager)

        XCTAssertFalse(service.setActiveSpace(targetSpace))
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, previousSpace)
        XCTAssertIdentical(tabManager.tabStateStore.selection.currentTab, previousTab)

        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.publishCommit)()
        try XCTUnwrap(transition.settlement)(.committed)

        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, targetSpace)
        XCTAssertEqual(targetSpace.profileId, profile.id)
    }

    private func makeService(
        _ tabManager: BrowserManager
    ) -> SpaceActivationService {
        SpaceActivationService(
            state: tabManager.tabStateStore,
            projection: SpaceLauncherProjectionService(
                regularTabs: tabManager.tabStateStore.regularTabs,
                pins: tabManager.shortcutPinCollectionStateOwner,
                folders: tabManager.folderCollectionStateOwner,
                splitOrdering: tabManager.splitGroupSidebarOrdering,
                transientTabs: tabManager.tabStateStore.transientTabs
            ),
            persistence: tabManager.structuralPersistence,
            profileAdmission: SpaceActivationProfileAdmission(
                runtimeConnection: tabManager.runtimePortConnection,
                profileTransitions: tabManager.spaceProfileTransitions
            ),
            shortcutPresentation: tabManager.shortcutPresentationOwner
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
