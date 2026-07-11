import Foundation
@testable import Sumi
import SumiWebRuntime
import WebKit
import XCTest

@MainActor
final class TabCreationPlacementServiceTests: XCTestCase {
    func testExplicitAndFallbackPlacementsWinWithoutProfileRepair() throws {
        let tabManager = try makeInMemoryTabManager()
        let explicit = tabManager.spaceServices.catalog.createSpace(
            name: "Explicit"
        )
        let fallback = tabManager.spaceServices.catalog.createSpace(
            name: "Fallback"
        )

        let explicitTab = installTab(
            preferred: explicit,
            fallbackSpaceId: fallback.id,
            tabManager: tabManager
        )
        let fallbackTab = installTab(
            preferred: nil,
            fallbackSpaceId: fallback.id,
            tabManager: tabManager
        )

        XCTAssertEqual(explicitTab.spaceId, explicit.id)
        XCTAssertEqual(fallbackTab.spaceId, fallback.id)
    }

    func testPlacementPrefersCurrentProfileSpaceWithoutPersistingAnOverride() throws {
        let tabManager = try makeInMemoryTabManager()
        let selectedProfileID = UUID()
        let currentProfileID = UUID()
        let selected = Space(name: "Selected", profileId: selectedProfileID)
        let currentProfileSpace = Space(
            name: "Current Profile",
            profileId: currentProfileID
        )
        tabManager.spaceStateOwner.replaceSpaces([selected, currentProfileSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(selected)
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                currentProfileId: { currentProfileID },
                defaultProfileId: { selectedProfileID }
            )
        )

        let tab = installTab(preferred: nil, tabManager: tabManager)

        XCTAssertEqual(tab.spaceId, currentProfileSpace.id)
        XCTAssertNil(tab.profileId)
    }

