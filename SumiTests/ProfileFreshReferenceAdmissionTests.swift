import Combine
import Foundation
import SumiWebRuntime
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ProfileFreshReferenceAdmissionTests: XCTestCase {
    func testProfileCreationDoesNotPublishWhenCanonicalSaveFails() throws {
        let container = try makeInMemoryStartupModelContainer()
        let manager = ProfileManager(
            context: container.mainContext,
            saveContext: { _ in throw ProfileCreationSaveFailure() }
        )

        XCTAssertThrowsError(try manager.createProfile(name: "Uncommitted"))
        XCTAssertTrue(manager.profiles.isEmpty)
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<ProfileEntity>())
                .isEmpty
        )
    }

    func testProfileCreationRejectsWhileRetirementIsReserved() throws {
        let container = try makeInMemoryStartupModelContainer()
        let retiringProfile = Profile(name: "Retiring")
        let fallbackProfile = Profile(name: "Fallback")
        container.mainContext.insert(
            ProfileEntity(
                id: retiringProfile.id,
                name: retiringProfile.name,
                icon: retiringProfile.icon,
                index: 0
            )
        )
        container.mainContext.insert(
            ProfileEntity(
                id: fallbackProfile.id,
                name: fallbackProfile.name,
                icon: fallbackProfile.icon,
                index: 1
            )
        )
        try container.mainContext.save()
        let manager = ProfileManager(context: container.mainContext)
        _ = try manager.profileReferenceAdmission.reserve(
            profile: retiringProfile,
            fallbackID: fallbackProfile.id
        )

        XCTAssertThrowsError(try manager.createProfile(name: "Blocked")) {
            XCTAssertEqual(
                $0 as? ProfileReferenceAdmissionLedgerError,
                .retirementInProgress(retiringProfile.id)
            )
        }
        XCTAssertEqual(
            Set(manager.profiles.map(\.id)),
            [retiringProfile.id, fallbackProfile.id]
        )
        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<ProfileEntity>())
                .count,
            2
        )
    }

    func testReservedProfileRejectsRegularAddAndCreateBeforeAttachOrPublication()
        throws {
        let fixture = try makeTabFixture(spaceUsesRetiringProfile: false)
        let candidate = fixture.tabManager.tabFactory.makeTab(
            url: URL(string: "https://blocked-add.example")!,
            name: "Blocked",
            favicon: "globe",
            spaceId: fixture.space.id,
            index: 0
        )
        candidate.profileId = fixture.retiringProfile.id
        let owner = fixture.tabManager.regularTabLifecycleOwner

        XCTAssertFalse(owner.addTab(candidate))
        let rejectedCreate = owner.createNewTab(
            in: fixture.space,
            executionProfileID: fixture.retiringProfile.id
        )
        let rejectedPopup = owner.createPopupTab(
            in: fixture.space,
            executionProfileID: fixture.retiringProfile.id
        )

        XCTAssertNil(rejectedCreate.spaceId)
        XCTAssertNil(rejectedPopup.spaceId)
        XCTAssertNil(fixture.tabManager.tabStateStore.selection.currentTab)
        XCTAssertFalse(
            fixture.tabManager.tabCollectionMembershipOwner
                .lookupContainsExact(candidate)
        )
        XCTAssertTrue(
            fixture.tabManager.tabStateStore.regularTabs
                .allTabsSnapshot().isEmpty
        )
        XCTAssertTrue(fixture.webViewSessions.runtimeOwnedTabIDs.isEmpty)
    }

    func testRegularCreationComposesWithinOneStructuralAdmissionBatch() throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        var publications = 0
        let cancellable = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in publications += 1 }
        var created: [Tab] = []

        fixture.tabManager.structuralLookupCoordinator.withTransaction {
            created.append(
                fixture.tabManager.regularTabLifecycleOwner.createNewTab(
                    url: "https://batch-one.example",
                    in: fixture.space,
                    activate: false
                )
            )
            created.append(
                fixture.tabManager.regularTabLifecycleOwner.createNewTab(
                    url: "https://batch-two.example",
                    in: fixture.space,
                    activate: false
                )
            )
        }

        let resident = fixture.tabManager.regularTabCollectionOwner.tabs(
            in: fixture.space
        )
        XCTAssertEqual(resident.count, 2)
        XCTAssertIdentical(resident[0], created[0])
        XCTAssertIdentical(resident[1], created[1])
        XCTAssertEqual(publications, 1)
        cancellable.cancel()
    }

    func testGlanceAdoptionRejectsExclusiveMigrationWithoutMutatingPreview()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        let source = fixture.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://glance-source.example",
            in: fixture.space,
            activate: false
        )
        let previewURL = URL(string: "https://glance-preview.example")!
        let preview = Tab(url: previewURL, name: "Preview", spaceId: nil)
        preview.profileId = fixture.fallbackProfile.id
        let token = try fixture.ledger.reserve(
            profile: fixture.retiringProfile,
            fallbackID: fixture.fallbackProfile.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))
        let migrationLease = try fixture.ledger
            .beginRetirementReferenceMigration(
                to: [fixture.fallbackProfile.id]
            )

        let adopted = fixture.tabManager.regularTabLifecycleOwner
            .adoptGlanceTab(preview, sourceTab: source, in: fixture.space)

        XCTAssertNil(adopted)
        XCTAssertNil(preview.spaceId)
        XCTAssertEqual(preview.profileId, fixture.fallbackProfile.id)
        XCTAssertEqual(preview.url, previewURL)
        XCTAssertFalse(
            fixture.tabManager.tabCollectionMembershipOwner.contains(preview)
        )
        XCTAssertTrue(fixture.ledger.endReferenceMutation(migrationLease))
    }

    func testReservedProfileRejectsTransientAndAuxiliaryTabsBeforeRegistry()
        throws {
        let fixture = try makeTabFixture(spaceUsesRetiringProfile: true)

        let extensionTab = fixture.tabManager.extensionTabCommands
            .createTransient(
                url: try XCTUnwrap(URL(string: "https://blocked-extension.example")),
                in: fixture.space,
                webExtensionContextOverride: nil
            )
        let auxiliaryTab = fixture.tabManager.auxiliaryMiniWindowTabs.create(
                openerTab: nil,
                profileID: fixture.retiringProfile.id,
                urlString: "https://blocked-auxiliary.example",
                webExtensionContextOverride: nil
            )

        XCTAssertNil(extensionTab.spaceId)
        XCTAssertNil(auxiliaryTab)
        XCTAssertFalse(extensionTab.isAuxiliaryMiniWindow)
        XCTAssertTrue(
            fixture.tabManager.tabCollectionMembershipOwner.allTabs()
                .allSatisfy {
                    fixture.tabManager.tabCollectionMembershipOwner
                        .isTransientExtensionTab($0) == false
                }
        )
        XCTAssertTrue(
            fixture.tabManager.tabCollectionMembershipOwner
                .allIdentityWitnesses()
                .allSatisfy { $0.isAuxiliaryMiniWindow == false }
        )
        XCTAssertFalse(
            fixture.tabManager.tabCollectionMembershipOwner
                .lookupContainsExact(extensionTab)
        )
        XCTAssertTrue(fixture.webViewSessions.runtimeOwnedTabIDs.isEmpty)
    }

    func testReservedBootstrapProfileRejectsNilProfileSpaceBeforeInstall()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        let unassignedSpace = Space(name: "Unassigned")
        fixture.tabManager.spaceStateOwner.replaceSpaces([unassignedSpace])
        fixture.tabManager.spaceStateOwner.replaceCurrentSpace(unassignedSpace)
        _ = try fixture.ledger.reserve(
            profile: fixture.retiringProfile,
            fallbackID: fixture.fallbackProfile.id
        )
        var installCount = 0
        let dirtyBefore = fixture.tabManager.structuralPersistence.dirtySet

        let profilePolicy = ProfileAssignmentPolicy(
            runtimeConnection: fixture.tabManager.runtimePortConnection,
            spaces: fixture.tabManager.spaceStateOwner,
            membership: fixture.tabManager.tabCollectionMembershipOwner,
            transientTabs: fixture.tabManager.tabStateStore.transientTabs
        )
        let placement = TabCreationPlacementService(
            spaces: fixture.tabManager.spaceStateOwner,
            catalog: makeSpaceCatalog(in: fixture.tabManager),
            profilePolicy: profilePolicy,
            profileTransitions: fixture.tabManager.spaceProfileTransitions,
            membership: fixture.tabManager.tabCollectionMembershipOwner
        )
        let rejected = placement
            .withAdmittedCreationPlacement(
                preferred: unassignedSpace,
                bootstrapProfileId: fixture.retiringProfile.id,
                admission: { placement in
                    placement.effectiveProfileId
                        .map(fixture.ledger.isReferenceAllowed)
                        != false
                },
                install: { _ in
                    installCount += 1
                    return nil
                }
            )

        XCTAssertNil(rejected)
        XCTAssertNil(unassignedSpace.profileId)
        XCTAssertEqual(installCount, 0)
        XCTAssertTrue(
            fixture.tabManager.tabStateStore.regularTabs
                .allTabsSnapshot().isEmpty
        )
        XCTAssertEqual(
            fixture.tabManager.structuralPersistence.dirtySet,
            dirtyBefore
        )
        XCTAssertTrue(fixture.webViewSessions.runtimeOwnedTabIDs.isEmpty)
    }

    func testReservedProfileRejectsTransientPromotionBeforeRetiringMembership()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: true,
            reserveRetiringProfile: false
        )
        let tab = fixture.tabManager.extensionTabCommands
            .createTransient(
                url: try XCTUnwrap(URL(string: "https://promotion-preflight.example")),
                in: fixture.space,
                webExtensionContextOverride: nil
            )
        _ = try fixture.ledger.reserve(
            profile: fixture.retiringProfile,
            fallbackID: fixture.fallbackProfile.id
        )

        let promoted = fixture.tabManager.extensionTabCommands
            .promoteTransient(tab)

        XCTAssertFalse(promoted)
        XCTAssertTrue(
            fixture.tabManager.extensionTabCommands.containsTransient(tab)
        )
        XCTAssertTrue(
            fixture.tabManager.tabCollectionMembershipOwner
                .lookupContainsExact(tab)
        )
        XCTAssertTrue(
            fixture.tabManager.tabStateStore.regularTabs
                .allTabsSnapshot().isEmpty
        )
    }

    func testTransientPromotionKeepsAdmissionLeaseThroughRegularPublication()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: true,
            reserveRetiringProfile: false
        )
        let tab = fixture.tabManager.extensionTabCommands
            .createTransient(
                url: try XCTUnwrap(URL(string: "https://promotion-revalidation.example")),
                in: fixture.space,
                webExtensionContextOverride: nil
            )
        var reservationError: ProfileReferenceAdmissionLedgerError?
        let persistenceRevisionBefore = fixture.tabManager
            .structuralPersistence.schedulingRevision
        let cancellable = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in
                guard reservationError == nil else { return }
                do {
                    _ = try fixture.ledger.reserve(
                        profile: fixture.retiringProfile,
                        fallbackID: fixture.fallbackProfile.id
                    )
                } catch let error as ProfileReferenceAdmissionLedgerError {
                    reservationError = error
                } catch {
                    XCTFail("Unexpected reservation error: \(error)")
                }
            }

        let promoted = fixture.tabManager.extensionTabCommands
            .promoteTransient(tab)

        XCTAssertTrue(promoted)
        XCTAssertEqual(reservationError, .mutationInProgress)
        XCTAssertFalse(
            fixture.tabManager.extensionTabCommands.containsTransient(tab)
        )
        XCTAssertIdentical(
            fixture.tabManager.regularTabCollectionOwner
                .tabs(in: fixture.space).first,
            tab
        )
        XCTAssertTrue(
            fixture.tabManager.tabCollectionMembershipOwner
                .lookupContainsExact(tab)
        )
        XCTAssertGreaterThan(
            fixture.tabManager.structuralPersistence.schedulingRevision,
            persistenceRevisionBefore
        )
        cancellable.cancel()
        let token = try fixture.ledger.reserve(
            profile: fixture.retiringProfile,
            fallbackID: fixture.fallbackProfile.id
        )
        XCTAssertTrue(fixture.ledger.validate(token))
    }

    func testCrossSpacePromotionRejectsReservedSourcePinBeforePublication()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: true,
            reserveRetiringProfile: false
        )
        let destination = Space(
            name: "Destination",
            profileId: fixture.fallbackProfile.id
        )
        fixture.tabManager.spaceStateOwner.replaceSpaces([
            fixture.space,
            destination,
        ])
        fixture.runtimeAttachment.detach()
        fixture.runtimeAttachment.attach(
            TestRuntimePorts.make(
                currentProfileId: { fixture.retiringProfile.id },
                defaultProfileId: { fixture.fallbackProfile.id },
                profile: { profileID in
                    switch profileID {
                    case fixture.retiringProfile.id:
                        fixture.retiringProfile
                    case fixture.fallbackProfile.id:
                        fixture.fallbackProfile
                    default:
                        nil
                    }
                }
            )
        )
        let tab = fixture.tabManager.extensionTabCommands
            .createTransient(
                url: try XCTUnwrap(URL(string: "https://cross-space-promotion.example")),
                in: fixture.space,
                webExtensionContextOverride: nil
            )
        _ = try fixture.ledger.reserve(
            profile: fixture.retiringProfile,
            fallbackID: fixture.fallbackProfile.id
        )
        let dirtyBefore = fixture.tabManager.structuralPersistence.dirtySet

        let promoted = TransientExtensionTabPromotionTransaction(
            spaces: fixture.tabManager.spaceStateOwner,
            membership: fixture.tabManager.tabCollectionMembershipOwner,
            regularTabs: fixture.tabManager.regularTabCollectionOwner,
            persistence: fixture.tabManager.structuralPersistence,
            selection: fixture.tabManager.activeSelectionOwner
        ).promote(
                tab,
                in: destination,
                activate: false
            )

        XCTAssertFalse(promoted)
        XCTAssertNil(tab.profileId)
        XCTAssertEqual(tab.spaceId, fixture.space.id)
        XCTAssertTrue(
            fixture.tabManager.extensionTabCommands.containsTransient(tab)
        )
        XCTAssertTrue(
            fixture.tabManager.tabCollectionMembershipOwner
                .lookupContainsExact(tab)
        )
        XCTAssertTrue(
            fixture.tabManager.tabStateStore.regularTabs
                .allTabsSnapshot().isEmpty
        )
        XCTAssertEqual(
            fixture.tabManager.structuralPersistence.dirtySet,
            dirtyBefore
        )
    }

    func testReservedProfileRejectsSpaceBeforeCatalogMutation() throws {
        let fixture = try makeTabFixture(spaceUsesRetiringProfile: false)
        let spacesBefore = fixture.tabManager.spaceStateOwner.spaces.map(\.id)
        let dirtyBefore = fixture.tabManager.structuralPersistence.dirtySet
        let rejected = makeSpaceCatalog(in: fixture.tabManager)
            .createSpaceIfAdmitted(
            name: "Blocked",
            profileId: fixture.retiringProfile.id
        )

        XCTAssertEqual(
            fixture.tabManager.spaceStateOwner.spaces.map(\.id),
            spacesBefore
        )
        XCTAssertNil(rejected)
        XCTAssertEqual(
            fixture.tabManager.structuralPersistence.dirtySet,
            dirtyBefore
        )
    }

    func testSpaceCatalogLeaseRejectsReentrantReservationBeforePublication()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        fixture.tabManager.spaceStateOwner.removeAll()
        var reservationError: Error?
        let runtimeConnection = TabRuntimePortConnection(
            TestRuntimePorts.make(
                defaultProfileId: { fixture.retiringProfile.id }
            )
        )
        let changes = ObservableObjectPublisher()
        let observation = changes.sink {
            do {
                _ = try fixture.ledger.reserve(
                    profile: fixture.retiringProfile,
                    fallbackID: fixture.fallbackProfile.id
                )
            } catch {
                reservationError = error
            }
        }
        let commands = makeSpaceCatalog(
            in: fixture.tabManager,
            runtimeConnection: runtimeConnection,
            changes: changes
        )

        let created = try XCTUnwrap(
            commands.createSpaceIfAdmitted(name: "Lease protected")
        )

        XCTAssertEqual(
            reservationError as? ProfileReferenceAdmissionLedgerError,
            .mutationInProgress
        )
        XCTAssertTrue(
            fixture.ledger.isReferenceAllowed(fixture.retiringProfile.id)
        )
        XCTAssertTrue(
            fixture.tabManager.spaceStateOwner.contains(spaceId: created.id)
        )
        XCTAssertEqual(created.profileId, fixture.retiringProfile.id)
        withExtendedLifetime(observation) {}
    }

    func testPreparedPlacementKeepsAdmissionLeaseThroughFinalPublication()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        let tab = fixture.tabManager.tabFactory.makeTab(
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        let placement = try XCTUnwrap(
            fixture.tabManager.regularTabCollectionOwner.preparePlacement(
                tab,
                in: fixture.space.id,
                at: 0
            )
        )
        var reservationError: Error?

        XCTAssertTrue(placement.stage())
        XCTAssertTrue(placement.finish(publishing: {
            do {
                _ = try fixture.ledger.reserve(
                    profile: fixture.retiringProfile,
                    fallbackID: fixture.fallbackProfile.id
                )
            } catch {
                reservationError = error
            }
        }))

        XCTAssertEqual(
            reservationError as? ProfileReferenceAdmissionLedgerError,
            .mutationInProgress
        )
        let token = try fixture.ledger.reserve(
            profile: fixture.retiringProfile,
            fallbackID: fixture.fallbackProfile.id
        )
        XCTAssertTrue(fixture.ledger.validate(token))
    }

    func testProductionRegularCreationKeepsLeaseThroughCoalescedPublication()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        var reservationErrors: [ProfileReferenceAdmissionLedgerError] = []
        let cancellable = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in
                do {
                    _ = try fixture.ledger.reserve(
                        profile: fixture.retiringProfile,
                        fallbackID: fixture.fallbackProfile.id
                    )
                } catch let error as ProfileReferenceAdmissionLedgerError {
                    reservationErrors.append(error)
                } catch {
                    XCTFail("Unexpected reservation error: \(error)")
                }
            }

        let regular = fixture.tabManager.regularTabLifecycleOwner.createNewTab(
            in: fixture.space,
            activate: false,
            executionProfileID: fixture.fallbackProfile.id
        )
        let popup = fixture.tabManager.regularTabLifecycleOwner.createPopupTab(
            in: fixture.space,
            activate: false,
            executionProfileID: fixture.fallbackProfile.id
        )

        XCTAssertTrue(
            fixture.tabManager.tabCollectionMembershipOwner
                .lookupContainsExact(regular)
        )
        XCTAssertTrue(
            fixture.tabManager.tabCollectionMembershipOwner
                .lookupContainsExact(popup)
        )
        XCTAssertEqual(
            reservationErrors,
            [.mutationInProgress, .mutationInProgress]
        )
        cancellable.cancel()
        let token = try fixture.ledger.reserve(
            profile: fixture.retiringProfile,
            fallbackID: fixture.fallbackProfile.id
        )
        XCTAssertTrue(fixture.ledger.validate(token))
    }

    func testProductionCreationBootstrapsUnassignedSpaceUnderExactLease()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        let unassigned = Space(name: "Unassigned")
        fixture.tabManager.spaceStateOwner.replaceSpaces([unassigned])
        fixture.tabManager.spaceStateOwner.replaceCurrentSpace(unassigned)
        fixture.runtimeAttachment.detach()
        fixture.runtimeAttachment.attach(
            TestRuntimePorts.make(
                currentProfileId: { fixture.fallbackProfile.id },
                defaultProfileId: { fixture.fallbackProfile.id },
                profile: {
                    $0 == fixture.fallbackProfile.id
                        ? fixture.fallbackProfile
                        : nil
                }
            )
        )

        let tab = fixture.tabManager.regularTabLifecycleOwner.createNewTab(
            in: unassigned,
            activate: false
        )

        XCTAssertIdentical(
            fixture.tabManager.regularTabCollectionOwner
                .tabs(in: unassigned).first,
            tab
        )
        XCTAssertTrue(
            fixture.tabManager.tabCollectionMembershipOwner
                .lookupContainsExact(tab)
        )
        XCTAssertEqual(unassigned.profileId, fixture.fallbackProfile.id)
        XCTAssertNil(tab.profileId)
    }

    func testDivergedPlacementRollbackDoesNotPartiallyMutateOrLeakLease()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        let tab = fixture.tabManager.tabFactory.makeTab(
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        let intruder = fixture.tabManager.tabFactory.makeTab(
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        let placement = try XCTUnwrap(
            fixture.tabManager.regularTabCollectionOwner.preparePlacement(
                tab,
                in: fixture.space.id,
                at: 0
            )
        )
        XCTAssertTrue(placement.stage())
        fixture.tabManager.structuralCollectionMutationOwner.setTabs(
            [tab, intruder],
            for: fixture.space.id
        )
        let beforeRollback = fixture.tabManager.regularTabCollectionOwner
            .tabs(in: fixture.space)

        XCTAssertFalse(placement.rollback())
        XCTAssertEqual(
            fixture.tabManager.regularTabCollectionOwner
                .tabs(in: fixture.space).map(ObjectIdentifier.init),
            beforeRollback.map(ObjectIdentifier.init)
        )
        XCTAssertEqual(tab.spaceId, fixture.space.id)
        let token = try fixture.ledger.reserve(
            profile: fixture.retiringProfile,
            fallbackID: fixture.fallbackProfile.id
        )
        XCTAssertTrue(fixture.ledger.validate(token))
    }

    func testRegularPlacementRejectsSameIDSourceReplacement()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        let target = Space(
            name: "Target",
            profileId: fixture.fallbackProfile.id
        )
        fixture.tabManager.spaceStateOwner.replaceSpaces([
            fixture.space,
            target,
        ])
        let sharedID = UUID()
        let canonical = fixture.tabManager.tabFactory.makeTab(
            id: sharedID,
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        XCTAssertTrue(fixture.tabManager.regularTabCollectionOwner.insert(
            canonical,
            in: fixture.space.id,
            at: 0
        ))
        let stale = fixture.tabManager.tabFactory.makeTab(
            id: sharedID,
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )

        let placed = fixture.tabManager.regularTabCollectionOwner.place(
            stale,
            in: target.id,
            at: 0,
            removingFromSource: {
                makeShortcutRemoval(in: fixture.tabManager)
                    .removeFromCurrentContainer(stale)
            }
        )

        XCTAssertFalse(placed)
        XCTAssertIdentical(
            fixture.tabManager.regularTabCollectionOwner
                .tabs(in: fixture.space).first,
            canonical
        )
        XCTAssertTrue(
            fixture.tabManager.regularTabCollectionOwner.tabs(in: target)
                .isEmpty
        )
    }

    func testStandaloneRegularPlaceKeepsLeaseThroughStructuralPublication()
        throws {
        let fixture = try makeTabFixture(
            spaceUsesRetiringProfile: false,
            reserveRetiringProfile: false
        )
        let target = Space(
            name: "Target",
            profileId: fixture.fallbackProfile.id
        )
        fixture.tabManager.spaceStateOwner.replaceSpaces([
            fixture.space,
            target,
        ])
        let tab = fixture.tabManager.tabFactory.makeTab(
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        XCTAssertTrue(fixture.tabManager.regularTabCollectionOwner.insert(
            tab,
            in: fixture.space.id,
            at: 0
        ))
        var reservationError: ProfileReferenceAdmissionLedgerError?
        let cancellable = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in
                guard reservationError == nil else { return }
                do {
                    _ = try fixture.ledger.reserve(
                        profile: fixture.retiringProfile,
                        fallbackID: fixture.fallbackProfile.id
                    )
                } catch let error as ProfileReferenceAdmissionLedgerError {
                    reservationError = error
                } catch {
                    XCTFail("Unexpected reservation error: \(error)")
                }
            }

        XCTAssertTrue(fixture.tabManager.regularTabCollectionOwner.place(
            tab,
            in: target.id,
            at: 0,
            removingFromSource: {
                makeShortcutRemoval(in: fixture.tabManager)
                    .removeFromCurrentContainer(tab)
            }
        ))

        XCTAssertEqual(reservationError, .mutationInProgress)
        XCTAssertIdentical(
            fixture.tabManager.regularTabCollectionOwner.tabs(in: target)
                .first,
            tab
        )
        cancellable.cancel()
        let token = try fixture.ledger.reserve(
            profile: fixture.retiringProfile,
            fallbackID: fixture.fallbackProfile.id
        )
        XCTAssertTrue(fixture.ledger.validate(token))
    }

    func testReservedProfileMakesBrowserSwitchAndAuxiliaryPopupNoOps()
        async throws {
        let container = try makeInMemoryStartupModelContainer()
        let registry = WindowRegistry()
        let browser = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            )
        )
        let retiringProfile = try XCTUnwrap(browser.currentProfile)
        let fallbackProfile = try browser.profileManager.createProfile(
            name: "Fallback"
        )
        let window = BrowserWindowState()
        window.currentProfileId = fallbackProfile.id
        registry.register(window)
        registry.setActive(window)
        browser.currentProfile = fallbackProfile
        _ = try browser.profileReferenceAdmission.reserve(
            profile: retiringProfile,
            fallbackID: fallbackProfile.id
        )
        let opener = browser.tabFactory.makeTab(
            url: URL(string: "https://blocked-popup-source.example")!,
            name: "Source",
            favicon: "globe",
            spaceId: nil,
            index: 0
        )
        opener.profileId = retiringProfile.id
        let runtimeOwnedBefore = browser.webViewSessions.runtimeOwnedTabIDs

        await browser.switchToProfile(
            retiringProfile,
            context: .userInitiated,
            in: window
        )
        let popup = browser.auxiliaryWindows.popups.presentWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(
                url: URL(string: "https://blocked-popup.example")!
            ),
            windowFeatures: WKWindowFeatures(),
            openerTab: opener
        )

        XCTAssertEqual(browser.currentProfile?.id, fallbackProfile.id)
        XCTAssertEqual(window.currentProfileId, fallbackProfile.id)
        XCTAssertNil(popup)
        XCTAssertTrue(
            browser.auxiliaryWindows.sessions.sessionsSnapshot().isEmpty
        )
        XCTAssertTrue(
            browser.tabCollectionMembershipOwner.allIdentityWitnesses()
                .allSatisfy { $0.isAuxiliaryMiniWindow == false }
        )
        XCTAssertEqual(
            browser.webViewSessions.runtimeOwnedTabIDs,
            runtimeOwnedBefore
        )
    }

    func testProfileSwitchHoldsTargetMutationLeaseAcrossPublication()
        async throws {
        let container = try makeInMemoryStartupModelContainer()
        let registry = WindowRegistry()
        let browser = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            )
        )
        let previousProfile = try XCTUnwrap(browser.currentProfile)
        let targetProfile = try browser.profileManager.createProfile(name: "Target")
        let window = BrowserWindowState()
        window.currentProfileId = previousProfile.id
        registry.register(window)
        registry.setActive(window)
        var reservationError: Error?
        var observedTargetPublication = false
        let observation = browser.currentProfileAuthority.$currentProfile
            .dropFirst()
            .sink { profile in
                guard profile?.id == targetProfile.id else { return }
                observedTargetPublication = true
                do {
                    _ = try browser.profileReferenceAdmission.reserve(
                        profile: targetProfile,
                        fallbackID: previousProfile.id
                    )
                } catch {
                    reservationError = error
                }
            }

        await browser.switchToProfile(
            targetProfile,
            context: .userInitiated,
            in: window
        )
        withExtendedLifetime(observation) {}

        XCTAssertTrue(observedTargetPublication)
        XCTAssertEqual(
            reservationError as? ProfileReferenceAdmissionLedgerError,
            .mutationInProgress
        )
        XCTAssertTrue(
            browser.profileReferenceAdmission.isReferenceAllowed(
                targetProfile.id
            )
        )
        XCTAssertEqual(browser.currentProfile?.id, targetProfile.id)
        XCTAssertEqual(window.currentProfileId, targetProfile.id)
        XCTAssertEqual(browser.historyManager.currentProfileId, targetProfile.id)
    }

    func testProfileRetirementSwitchUsesExactFallbackMigrationLease()
        async throws {
        let container = try makeInMemoryStartupModelContainer()
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            )
        )
        let retiringProfile = try XCTUnwrap(browser.currentProfile)
        let fallbackProfile = try browser.profileManager.createProfile(
            name: "Fallback"
        )
        let token = try browser.profileReferenceAdmission.reserve(
            profile: retiringProfile,
            fallbackID: fallbackProfile.id
        )
        XCTAssertTrue(
            try browser.profileReferenceAdmission.beginReferenceMigration(
                token
            )
        )

        await browser.switchToProfile(
            fallbackProfile,
            context: .profileRetirement
        )

        XCTAssertEqual(browser.currentProfile?.id, fallbackProfile.id)
        XCTAssertTrue(browser.profileReferenceAdmission.validate(token))
        XCTAssertFalse(try browser.profileReferenceAdmission.cancel(token))
    }

    private func makeTabFixture(
        spaceUsesRetiringProfile: Bool,
        reserveRetiringProfile: Bool = true
    ) throws -> FreshReferenceFixture {
        let container = try makeInMemoryStartupModelContainer()
        let context = container.mainContext
        let retiringProfile = Profile(name: "Retiring")
        let fallbackProfile = Profile(name: "Fallback")
        context.insert(
            ProfileEntity(
                id: retiringProfile.id,
                name: retiringProfile.name,
                icon: retiringProfile.icon,
                index: 0
            )
        )
        context.insert(
            ProfileEntity(
                id: fallbackProfile.id,
                name: fallbackProfile.name,
                icon: fallbackProfile.icon,
                index: 1
            )
        )
        try context.save()
        let tabManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            )
        )
        let ledger = tabManager.profileReferenceAdmission
        let webViewSessions = tabManager.webViewSessions
        tabManager.profileManager.profiles = [retiringProfile, fallbackProfile]
        tabManager.currentProfile = retiringProfile
        let runtimeAttachment = tabManager.runtimePortConnection
        let space = Space(
            name: "Target",
            profileId: spaceUsesRetiringProfile
                ? retiringProfile.id
                : fallbackProfile.id
        )
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        if reserveRetiringProfile {
            _ = try ledger.reserve(
                profile: retiringProfile,
                fallbackID: fallbackProfile.id
            )
        }
        return FreshReferenceFixture(
            container: container,
            ledger: ledger,
            retiringProfile: retiringProfile,
            fallbackProfile: fallbackProfile,
            tabManager: tabManager,
            runtimeAttachment: runtimeAttachment,
            webViewSessions: webViewSessions,
            space: space
        )
    }

    private func makeSpaceCatalog(
        in browser: BrowserManager,
        runtimeConnection: TabRuntimePortConnection? = nil,
        changes: ObservableObjectPublisher? = nil
    ) -> SpaceCatalogCommands {
        let runtimeConnection = runtimeConnection
            ?? browser.runtimePortConnection
        let changes = changes ?? browser.objectWillChange
        let creation = SpaceCreationTransaction(
            transactions: browser.structuralLookupCoordinator,
            spaces: browser.spaceStateOwner,
            runtimeConnection: runtimeConnection,
            profileReferenceAdmission: browser.profileReferenceAdmission,
            committer: SpaceCreationCommitter(
                structuralMutations: browser.structuralCollectionMutationOwner,
                persistence: browser.structuralPersistence,
                changes: changes
            )
        )
        return SpaceCatalogCommands(
            transactions: browser.structuralLookupCoordinator,
            spaces: browser.spaceStateOwner,
            creation: creation,
            runtimeConnection: runtimeConnection,
            publication: SpaceCatalogMutationPublication(
                persistence: browser.structuralPersistence,
                changes: changes
            )
        )
    }

    private func makeShortcutRemoval(
        in browser: BrowserManager
    ) -> ShortcutContainerRemovalOwner {
        ShortcutContainerRemovalOwner(
            pins: browser.shortcutPinCollectionStateOwner,
            structuralMutations: browser.structuralCollectionMutationOwner,
            regularTabs: browser.regularTabCollectionOwner,
            spaces: browser.spaceStateOwner
        )
    }
}

private struct ProfileCreationSaveFailure: Error {}

@MainActor
private struct FreshReferenceFixture {
    let container: ModelContainer
    let ledger: ProfileReferenceAdmissionLedger
    let retiringProfile: Profile
    let fallbackProfile: Profile
    let tabManager: BrowserManager
    let runtimeAttachment: TabRuntimePortConnection
    let webViewSessions: WebViewSessionRepository
    let space: Space
}
