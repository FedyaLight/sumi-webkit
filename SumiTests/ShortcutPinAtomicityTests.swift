import Combine
import SumiDomain
import SumiWebRuntime
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class ShortcutPinAtomicityTests: XCTestCase {
    func testInsertRejectsReservedOwnerAndExecutionProfiles() throws {
        let fixture = try makeRetirementFixture()
        let space = fixture.createSpace("Space", nil)
        _ = try fixture.context.admission.reserve(
            profile: fixture.context.profiles.retiring,
            fallbackID: fixture.context.profiles.fallback.id
        )
        let ownerPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: fixture.context.profiles.retiring.id,
            index: 0,
            launchURL: URL(string: "https://owner.example")!,
            title: "Owner"
        )
        let executionPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            executionProfileId: fixture.context.profiles.retiring.id,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://execution.example")!,
            title: "Execution"
        )

        XCTAssertNil(fixture.store.insert(ownerPin, at: 0))
        XCTAssertNil(fixture.store.insert(executionPin, at: 0))
        XCTAssertTrue(
            fixture.pins.essentialPins(for: fixture.context.profiles.retiring.id).isEmpty
        )
        XCTAssertTrue(
            fixture.pins.spacePinnedPins(for: space.id).isEmpty
        )
    }

    func testMoveRejectsReservedOwnerAndExecutionProfilesWithoutLosingSources() throws {
        let fixture = try makeRetirementFixture()
        let sourceSpace = fixture.createSpace("Source", nil)
        let targetSpace = fixture.createSpace("Target", nil)
        let executionSource = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(
                    spaceId: sourceSpace.id,
                    executionProfileId: fixture.context.profiles.retiring.id
                ),
                at: 0
            )
        )
        let ownerSource = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(spaceId: sourceSpace.id),
                at: 1
            )
        )
        _ = try fixture.context.admission.reserve(
            profile: fixture.context.profiles.retiring,
            fallbackID: fixture.context.profiles.fallback.id
        )

        XCTAssertNil(
            fixture.store.move(
                executionSource,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpace.id,
                folderId: nil,
                index: 0
            )
        )
        XCTAssertNil(
            fixture.store.move(
                ownerSource,
                to: .essential,
                profileId: fixture.context.profiles.retiring.id,
                spaceId: nil,
                folderId: nil,
                index: 0
            )
        )
        XCTAssertEqual(
            Set(
                fixture.pins
                    .spacePinnedPins(for: sourceSpace.id).map(\.id)
            ),
            [executionSource.id, ownerSource.id]
        )
        XCTAssertTrue(
            fixture.pins.spacePinnedPins(for: targetSpace.id).isEmpty
        )
    }

    func testUpdateRejectsReservedOwnerAndExecutionProfiles() throws {
        let fixture = try makeRetirementFixture()
        let space = fixture.createSpace("Space", nil)
        let ownerPin = try XCTUnwrap(
            fixture.store.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .essential,
                    profileId: fixture.context.profiles.retiring.id,
                    index: 0,
                    launchURL: URL(string: "https://owner-update.example")!,
                    title: "Owner"
                ),
                at: 0
            )
        )
        let executionPin = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(
                    spaceId: space.id,
                    executionProfileId: fixture.context.profiles.retiring.id
                ),
                at: 0
            )
        )
        _ = try fixture.context.admission.reserve(
            profile: fixture.context.profiles.retiring,
            fallbackID: fixture.context.profiles.fallback.id
        )

        XCTAssertNil(
            fixture.update(
                ownerPin,
                "Changed owner"
            )
        )
        XCTAssertNil(
            fixture.update(
                executionPin,
                "Changed execution"
            )
        )
        XCTAssertEqual(
            fixture.pins
                .shortcutPin(by: ownerPin.id)?.title,
            "Owner"
        )
        XCTAssertEqual(
            fixture.pins
                .shortcutPin(by: executionPin.id)?.title,
            "Space Pin"
        )
    }

    func testMetadataUpdateRejectsStaleSourceRevision() throws {
        let fixture = try makePinMetadataFixture()
        let space = fixture.createSpace("Space", nil)
        let source = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let current = try XCTUnwrap(
            fixture.update(
                source,
                "Current title",
                nil
            )
        )

        XCTAssertNil(
            fixture.update(
                source,
                nil,
                URL(string: "https://stale.example")!
            )
        )
        let stored = try XCTUnwrap(
            fixture.pins.shortcutPin(
                by: source.id
            )
        )
        XCTAssertEqual(stored.title, current.title)
        XCTAssertEqual(stored.launchURL, current.launchURL)
    }

    func testStructuralStoreRejectsStaleSameIDMoveSource() throws {
        let fixture = try makePinMoveFixture()
        let sourceSpace = fixture.createSpace("Source", nil)
        let targetSpace = fixture.createSpace("Target", nil)
        let source = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(spaceId: sourceSpace.id),
                at: 0
            )
        )
        let current = try XCTUnwrap(
            fixture.update(
                source,
                "Current",
                nil
            )
        )

        XCTAssertNil(
            fixture.store.move(
                source,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpace.id,
                folderId: nil,
                index: 0
            )
        )
        XCTAssertIdentical(
            fixture.pins.shortcutPin(
                by: source.id
            ),
            current
        )
        XCTAssertTrue(
            fixture.pins.spacePinnedPins(for: targetSpace.id).isEmpty
        )
    }

    func testExecutionProfileAssignmentRejectsStaleSourceRevision() throws {
        let targetProfile = Profile(name: "Target")
        let fixture = try makePinExecutionFixture(targetProfile: targetProfile)
        let space = fixture.createSpace("Space", nil)
        let source = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let current = try XCTUnwrap(
            fixture.update(
                source,
                "Current title",
                nil
            )
        )

        XCTAssertNil(
            fixture.assign(
                source,
                targetProfile.id
            )
        )
        XCTAssertNil(current.executionProfileId)
        XCTAssertIdentical(
            fixture.pins.shortcutPin(
                by: source.id
            ),
            current
        )
    }

    func testHeadlessMetadataUpdateCommitsWithoutRuntimeMutation() throws {
        let fixture = try makePinMetadataFixture()
        let space = fixture.createSpace("Space", nil)
        let source = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let targetURL = URL(string: "https://updated.example")!

        let updated = try XCTUnwrap(
            fixture.update(
                source,
                "Updated",
                targetURL
            )
        )

        XCTAssertEqual(updated.title, "Updated")
        XCTAssertEqual(updated.launchURL, targetURL)
        XCTAssertEqual(
            fixture.pins
                .shortcutPin(by: source.id)?.launchURL,
            targetURL
        )
    }

    func testMetadataUpdateRollsBackWhenLivePresentationCannotSettle() throws {
        let fixture = try makePinPresentationFixture()
        let source = fixture.source
        let liveTab = try XCTUnwrap(fixture.materialize())
        var structuralEvents = 0
        let cancellable = fixture.events
            .structureChangedPublisher.sink { structuralEvents += 1 }

        XCTAssertNil(
            fixture.update(
                source,
                "Must roll back"
            )
        )
        let stored = try XCTUnwrap(
            fixture.pins.shortcutPin(by: source.id)
        )
        XCTAssertIdentical(stored, source)
        XCTAssertEqual(stored.title, "Space Pin")
        XCTAssertEqual(liveTab.shortcutPinId, source.id)
        XCTAssertEqual(structuralEvents, 0)
        _ = cancellable
    }

    func testRemoveWithDetachedRuntimePreservesPinAndLiveRegistry() throws {
        let fixture = try makePinRemovalFixture()

        fixture.remove()

        XCTAssertNotNil(
            fixture.pins.shortcutPin(by: fixture.pin.id)
        )
        XCTAssertIdentical(
            fixture.liveTabs.tab(for: fixture.pin.id, in: fixture.windowID),
            fixture.liveTab
        )
    }

    func testHeadlessStructuralStoreCanInsertAndMoveIntoRegularFolder() throws {
        let fixture = try makePinFolderFixture()
        let space = fixture.createSpace("Space", nil)
        let folder = try XCTUnwrap(fixture.createFolder(space.id))
        let source = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let candidate = makeSpacePin(
            spaceId: space.id,
            folderId: folder.id
        )

        let inserted = try XCTUnwrap(
            fixture.store.insert(candidate, at: 0)
        )
        let currentSource = try XCTUnwrap(
            fixture.pins.shortcutPin(by: source.id)
        )
        let moved = try XCTUnwrap(
            fixture.store.move(
                currentSource,
                to: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: folder.id,
                index: 0
            )
        )

        let pins = fixture.pins.spacePinnedPins(for: space.id)
        XCTAssertEqual(Set(pins.map(\.id)), [inserted.id, moved.id])
        XCTAssertTrue(pins.allSatisfy { $0.folderId == folder.id })
    }

    func testStructuralStoreRejectsDanglingAndCrossSpaceFolderIdentity() throws {
        let fixture = try makePinFolderMutationFixture()
        let sourceSpace = fixture.createSpace("Source", nil)
        let targetSpace = fixture.createSpace("Target", nil)
        let sourceFolder = try XCTUnwrap(fixture.createFolder(sourceSpace.id))
        let source = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(spaceId: targetSpace.id),
                at: 0
            )
        )
        let crossSpace = makeSpacePin(
            spaceId: targetSpace.id,
            folderId: sourceFolder.id
        )
        let dangling = makeSpacePin(
            spaceId: targetSpace.id,
            folderId: UUID()
        )

        XCTAssertNil(fixture.store.insert(crossSpace, at: 0))
        XCTAssertNil(fixture.store.insert(dangling, at: 0))
        XCTAssertNil(
            fixture.store.insert(
                makeSpacePin(spaceId: UUID()),
                at: 0
            )
        )
        XCTAssertNil(
            fixture.move(
                source,
                targetSpace.id,
                sourceFolder.id
            )
        )
        XCTAssertEqual(
            fixture.pins.spacePinnedPins(for: targetSpace.id).map(\.id),
            [source.id]
        )
    }

    func testFullEssentialDestinationRejectsMoveWithoutLosingSource() throws {
        let fixture = try makePinEssentialMoveFixture()
        let space = fixture.createSpace("Space", nil)
        let source = try XCTUnwrap(
            fixture.store.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let profileId = UUID()
        let essentials = try (0..<EssentialsShortcutPlacementOwner.CapacityPolicy.maxItems)
            .map { index in
                ShortcutPin(
                    id: UUID(),
                    role: .essential,
                    profileId: profileId,
                    index: index,
                    launchURL: try XCTUnwrap(
                        URL(string: "https://essential-\(index).example")
                    ),
                    title: "Essential \(index)"
                )
            }
        fixture.setEssentials(essentials, profileId)

        XCTAssertNil(
            fixture.moveToEssentials(
                source,
                profileId
            )
        )
        XCTAssertNotNil(
            fixture.pins.spacePinnedPins(for: space.id)
                .first { $0.id == source.id }
        )
        XCTAssertEqual(
            fixture.pins.essentialPins(for: profileId)
                .count,
            essentials.count
        )
    }

    func testPinLiveEssentialWithoutRegistryLeaseDoesNotCreateDetachedPin() throws {
        let profileId = UUID()
        let fixture = try makePinEssentialLiveFixture(profileID: profileId)

        fixture.setEssentials()
        fixture.pinToSpace()

        XCTAssertTrue(
            fixture.pins.spacePinnedPins(for: fixture.space.id)
                .isEmpty
        )
        XCTAssertEqual(fixture.input.tab.shortcutPinId, fixture.input.source.id)
    }

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

    func testPublicConversionCommitsSelectedSplitAndPinAsOneStructuralEvent() throws {
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

        let converted = try XCTUnwrap(
            fixture.conversion.commit(
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
        )

        XCTAssertEqual(structuralEvents, 1)
        XCTAssertFalse(fixture.state().regularTabs.contains(input.tab))
        XCTAssertIdentical(
            fixture.state().liveTabs.tab(for: converted.id, in: input.window.id),
            input.tab
        )
        let convertedGroup = try XCTUnwrap(fixture.state().groups.group(id: group.id))
        XCTAssertEqual(convertedGroup.layoutKind, group.layoutKind)
        XCTAssertEqual(convertedGroup.container, group.container)
        XCTAssertFalse(convertedGroup.contains(.regularTab(input.tab.id)))
        XCTAssertEqual(
            convertedGroup.member(for: .shortcutPin(converted.id)),
            SplitMember.shortcutPin(
                converted.id,
                returnPlacement: .spacePinned(
                    spaceId: input.space.id,
                    folderId: nil,
                    index: 0
                )
            )
        )
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

    func testHeadlessConversionReplacesPersistedSplitMemberAtomically() throws {
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

        let pin = try XCTUnwrap(converted)
        XCTAssertTrue(fixture.input.tab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertFalse(fixture.state().regularTabs.contains(fixture.input.tab))
        XCTAssertNotNil(fixture.state().pins.shortcutPin(by: pin.id))
        let convertedGroup = try XCTUnwrap(
            fixture.state().groups.group(id: fixture.input.group.id)
        )
        XCTAssertFalse(convertedGroup.contains(.regularTab(fixture.input.tab.id)))
        XCTAssertTrue(convertedGroup.contains(.shortcutPin(pin.id)))
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

    private func makeSpacePin(
        spaceId: UUID,
        folderId: UUID? = nil,
        executionProfileId: UUID? = nil
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            executionProfileId: executionProfileId,
            spaceId: spaceId,
            index: 0,
            folderId: folderId,
            launchURL: URL(string: "https://space-pin.example")!,
            title: "Space Pin"
        )
    }

    private func makeRetirementFixture() throws -> RetirementFixture {
        let browser = try makeIsolatedBrowser()
        let retiringProfile = Profile(name: "Retiring")
        let fallbackProfile = Profile(name: "Fallback")
        browser.modelContext.insert(
            ProfileEntity(
                id: retiringProfile.id,
                name: retiringProfile.name,
                icon: retiringProfile.icon,
                index: 0
            )
        )
        browser.modelContext.insert(
            ProfileEntity(
                id: fallbackProfile.id,
                name: fallbackProfile.name,
                icon: fallbackProfile.icon,
                index: 1
            )
        )
        try browser.modelContext.save()
        return RetirementFixture(
            store: browser.shortcutPinStoreOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            context: .init(
                admission: browser.profileReferenceAdmission,
                profiles: .init(retiring: retiringProfile, fallback: fallbackProfile)
            ),
            createSpace: { name, profileID in
                let space = Space(
                    name: name,
                    profileId: profileID
                )
                browser.spaceStateOwner.append(space)
                return space
            },
            update: { pin, title in
                browser.sidebarPinCommands.update(
                    pin,
                    title: title ?? pin.title,
                    launchURL: pin.launchURL,
                    iconAsset: pin.iconAsset
                )
            }
        )
    }

    private func makeIsolatedBrowser() throws -> BrowserManager {
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupModelContainer()
            )
        )
        browser.startupRestoreLifecycle.markLoadFinished()
        browser.startupSessionRestoreOwner.markRestoreOfferConsumed()
        return browser
    }

    private func register(
        _ window: BrowserWindowState,
        in browser: BrowserManager
    ) {
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        XCTAssertEqual(browser.windowRegistry.register(window), .registered)
    }

    private func install(
        _ profile: Profile,
        in browser: BrowserManager
    ) throws {
        browser.modelContext.insert(ProfileEntity(
            id: profile.id,
            name: profile.name,
            icon: profile.icon,
            index: browser.profileManager.profiles.count
        ))
        try browser.modelContext.save()
        browser.profileManager.loadProfiles()
        browser.currentProfile = try XCTUnwrap(
            browser.profileManager.profiles.first { $0.id == profile.id }
        )
    }

    private func makePinMetadataFixture() throws -> PinMetadataFixture {
        let browser = try makeIsolatedBrowser()
        return PinMetadataFixture(
            store: browser.shortcutPinStoreOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            createSpace: { name, profileID in
                let space = Space(name: name, profileId: profileID)
                browser.spaceStateOwner.append(space)
                return space
            },
            update: { pin, title, launchURL in
                browser.sidebarPinCommands.update(
                    pin,
                    title: title ?? pin.title,
                    launchURL: launchURL ?? pin.launchURL,
                    iconAsset: pin.iconAsset
                )
            }
        )
    }

    private func makePinMoveFixture() throws -> PinMoveFixture {
        let browser = try makeIsolatedBrowser()
        return PinMoveFixture(
            store: browser.shortcutPinStoreOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            createSpace: { name, profileID in
                let space = Space(name: name, profileId: profileID)
                browser.spaceStateOwner.append(space)
                return space
            },
            update: { pin, title, launchURL in
                browser.sidebarPinCommands.update(
                    pin,
                    title: title ?? pin.title,
                    launchURL: launchURL ?? pin.launchURL,
                    iconAsset: pin.iconAsset
                )
            }
        )
    }

    private func makePinExecutionFixture(
        targetProfile: Profile
    ) throws -> PinExecutionFixture {
        let browser = try makeIsolatedBrowser()
        try install(targetProfile, in: browser)
        return PinExecutionFixture(
            store: browser.shortcutPinStoreOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            createSpace: { name, profileID in
                let space = Space(name: name, profileId: profileID)
                browser.spaceStateOwner.append(space)
                return space
            },
            update: { pin, title, launchURL in
                browser.sidebarPinCommands.update(
                    pin,
                    title: title ?? pin.title,
                    launchURL: launchURL ?? pin.launchURL,
                    iconAsset: pin.iconAsset
                )
            },
            assign: { pin, profileID in
                browser.shortcutExecutionProfileAssignments.assign(
                    pin,
                    toExecutionProfile: profileID
                )
            }
        )
    }

    private func makePinPresentationFixture() throws -> PinPresentationFixture {
        let browser = try makeIsolatedBrowser()
        let space = Space(
            name: "Space",
            profileId: browser.currentProfile?.id
        )
        browser.spaceStateOwner.append(space)
        let source = try XCTUnwrap(
            browser.shortcutPinStoreOwner.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let detachedRuntime = TabRuntimePortConnection()
        let targets = ShortcutTabBindingTargetMutationService(
            resolution: browser.shortcutPinRuntimeResolutionOwner,
            profiles: browser.tabProfileTransitions
        )
        let bindings = ShortcutTabBindingSynchronizer(
            presentationRefreshes: browser.liveShortcutPresentationRefreshes,
            runtimeMutations: ShortcutTabBindingRuntimeMutation(
                registry: browser.liveShortcutTabs,
                targets: targets,
                runtimeConnection: detachedRuntime,
                windowMutations: browser.shortcutWindowMutationOwner,
                structuralLookup: browser.structuralLookupCoordinator
            ),
            targets: targets
        )
        let metadata = ShortcutPinMetadataMutationService(
            pins: browser.shortcutPinCollectionStateOwner,
            bindings: bindings,
            profileAdmissions: browser.profileReferenceAdmission,
            persistence: browser.structuralPersistence,
            commitTransaction: ShortcutPinMetadataCommitTransaction(
                pins: browser.shortcutPinCollectionStateOwner,
                structuralMutations: browser.structuralCollectionMutationOwner,
                spacePinnedStructure: browser.spacePinnedStructureOwner,
                bindings: bindings
            )
        )
        return PinPresentationFixture(
            lifetime: browser,
            source: source,
            events: browser.tabStructureEventBus,
            pins: browser.shortcutPinCollectionStateOwner,
            materialize: {
                browser.shortcutTabMaterializer.materialize(
                    source,
                    in: UUID(),
                    currentSpaceId: space.id
                )
            },
            update: { pin, title in
                metadata.update(
                    pin,
                    title: title ?? pin.title,
                    launchURL: pin.launchURL,
                    iconAsset: .some(pin.iconAsset)
                )
            }
        )
    }

    private func makePinRemovalFixture() throws -> PinRemovalFixture {
        let browser = try makeIsolatedBrowser()
        let space = Space(
            name: "Space",
            profileId: browser.currentProfile?.id
        )
        browser.spaceStateOwner.append(space)
        let pin = try XCTUnwrap(
            browser.shortcutPinStoreOwner.insert(
                makeSpacePin(spaceId: space.id),
                at: 0
            )
        )
        let windowID = UUID()
        let liveTab = try XCTUnwrap(
            browser.shortcutTabMaterializer.materialize(
                pin,
                in: windowID,
                currentSpaceId: space.id
            )
        )
        let detachedRuntime = TabRuntimePortConnection()
        let retirement = ShortcutPinRetirementTransaction(
            structuralLookup: browser.structuralLookupCoordinator,
            pins: browser.shortcutPinCollectionStateOwner,
            committer: ShortcutPinRetirementCommitter(
                retirement: ShortcutLiveTabRetirementService(
                    registry: browser.liveShortcutTabs,
                    structuralLookup: browser.structuralLookupCoordinator,
                    runtimeConnection: detachedRuntime,
                    runtimeTeardown: TabRuntimeTeardownService(
                        persistence: browser.structuralPersistence,
                        membership: browser.tabCollectionMembershipOwner,
                        webViewSessions: browser.webViewSessions
                    ),
                    windowMutations: browser.shortcutWindowMutationOwner,
                    splitGroups: browser.splitGroupStore,
                    splitMutations: browser.splitGroupMutations
                ),
                runtimeConnection: detachedRuntime,
                store: browser.shortcutPinStoreOwner,
                structuralMutations: browser.structuralCollectionMutationOwner
            )
        )
        return PinRemovalFixture(
            lifetime: browser,
            pin: pin,
            liveTab: liveTab,
            windowID: windowID,
            pins: browser.shortcutPinCollectionStateOwner,
            liveTabs: browser.liveShortcutTabs,
            remove: {
                retirement.remove(pin)
            }
        )
    }

    private func makePinFolderFixture() throws -> PinFolderFixture {
        let browser = try makeIsolatedBrowser()
        return PinFolderFixture(
            store: browser.shortcutPinStoreOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            createSpace: { name, profileID in
                let space = Space(name: name, profileId: profileID)
                browser.spaceStateOwner.append(space)
                return space
            },
            createFolder: { spaceID in
                browser.sidebarFolderCommands.createFolder(
                    in: spaceID,
                    name: "Folder"
                )
            }
        )
    }

    private func makePinFolderMutationFixture() throws -> PinFolderMutationFixture {
        let browser = try makeIsolatedBrowser()
        return PinFolderMutationFixture(
            store: browser.shortcutPinStoreOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            createSpace: { name, profileID in
                let space = Space(name: name, profileId: profileID)
                browser.spaceStateOwner.append(space)
                return space
            },
            createFolder: { spaceID in
                browser.sidebarFolderCommands.createFolder(
                    in: spaceID,
                    name: "Folder"
                )
            },
            move: { pin, spaceID, folderID in
                browser.shortcutPinStoreOwner.move(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: spaceID,
                    folderId: folderID,
                    index: 0
                )
            }
        )
    }

    private func makePinEssentialMoveFixture() throws -> PinEssentialMoveFixture {
        let browser = try makeIsolatedBrowser()
        return PinEssentialMoveFixture(
            store: browser.shortcutPinStoreOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            createSpace: { name, profileID in
                let space = Space(name: name, profileId: profileID)
                browser.spaceStateOwner.append(space)
                return space
            },
            setEssentials: { pins, profileID in
                browser.structuralCollectionMutationOwner.setPinnedTabs(
                    pins,
                    for: profileID
                )
            },
            moveToEssentials: { pin, profileID in
                browser.shortcutPinStoreOwner.move(
                    pin,
                    to: .essential,
                    profileId: profileID,
                    spaceId: nil,
                    folderId: nil,
                    index: 0
                )
            }
        )
    }

    private func makePinEssentialLiveFixture(
        profileID: UUID
    ) throws -> PinEssentialLiveFixture {
        let browser = try makeIsolatedBrowser()
        let profile = Profile(id: profileID, name: "Essential")
        try install(profile, in: browser)
        let space = Space(name: "Space")
        browser.spaceStateOwner.append(space)
        let source = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        let tab = browser.tabFactory.makeTab(
            url: source.launchURL,
            name: source.title,
            spaceId: nil,
            index: 0
        )
        tab.bindToShortcutPin(source)
        return PinEssentialLiveFixture(
            space: space,
            input: .init(source: source, tab: tab),
            pins: browser.shortcutPinCollectionStateOwner,
            setEssentials: {
                browser.structuralCollectionMutationOwner
                    .setPinnedTabs([source], for: profileID)
            },
            pinToSpace: {
                browser.sidebarRegularTabShortcutCommands
                    .pinTabToSpace(tab, spaceID: space.id)
            }
        )
    }

    private func makeCrossWindowConversionFixture()
        throws -> CrossWindowConversionFixture {
        let selected = BrowserWindowState()
        let splitOnly = BrowserWindowState()
        let profile = Profile(name: "Conversion")
        let browser = try makeIsolatedBrowser()
        try install(profile, in: browser)
        let space = Space(name: "Space", profileId: profile.id)
        browser.spaceStateOwner.append(space)
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://split-conversion.example",
            in: space,
            activate: false
        )
        register(selected, in: browser)
        register(splitOnly, in: browser)
        selected.currentSpaceId = space.id
        selected.currentProfileId = space.profileId
        splitOnly.currentSpaceId = space.id
        splitOnly.currentProfileId = space.profileId
        _ = browser.selectTab(tab, in: selected)
        splitOnly.currentTabId = tab.id
        return CrossWindowConversionFixture(
            lifetime: browser,
            input: .init(
                space: space,
                tab: tab,
                selectedWindowID: selected.id,
                secondaryWindowID: splitOnly.id
            ),
            conversion: browser.regularTabShortcutConversion,
            regularTabs: browser.regularTabCollectionOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            liveTabs: browser.liveShortcutTabs
        )
    }

    private func makeSelectedSplitConversionFixture()
        throws -> SelectedSplitConversionFixture {
        let window = BrowserWindowState()
        let profile = Profile(name: "Conversion")
        let browser = try makeIsolatedBrowser()
        try install(profile, in: browser)
        let space = Space(name: "Space", profileId: profile.id)
        browser.spaceStateOwner.append(space)
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://selected-split.example",
            in: space,
            activate: false
        )
        let companion = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://split-companion.example",
            in: space,
            activate: false
        )
        register(window, in: browser)
        window.currentSpaceId = space.id
        window.currentProfileId = profile.id
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(tab.id), .regularTab(companion.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        precondition(browser.splitGroupMutations.insert(group, persist: false))
        _ = browser.selectTab(tab, in: window)
        window.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(tab.id)
        )
        return SelectedSplitConversionFixture(
            input: .init(space: space, tab: tab, window: window, group: group),
            conversion: browser.regularTabShortcutConversion,
            events: browser.tabStructureEventBus,
            state: {
                .init(
                    regularTabs: browser.regularTabCollectionOwner,
                    liveTabs: browser.liveShortcutTabs,
                    groups: browser.splitGroupStore
                )
            }
        )
    }

    private func makeHeadlessSplitConversionFixture()
        throws -> HeadlessSplitConversionFixture {
        let browser = try makeIsolatedBrowser()
        let space = Space(name: "Space")
        browser.spaceStateOwner.append(space)
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://hidden-split.example",
            in: space,
            activate: false
        )
        let companion = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://hidden-companion.example",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(tab.id), .regularTab(companion.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        precondition(browser.splitGroupMutations.insert(group, persist: false))
        return HeadlessSplitConversionFixture(
            input: .init(space: space, tab: tab, group: group),
            conversion: browser.regularTabShortcutConversion,
            state: {
                .init(
                    regularTabs: browser.regularTabCollectionOwner,
                    pins: browser.shortcutPinCollectionStateOwner,
                    groups: browser.splitGroupStore
                )
            }
        )
    }

    private func makeStaleSplitPlanFixture() throws -> StaleSplitPlanFixture {
        let window = BrowserWindowState()
        let browser = try makeIsolatedBrowser()
        let space = Space(
            name: "Space",
            profileId: browser.currentProfile?.id
        )
        browser.spaceStateOwner.append(space)
        let folder = try XCTUnwrap(
            browser.sidebarFolderCommands.createFolder(in: space.id, name: "Folder")
        )
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://stale-plan.example", in: space, activate: false
        )
        let companion = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://stale-plan.example/companion", in: space, activate: false
        )
        register(window, in: browser)
        window.currentSpaceId = space.id
        window.currentProfileId = space.profileId
        window.currentTabId = tab.id
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(tab.id), .regularTab(companion.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        precondition(browser.splitGroupMutations.insert(group, persist: false))
        return StaleSplitPlanFixture(
            input: .init(space: space, folder: folder, tab: tab, window: window, group: group),
            conversion: browser.regularTabShortcutConversion,
            splitMutations: browser.splitGroupMutations,
            events: browser.tabStructureEventBus,
            state: {
                .init(
                    regularTabs: browser.regularTabCollectionOwner,
                    pins: browser.shortcutPinCollectionStateOwner,
                    groups: browser.splitGroupStore,
                    persistedWindowIDs: browser.lastSessionWindowsStore
                        .snapshots.filter { $0.id == window.id }.map(\.id)
                )
            }
        )
    }

    private func makeWindowRepairFixture() throws -> WindowRepairFixture {
        let displayed = BrowserWindowState()
        let stale = BrowserWindowState()
        let profile = Profile(name: "Conversion")
        let oracle = WindowRepairOracle()
        let browser = try makeIsolatedBrowser()
        try install(profile, in: browser)
        let space = Space(name: "Space", profileId: profile.id)
        browser.spaceStateOwner.append(space)
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://displayed.example",
            in: space,
            activate: false
        )
        let fallback = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://fallback.example",
            in: space,
            activate: false
        )
        register(displayed, in: browser)
        register(stale, in: browser)
        displayed.currentSpaceId = space.id
        displayed.currentProfileId = profile.id
        _ = browser.selectTab(tab, in: displayed)
        stale.currentSpaceId = space.id
        stale.currentProfileId = profile.id
        stale.currentTabId = UUID()
        stale.activeTabForSpace[space.id] = tab.id
        stale.selectionHistory.recordRegularTabSelection(tab.id, in: space.id)
        return WindowRepairFixture(
            input: .init(
                stale: stale,
                space: space,
                tab: tab,
                fallback: fallback
            ),
            events: browser.tabStructureEventBus,
            oracle: oracle,
            persistedStaleSnapshot: {
                browser.lastSessionWindowsStore.snapshots
                    .first { $0.id == stale.id }?.session
            },
            prepare: {
                browser.regularTabShortcutConversion.prepare(
                    tab,
                    preferredWindowId: displayed.id
                )
            },
            commit: { preparation in
                browser.regularTabShortcutConversion.commit(
                    tab,
                    preparation: preparation,
                    destination: TabShortcutPinDestination(
                        role: .spacePinned,
                        profileId: nil,
                        spaceId: space.id,
                        folderId: nil,
                        index: 0,
                        opensFolder: false
                    )
                )?.canonicalPin
            }
        )
    }
}

