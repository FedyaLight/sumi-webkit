import Combine
import XCTest

@testable import Sumi

@MainActor
final class ShortcutTabMaterializerTests: XCTestCase {
    func testPresentationActivationRelocatesOnlyCanonicalExistingBinding() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        let sourceSpace = Space(name: "Source", profileId: profileID)
        let targetSpace = Space(name: "Target", profileId: profileID)
        tabManager.spaceStateOwner.replaceSpaces([sourceSpace, targetSpace])
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )
        tabManager.shortcutPinCollectionStateOwner.replacePinnedByProfile([
            profileID: [pin],
        ])
        let windowID = UUID()
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.bindToShortcutPin(pin)
        tab.profileId = profileID
        let sourcePage = LiveShortcutPresentationPageReceipt(
            windowID: windowID,
            spaceID: sourceSpace.id,
            profileID: profileID
        )
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            tab,
            for: pin.id,
            in: windowID,
            presentationPage: sourcePage
        ))

        let activated = tabManager.shortcutPresentationActivation.activate(
            pin,
            in: windowID,
            presentationSpaceID: targetSpace.id
        )

        XCTAssertIdentical(activated, tab)
        XCTAssertEqual(
            tabManager.liveShortcutTabs.entry(containing: tab)?
                .presentationPage,
            LiveShortcutPresentationPageReceipt(
                windowID: windowID,
                spaceID: targetSpace.id,
                profileID: profileID
            )
        )
    }

    func testPresentationActivationRejectsStalePhysicalProfileWithoutRelocation() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        let sourceSpace = Space(name: "Source", profileId: profileID)
        let targetSpace = Space(name: "Target", profileId: profileID)
        tabManager.spaceStateOwner.replaceSpaces([sourceSpace, targetSpace])
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )
        tabManager.shortcutPinCollectionStateOwner.replacePinnedByProfile([
            profileID: [pin],
        ])
        let windowID = UUID()
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.bindToShortcutPin(pin)
        tab.profileId = UUID()
        let sourcePage = LiveShortcutPresentationPageReceipt(
            windowID: windowID,
            spaceID: sourceSpace.id,
            profileID: profileID
        )
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            tab,
            for: pin.id,
            in: windowID,
            presentationPage: sourcePage
        ))

        XCTAssertNil(tabManager.shortcutPresentationActivation.activate(
            pin,
            in: windowID,
            presentationSpaceID: targetSpace.id
        ))
        XCTAssertEqual(
            tabManager.liveShortcutTabs.entry(containing: tab)?
                .presentationPage,
            sourcePage
        )
    }

    func testPresentationBatchRejectsBeforeRelocatingAnyEarlierResidence() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        let sourceSpace = Space(name: "Source", profileId: profileID)
        let targetSpace = Space(name: "Target", profileId: profileID)
        tabManager.spaceStateOwner.replaceSpaces([sourceSpace, targetSpace])
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )
        tabManager.shortcutPinCollectionStateOwner.replacePinnedByProfile([
            profileID: [pin],
        ])
        let windowID = UUID()
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.bindToShortcutPin(pin)
        tab.profileId = profileID
        let sourcePage = LiveShortcutPresentationPageReceipt(
            windowID: windowID,
            spaceID: sourceSpace.id,
            profileID: profileID
        )
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            tab,
            for: pin.id,
            in: windowID,
            presentationPage: sourcePage
        ))

        XCTAssertFalse(tabManager.shortcutPresentationActivation.withActivation([
            .init(
                pinID: pin.id,
                windowID: windowID,
                presentationSpaceID: targetSpace.id
            ),
            .init(
                pinID: UUID(),
                windowID: windowID,
                presentationSpaceID: targetSpace.id
            ),
        ]) { _ in true })
        XCTAssertEqual(
            tabManager.liveShortcutTabs.entry(containing: tab)?
                .presentationPage,
            sourcePage
        )
    }

    func testRejectedFreshActivationRollsBackWithoutPublishing() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        let space = Space(name: "Target", profileId: profileID)
        tabManager.spaceStateOwner.replaceSpaces([space])
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            executionProfileId: profileID,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://fresh.example")!,
            title: "Fresh"
        )
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        let windowID = UUID()
        var events = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { events += 1 }
        events = 0
        let revision = tabManager.structuralLookupCoordinator.mutationRevision
        var stagedTab: Tab?

        let accepted = tabManager.shortcutPresentationActivation
            .withActivation([
                .init(
                    pinID: pin.id,
                    windowID: windowID,
                    presentationSpaceID: space.id
                ),
            ]) { tabs in
                stagedTab = tabs.first
                XCTAssertIdentical(
                    tabManager.liveShortcutTabs.tab(
                        for: pin.id,
                        in: windowID
                    ),
                    stagedTab
                )
                if let stagedTab {
                    XCTAssertIdentical(
                        tabManager.tabCollectionMembershipOwner.tab(
                            for: stagedTab.id
                        ),
                        stagedTab
                    )
                }
                return false
            }

        XCTAssertFalse(accepted)
        XCTAssertNotNil(stagedTab)
        XCTAssertNil(tabManager.liveShortcutTabs.tab(for: pin.id, in: windowID))
        XCTAssertNil(stagedTab.flatMap {
            tabManager.tabCollectionMembershipOwner.tab(for: $0.id)
        })
        XCTAssertEqual(events, 0)
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            revision
        )
        _ = cancellable
    }

    func testPostDownstreamPinDriftRejectsAndRemovesFreshStageWithoutEffects() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        let space = Space(name: "Target", profileId: profileID)
        tabManager.spaceStateOwner.replaceSpaces([space])
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            executionProfileId: profileID,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://drift.example")!,
            title: "Before"
        )
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        let windowID = UUID()
        var events = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { events += 1 }
        events = 0
        let revision = tabManager.structuralLookupCoordinator.mutationRevision
        var stagedTab: Tab?

        let accepted = tabManager.shortcutPresentationActivation
            .withActivation([
                .init(
                    pinID: pin.id,
                    windowID: windowID,
                    presentationSpaceID: space.id
                ),
            ]) { tabs in
                stagedTab = tabs.first
                pin.title = "After"
                return true
            }

        XCTAssertFalse(accepted)
        XCTAssertNil(tabManager.liveShortcutTabs.tab(for: pin.id, in: windowID))
        XCTAssertNil(stagedTab.flatMap {
            tabManager.tabCollectionMembershipOwner.tab(for: $0.id)
        })
        XCTAssertEqual(events, 0)
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            revision
        )
        _ = cancellable
    }

    func testFreshResidenceDriftRejectsWithoutLeakingMembership() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        let space = Space(name: "Target", profileId: profileID)
        tabManager.spaceStateOwner.replaceSpaces([space])
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            executionProfileId: profileID,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://residence-drift.example")!,
            title: "Residence Drift"
        )
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        let windowID = UUID()
        var stagedTab: Tab?

        let accepted = tabManager.shortcutPresentationActivation
            .withActivation([
                .init(
                    pinID: pin.id,
                    windowID: windowID,
                    presentationSpaceID: space.id
                ),
            ]) { tabs in
                stagedTab = tabs.first
                guard let stagedTab else { return false }
                return tabManager.liveShortcutTabs.remove(
                    tabId: stagedTab.id
                ) != nil
            }

        XCTAssertFalse(accepted)
        XCTAssertNil(tabManager.liveShortcutTabs.tab(for: pin.id, in: windowID))
        XCTAssertNil(stagedTab.flatMap {
            tabManager.tabCollectionMembershipOwner.tab(for: $0.id)
        })
    }

    func testReentrantResidenceDriftRejectsWithoutCrashingRollback() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        let sourceSpace = Space(name: "Source", profileId: profileID)
        let targetSpace = Space(name: "Target", profileId: profileID)
        tabManager.spaceStateOwner.replaceSpaces([sourceSpace, targetSpace])
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://reentrant.example")!,
            title: "Reentrant"
        )
        tabManager.shortcutPinCollectionStateOwner.replacePinnedByProfile([
            profileID: [pin],
        ])
        let windowID = UUID()
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.bindToShortcutPin(pin)
        tab.profileId = profileID
        let sourcePage = LiveShortcutPresentationPageReceipt(
            windowID: windowID,
            spaceID: sourceSpace.id,
            profileID: profileID
        )
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            tab,
            for: pin.id,
            in: windowID,
            presentationPage: sourcePage
        ))
        var events = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { events += 1 }
        events = 0
        let revision = tabManager.structuralLookupCoordinator.mutationRevision

        let accepted = tabManager.shortcutPresentationActivation
            .withActivation([
                .init(
                    pinID: pin.id,
                    windowID: windowID,
                    presentationSpaceID: targetSpace.id
                ),
            ]) { _ in
                tabManager.liveShortcutTabs.relocate(
                    tab,
                    from: pin.id,
                    to: pin.id,
                    in: windowID,
                    presentationPage: sourcePage
                )
            }

        XCTAssertFalse(accepted)
        XCTAssertEqual(
            tabManager.liveShortcutTabs.entry(containing: tab)?
                .presentationPage,
            sourcePage
        )
        XCTAssertEqual(events, 1)
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            revision + 1
        )
        _ = cancellable
    }

    func testRejectedRelocationRestoresSourcePageWithoutPublishing() throws {
        let profileID = UUID()
        let tabManager = BrowserManager()
        let sourceSpace = Space(name: "Source", profileId: profileID)
        let targetSpace = Space(name: "Target", profileId: profileID)
        tabManager.spaceStateOwner.replaceSpaces([sourceSpace, targetSpace])
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://relocation.example")!,
            title: "Relocation"
        )
        tabManager.shortcutPinCollectionStateOwner.replacePinnedByProfile([
            profileID: [pin],
        ])
        let windowID = UUID()
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.bindToShortcutPin(pin)
        tab.profileId = profileID
        let sourcePage = LiveShortcutPresentationPageReceipt(
            windowID: windowID,
            spaceID: sourceSpace.id,
            profileID: profileID
        )
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            tab,
            for: pin.id,
            in: windowID,
            presentationPage: sourcePage
        ))
        var events = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { events += 1 }
        let revision = tabManager.structuralLookupCoordinator.mutationRevision

        XCTAssertFalse(
            tabManager.shortcutPresentationActivation.withActivation([
                .init(
                    pinID: pin.id,
                    windowID: windowID,
                    presentationSpaceID: targetSpace.id
                ),
            ]) { _ in false }
        )

        XCTAssertEqual(
            tabManager.liveShortcutTabs.entry(containing: tab)?
                .presentationPage,
            sourcePage
        )
        XCTAssertEqual(events, 0)
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            revision
        )
        _ = cancellable
    }

    func testFreshEssentialUsesExecutionProfileAndReusesExactIdentity() throws {
        let windowId = UUID()
        let ownerProfileId = UUID()
        let executionProfile = Profile(name: "Execution")
        let executionProfileId = executionProfile.id
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            profile: { $0 == executionProfileId ? executionProfile : nil }
        ))
        let presentationSpace = Space(
            name: "Presentation",
            profileId: ownerProfileId
        )
        tabManager.spaceStateOwner.append(presentationSpace)
        let ignoredSpaceId = UUID()
        let ignoredFolderId = UUID()
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: ownerProfileId,
            executionProfileId: executionProfileId,
            spaceId: ignoredSpaceId,
            index: 0,
            folderId: ignoredFolderId,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )
        var eventCount = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher
            .sink { eventCount += 1 }

        let fresh = withExtendedLifetime(cancellable) {
            tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowId,
                currentSpaceId: presentationSpace.id
            )!
        }

        XCTAssertEqual(eventCount, 1)
        XCTAssertEqual(fresh.shortcutPinId, pin.id)
        XCTAssertEqual(fresh.shortcutPinRole, .essential)
        XCTAssertNil(fresh.spaceId)
        XCTAssertEqual(fresh.profileId, executionProfileId)
        XCTAssertNil(fresh.folderId)
        XCTAssertFalse(fresh.isPinned)
        XCTAssertFalse(fresh.isSpacePinned)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: windowId),
            fresh
        )
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: fresh.id),
            fresh
        )

        eventCount = 0
        let reused = withExtendedLifetime(cancellable) {
            tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowId,
                currentSpaceId: presentationSpace.id
            )!
        }

        XCTAssertIdentical(reused, fresh)
        XCTAssertEqual(eventCount, 0)
    }

    func testSpacePinnedMaterializationInheritsMetadataAndRebindsOnce() throws {
        let spaceProfile = Profile(name: "Space")
        let spaceProfileId = spaceProfile.id
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            profile: { $0 == spaceProfileId ? spaceProfile : nil }
        ))
        let space = Space(
            name: "Workspace",
            profileId: spaceProfileId
        )
        tabManager.spaceStateOwner.append(space)
        let firstFolderId = UUID()
        let secondFolderId = UUID()
        let windowId = UUID()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            folderId: firstFolderId,
            launchURL: URL(string: "https://space-pinned.example")!,
            title: "Space Pinned"
        )
        var eventCount = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher
            .sink { eventCount += 1 }

        let fresh = withExtendedLifetime(cancellable) {
            tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowId,
                currentSpaceId: space.id
            )!
        }

        XCTAssertEqual(eventCount, 1)
        XCTAssertEqual(fresh.shortcutPinId, pin.id)
        XCTAssertEqual(fresh.shortcutPinRole, .spacePinned)
        XCTAssertEqual(fresh.spaceId, space.id)
        XCTAssertNil(fresh.profileId)
        XCTAssertEqual(fresh.folderId, firstFolderId)
        XCTAssertFalse(fresh.isPinned)
        XCTAssertFalse(fresh.isSpacePinned)

        let updatedPin = pin.updated(folderId: .some(secondFolderId))
        eventCount = 0
        let rebound = withExtendedLifetime(cancellable) {
            tabManager.shortcutTabMaterializer.materialize(
                updatedPin,
                in: windowId,
                currentSpaceId: space.id
            )!
        }

        XCTAssertIdentical(rebound, fresh)
        XCTAssertEqual(rebound.folderId, secondFolderId)
        XCTAssertEqual(rebound.spaceId, space.id)
        XCTAssertNil(rebound.profileId)
        XCTAssertEqual(eventCount, 0)
    }
}