    func testStableSpaceProfileDrivesRuntimeMaterializationWithoutDurableOverride() throws {
        let profile = Profile(name: "Runtime Profile")
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        let space = Space(name: "Profiled", profileId: profile.id)
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://runtime-profile.example",
            in: space,
            activate: false
        )
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(
                reason: "TabCreationPlacementServiceTests.runtimeProfile"
            )
        )

        XCTAssertNil(tab.profileId)
        XCTAssertIdentical(tab.resolveProfile(), profile)
        XCTAssertIdentical(webView.configuration.websiteDataStore, profile.dataStore)
    }

    func testInFlightProfileOverridesExistingCanonicalProfileUntilCommit() throws {
        let existingProfile = Profile(name: "Existing")
        let pendingProfile = Profile(name: "Pending")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [
                existingProfile.id: existingProfile,
                pendingProfile.id: pendingProfile,
            ],
            currentProfileID: { pendingProfile.id },
            transition: transition
        )
        let space = Space(name: "Profiled", profileId: existingProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([space])

        XCTAssertEqual(
            tabManager.profileAssignments.spaces.assign(
                spaceID: space.id,
                toProfile: pendingProfile.id
            ),
            .deferred
        )

        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://pending.example",
            in: space,
            activate: false
        )

        XCTAssertEqual(space.profileId, existingProfile.id)
        XCTAssertEqual(follower.profileId, pendingProfile.id)
        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)

        XCTAssertEqual(space.profileId, pendingProfile.id)
        XCTAssertNil(follower.profileId)
    }

    func testSpaceCommitDoesNotInvalidateAcceptedFollowerProfileTransition() throws {
        let existingProfile = Profile(name: "Existing")
        let pendingProfile = Profile(name: "Pending")
        let explicitProfile = Profile(name: "Explicit")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [
                existingProfile.id: existingProfile,
                pendingProfile.id: pendingProfile,
                explicitProfile.id: explicitProfile,
            ],
            currentProfileID: { pendingProfile.id },
            transition: transition
        )
        let space = Space(name: "Profiled", profileId: existingProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([space])

        XCTAssertEqual(
            tabManager.profileAssignments.spaces.assign(
                spaceID: space.id,
                toProfile: pendingProfile.id
            ),
            .deferred
        )
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://follower.example",
            in: space,
            activate: false
        )
        XCTAssertEqual(follower.profileId, pendingProfile.id)
        XCTAssertTrue(
            tabManager.profileAssignments.tabs.assign(
                follower,
                toProfile: explicitProfile.id
            )
        )
        let tabIntent = try XCTUnwrap(transition.tabIntent)
        XCTAssertTrue(follower.profileAssignment.isCurrent(tabIntent))

        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)

        XCTAssertEqual(space.profileId, pendingProfile.id)
        XCTAssertEqual(follower.profileId, pendingProfile.id)
        XCTAssertTrue(follower.profileAssignment.isCurrent(tabIntent))
        XCTAssertTrue(follower.profileAssignment.stage(tabIntent))
        XCTAssertTrue(follower.profileAssignment.finish(tabIntent))
        try XCTUnwrap(transition.tabSettlement)(.committed)

        XCTAssertEqual(follower.profileId, explicitProfile.id)
        XCTAssertFalse(follower.profileAssignment.hasUnsettledAssignment)
    }

    func testNonInheritingPlacementPreservesExplicitTabProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let canonicalProfileID = UUID()
        let explicitProfileID = UUID()
        let space = Space(name: "Profiled", profileId: canonicalProfileID)
        tabManager.spaceStateOwner.replaceSpaces([space])
        var offeredOverrideID: UUID?

        let tab = tabManager.spaceServices.placement.withCreationPlacement(
            preferred: space,
            inheritsSpaceProfile: false
        ) { placement in
            offeredOverrideID = placement.temporaryProfileOverrideId
            let tab = Tab(
                url: URL(fileURLWithPath: "/"),
                spaceId: placement.space.id,
                loadsCachedFaviconOnInit: false
            )
            tab.profileId = explicitProfileID
            tabManager.regularTabLifecycleOwner.addTab(tab)
            return tab
        }

        XCTAssertNil(offeredOverrideID)
        XCTAssertEqual(tab.profileId, explicitProfileID)
    }

    func testCreationInstallsTabBeforeOneCommittedBackfill() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Current")
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                currentProfileId: { profileID },
                profile: { $0 == profileID ? profile : nil }
            )
        )
        let unassigned = Space(name: "Unassigned")
        tabManager.spaceStateOwner.replaceSpaces([unassigned])

        let tab = installTab(preferred: nil, tabManager: tabManager)

        XCTAssertEqual(tab.spaceId, unassigned.id)
        XCTAssertNil(tab.profileId)
        XCTAssertEqual(unassigned.profileId, profileID)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.count, 1)
    }

    func testCreationDoesNotStampFailedOrDeferredBackfill() throws {
        let profileID = UUID()
        let failedManager = try makeInMemoryTabManager()
        let failedSpace = Space(name: "Failed")
        failedManager.spaceStateOwner.replaceSpaces([failedSpace])
        var failedDefaultProfileID: UUID?
        failedManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                defaultProfileId: { failedDefaultProfileID },
                profile: { _ in nil }
            )
        )
        failedDefaultProfileID = profileID

        let failedTab = installTab(
            preferred: failedSpace,
            tabManager: failedManager
        )
        XCTAssertNil(failedTab.profileId)
        XCTAssertNil(failedSpace.profileId)

        let deferredManager = try makeInMemoryTabManager()
        let deferredSpace = Space(name: "Deferred")
        deferredManager.spaceStateOwner.replaceSpaces([deferredSpace])
        let profile = Profile(id: profileID, name: "Deferred")
        let transition = DeferredSpaceProfileTransition()
        var deferredDefaultProfileID: UUID?
        deferredManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                defaultProfileId: { deferredDefaultProfileID },
                profile: { $0 == profileID ? profile : nil },
                webViewLifecycle: transition.makeLifecycle()
            )
        )
        deferredDefaultProfileID = profileID

        let deferredTab = installTab(
            preferred: deferredSpace,
            tabManager: deferredManager
        )
        XCTAssertNil(deferredTab.profileId)
        XCTAssertNil(deferredSpace.profileId)
        XCTAssertEqual(transition.assignmentCount, 1)
    }

    func testDeferredBackfillIncludesNewWebViewTabAndRollsBackInheritance() throws {
        let profile = Profile(name: "Target")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeInMemoryTabManager()
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                currentProfileId: { profile.id },
                defaultProfileId: { profile.id },
                profile: { $0 == profile.id ? profile : nil },
                webViewLifecycle: transition.makeLifecycle()
            )
        )
        let space = Space(name: "Unassigned")
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        let webView = WKWebView()

        let tab = installWebViewTab(
            in: space,
            webView: webView,
            tabManager: tabManager
        )

        XCTAssertEqual(transition.assignmentCount, 1)
        XCTAssertEqual(transition.intent?.tabIntents.map(\.tabID), [tab.id])
        XCTAssertNil(space.profileId)
        XCTAssertNil(tab.profileId)
        XCTAssertIdentical(tab.webViewSession.parkedWebView, webView)
        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        XCTAssertEqual(space.profileId, profile.id)

        try XCTUnwrap(transition.rollbackModel)()
        try XCTUnwrap(transition.settlement)(.rolledBack(.abort(.explicit)))

        XCTAssertNil(space.profileId)
        XCTAssertNil(tab.profileId)
        XCTAssertIdentical(tab.webViewSession.parkedWebView, webView)
    }

    func testCreationDuringPendingBackfillPinsThenRejoinsSpaceInheritance() throws {
        let pendingProfile = Profile(name: "Pending")
        let laterProfile = Profile(name: "Later")
        let profiles = [
            pendingProfile.id: pendingProfile,
            laterProfile.id: laterProfile,
        ]
        var currentProfileID = pendingProfile.id
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: profiles,
            currentProfileID: { currentProfileID },
            transition: transition
        )
        let space = Space(name: "Unassigned")
        tabManager.spaceStateOwner.replaceSpaces([space])
        let first = installWebViewTab(
            in: space,
            webView: WKWebView(),
            tabManager: tabManager
        )

        currentProfileID = laterProfile.id
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://follower.example",
            in: space,
            activate: false
        )

        XCTAssertEqual(transition.assignmentCount, 1)
        XCTAssertEqual(transition.intent?.tabIntents.map(\.tabID), [first.id])
        XCTAssertNil(first.profileId)
        XCTAssertEqual(follower.profileId, pendingProfile.id)
        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)

        XCTAssertEqual(space.profileId, pendingProfile.id)
        XCTAssertNil(first.profileId)
        XCTAssertNil(follower.profileId)

        XCTAssertEqual(
            tabManager.profileAssignments.spaces.assign(
                spaceID: space.id,
                toProfile: laterProfile.id
            ),
            .deferred
        )
        XCTAssertEqual(
            Set(transition.intent?.tabIntents.map(\.tabID) ?? []),
            Set([first.id, follower.id])
        )
    }

    func testCreationDuringStagedBackfillStaysExplicitAfterRollback() throws {
        let profile = Profile(name: "Pending")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [profile.id: profile],
            currentProfileID: { profile.id },
            transition: transition
        )
        let space = Space(name: "Unassigned")
        tabManager.spaceStateOwner.replaceSpaces([space])
        _ = installWebViewTab(
            in: space,
            webView: WKWebView(),
            tabManager: tabManager
        )
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://follower.example",
            in: space,
            activate: false
        )

        XCTAssertEqual(follower.profileId, profile.id)
        try XCTUnwrap(transition.rollbackModel)()
        try XCTUnwrap(transition.settlement)(.rolledBack(.abort(.explicit)))

        XCTAssertNil(space.profileId)
        XCTAssertEqual(follower.profileId, profile.id)
    }

    func testDeferredBackfillRejectsTabMovedOutOfItsExactSpace() throws {
        let profile = Profile(name: "Pending")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [profile.id: profile],
            currentProfileID: { profile.id },
            transition: transition
        )
        let source = Space(name: "Source")
        let destination = Space(name: "Destination")
        tabManager.spaceStateOwner.replaceSpaces([source, destination])
        let tab = installWebViewTab(
            in: source,
            webView: WKWebView(),
            tabManager: tabManager
        )

        tab.spaceId = destination.id

        XCTAssertFalse(try XCTUnwrap(transition.validateModel)())
        try XCTUnwrap(transition.settlement)(.rejected(.stale))
        XCTAssertNil(source.profileId)
        XCTAssertNil(tab.profileId)
    }

    func testPreferredSpaceIsCanonicalizedAgainstCatalog() throws {
        let tabManager = try makeInMemoryTabManager()
        let sharedID = UUID()
        let canonical = Space(id: sharedID, name: "Canonical")
        let detached = Space(id: sharedID, name: "Detached")
        let fallback = Space(name: "Fallback")
        tabManager.spaceStateOwner.replaceSpaces([canonical, fallback])
        let placementService = tabManager.spaceServices.placement
        var resolvedSpace: Space?

        _ = placementService.withCreationPlacement(
            preferred: detached,
            fallbackSpaceId: fallback.id
        ) { placement in
            resolvedSpace = placement.space
            let tab = Tab(
                url: URL(fileURLWithPath: "/"),
                spaceId: placement.space.id,
                loadsCachedFaviconOnInit: false
            )
            tab.profileId = placement.temporaryProfileOverrideId
            tabManager.regularTabLifecycleOwner.addTab(tab)
            return tab
        }

        XCTAssertIdentical(resolvedSpace, canonical)

        resolvedSpace = nil
        _ = placementService.withCreationPlacement(
            preferred: Space(name: "Deleted"),
            fallbackSpaceId: fallback.id
        ) { placement in
            resolvedSpace = placement.space
            let tab = Tab(
                url: URL(fileURLWithPath: "/"),
                spaceId: placement.space.id,
                loadsCachedFaviconOnInit: false
            )
            tab.profileId = placement.temporaryProfileOverrideId
            tabManager.regularTabLifecycleOwner.addTab(tab)
            return tab
        }

        XCTAssertIdentical(resolvedSpace, fallback)
    }

    func testPlacementCreatesDeterministicPersonalSpaceWhenCatalogIsEmpty() throws {
        let tabManager = try makeInMemoryTabManager()
        tabManager.spaceStateOwner.removeAll()
        let profileID = UUID()
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(currentProfileId: { profileID })
        )

        let tab = installTab(preferred: nil, tabManager: tabManager)
        let resolved = try XCTUnwrap(tabManager.spaceStateOwner.firstSpace)

        XCTAssertEqual(resolved.name, "Personal")
        XCTAssertEqual(resolved.profileId, profileID)
        XCTAssertTrue(resolved.workspaceTheme.visuallyEquals(.default))
        XCTAssertEqual(resolved.icon, SumiPersistentGlyph.spaceDefaultIconValue)
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, resolved)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [resolved.id])
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner
                .tabsBySpaceSnapshot()[resolved.id]?.map(\.id),
            [tab.id]
        )
        XCTAssertTrue(
            tabManager.structuralPersistence.dirtySet.dirtySpaceIds
                .contains(resolved.id)
        )
    }

    func testPlacementWithoutProfilesUsesExistingFirstSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let first = Space(name: "First")
        let second = Space(name: "Second")
        tabManager.spaceStateOwner.replaceSpaces([first, second])
        tabManager.spaceStateOwner.replaceCurrentSpace(second)
        let tab = installTab(preferred: nil, tabManager: tabManager)

        XCTAssertEqual(tab.spaceId, first.id)
    }

    private func installTab(
        preferred space: Space?,
        fallbackSpaceId: UUID? = nil,
        tabManager: TabManager
    ) -> Tab {
        tabManager.spaceServices.placement.withCreationPlacement(
            preferred: space,
            fallbackSpaceId: fallbackSpaceId
        ) { placement in
            let tab = Tab(
                url: URL(fileURLWithPath: "/"),
                spaceId: placement.space.id,
                loadsCachedFaviconOnInit: false
            )
            tab.profileId = placement.temporaryProfileOverrideId
            tabManager.regularTabLifecycleOwner.addTab(tab)
            return tab
        }
    }

    private func installWebViewTab(
        in space: Space,
        webView: WKWebView,
        tabManager: TabManager
    ) -> Tab {
        tabManager.spaceServices.placement.withCreationPlacement(
            preferred: space
        ) { placement in
            let tab = tabManager.tabFactory.makeTab(
                url: URL(string: "https://partition.example")!,
                name: "Partition",
                favicon: "globe",
                spaceId: placement.space.id,
                index: tabManager.regularTabCollectionOwner.appendIndex(
                    in: placement.space.id
                ),
                existingWebView: webView
            )
            tab.profileId = placement.temporaryProfileOverrideId
            tabManager.regularTabLifecycleOwner.addTab(tab)
            return tab
        }
    }

    private func makeDeferredTabManager(
        profiles: [UUID: Profile],
        currentProfileID: @escaping @MainActor () -> UUID?,
        transition: DeferredSpaceProfileTransition
    ) throws -> TabManager {
        let tabManager = try makeInMemoryTabManager()
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                currentProfileId: currentProfileID,
                defaultProfileId: currentProfileID,
                profile: { profiles[$0] },
                webViewLifecycle: transition.makeLifecycle()
            )
        )
        return tabManager
    }
}