@MainActor
private struct RetirementFixture {
    struct Context {
        let admission: ProfileReferenceAdmissionLedger
        let profiles: Profiles
    }

    struct Profiles {
        let retiring: Profile
        let fallback: Profile
    }

    let store: ShortcutPinStoreOwner
    let pins: ShortcutPinCollectionStateOwner
    let context: Context
    let createSpace: @MainActor (String, UUID?) -> Space
    let update: @MainActor (ShortcutPin, String?) -> ShortcutPin?
}

@MainActor
private struct PinMetadataFixture {
    let store: ShortcutPinStoreOwner
    let pins: ShortcutPinCollectionStateOwner
    let createSpace: @MainActor (String, UUID?) -> Space
    let update: @MainActor (ShortcutPin, String?, URL?) -> ShortcutPin?
}

@MainActor
private struct PinMoveFixture {
    let store: ShortcutPinStoreOwner
    let pins: ShortcutPinCollectionStateOwner
    let createSpace: @MainActor (String, UUID?) -> Space
    let update: @MainActor (ShortcutPin, String?, URL?) -> ShortcutPin?
}

@MainActor
private struct PinExecutionFixture {
    let store: ShortcutPinStoreOwner
    let pins: ShortcutPinCollectionStateOwner
    let createSpace: @MainActor (String, UUID?) -> Space
    let update: @MainActor (ShortcutPin, String?, URL?) -> ShortcutPin?
    let assign: @MainActor (ShortcutPin, UUID) -> ShortcutPin?
}

@MainActor
private struct PinPresentationFixture {
    let lifetime: BrowserManager
    let source: ShortcutPin
    let events: TabStructureEventBus
    let pins: ShortcutPinCollectionStateOwner
    let materialize: @MainActor () -> Tab?
    let update: @MainActor (ShortcutPin, String?) -> ShortcutPin?
}

@MainActor
private struct PinRemovalFixture {
    let lifetime: BrowserManager
    let pin: ShortcutPin
    let liveTab: Tab
    let windowID: UUID
    let pins: ShortcutPinCollectionStateOwner
    let liveTabs: LiveShortcutTabRegistry
    let remove: @MainActor () -> Void
}

@MainActor
private struct PinFolderFixture {
    let store: ShortcutPinStoreOwner
    let pins: ShortcutPinCollectionStateOwner
    let createSpace: @MainActor (String, UUID?) -> Space
    let createFolder: @MainActor (UUID) -> TabFolder?
}

@MainActor
private struct PinFolderMutationFixture {
    let store: ShortcutPinStoreOwner
    let pins: ShortcutPinCollectionStateOwner
    let createSpace: @MainActor (String, UUID?) -> Space
    let createFolder: @MainActor (UUID) -> TabFolder?
    let move: @MainActor (ShortcutPin, UUID, UUID?) -> ShortcutPin?
}

@MainActor
private struct PinEssentialMoveFixture {
    let store: ShortcutPinStoreOwner
    let pins: ShortcutPinCollectionStateOwner
    let createSpace: @MainActor (String, UUID?) -> Space
    let setEssentials: @MainActor ([ShortcutPin], UUID) -> Void
    let moveToEssentials: @MainActor (ShortcutPin, UUID) -> ShortcutPin?
}

@MainActor
private struct PinEssentialLiveFixture {
    struct Input {
        let source: ShortcutPin
        let tab: Tab
    }

    let space: Space
    let input: Input
    let pins: ShortcutPinCollectionStateOwner
    let setEssentials: @MainActor () -> Void
    let pinToSpace: @MainActor () -> Void
}

@MainActor
private struct CrossWindowConversionFixture {
    struct Input {
        let space: Space
        let tab: Tab
        let selectedWindowID: UUID
        let secondaryWindowID: UUID
    }

    let lifetime: BrowserManager
    let input: Input
    let conversion: RegularTabShortcutConversionService
    let regularTabs: RegularTabCollectionOwner
    let pins: ShortcutPinCollectionStateOwner
    let liveTabs: LiveShortcutTabRegistry
}

@MainActor
private struct SelectedSplitConversionFixture {
    struct Input {
        let space: Space
        let tab: Tab
        let window: BrowserWindowState
        let group: SplitGroup
    }

    struct State {
        let regularTabs: RegularTabCollectionOwner
        let liveTabs: LiveShortcutTabRegistry
        let groups: SplitGroupStore
    }

    let input: Input
    let conversion: RegularTabShortcutConversionService
    let events: TabStructureEventBus
    let state: @MainActor () -> State
}

@MainActor
private struct HeadlessSplitConversionFixture {
    struct Input {
        let space: Space
        let tab: Tab
        let group: SplitGroup
    }

    struct State {
        let regularTabs: RegularTabCollectionOwner
        let pins: ShortcutPinCollectionStateOwner
        let groups: SplitGroupStore
    }

    let input: Input
    let conversion: RegularTabShortcutConversionService
    let state: @MainActor () -> State
}

@MainActor
private struct StaleSplitPlanFixture {
    struct Input {
        let space: Space
        let folder: TabFolder
        let tab: Tab
        let window: BrowserWindowState
        let group: SplitGroup
    }

    struct State {
        let regularTabs: RegularTabCollectionOwner
        let pins: ShortcutPinCollectionStateOwner
        let groups: SplitGroupStore
        let persistedWindowIDs: [UUID]
    }

    let input: Input
    let conversion: RegularTabShortcutConversionService
    let splitMutations: SplitGroupMutationService
    let events: TabStructureEventBus
    let state: @MainActor () -> State
}

@MainActor
private struct WindowRepairFixture {
    struct Input {
        let stale: BrowserWindowState
        let space: Space
        let tab: Tab
        let fallback: Tab
    }

    let input: Input
    let events: TabStructureEventBus
    let oracle: WindowRepairOracle
    let persistedStaleSnapshot: @MainActor () -> WindowSessionSnapshot?
    let prepare: @MainActor () -> TabShortcutConversionPreparation
    let commit: @MainActor (
        TabShortcutConversionPreparation
    ) -> ShortcutPin?
}

@MainActor
private final class WindowRepairOracle {
    var structuralEvents = 0
}
