import Combine
import XCTest

@testable import Sumi

@MainActor
final class ShortcutURLInsertionServiceTests: XCTestCase {
    func testOneOuterPublishContainsPinLiveTabAndFinalSelectionBeforeActivation() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = makeSpace(tabManager, profileID: profileID)
        let window = BrowserWindowState()
        window.currentSpaceId = space.id
        let recorder = ShortcutURLInsertionRecorder()
        let cancellable = tabManager.tabStructureEventBus.structureChangedPublisher.sink {
            recorder.order.append("publish")
            recorder.publishedSelections.append(window.currentTabId)
        }
        let service = makeService(tabManager: tabManager) { preparedWindow in
            recorder.preparedWindow = preparedWindow
            return { tab in
                recorder.activatedWindow = preparedWindow
                recorder.order.append("activate")
                XCTAssertEqual(window.currentTabId, tab.id)
            }
        }
        recorder.order.removeAll()
        recorder.publishedSelections.removeAll()
        let revisionBefore = tabManager.structuralLookupCoordinator.mutationRevision

        let inserted = service.insert(
            URL(string: "https://atomic.example")!,
            placement: placement(space: space, profileID: profileID),
            in: window
        )

        XCTAssertTrue(inserted)
        XCTAssertEqual(recorder.order, ["publish", "activate"])
        XCTAssertEqual(tabManager.structuralLookupCoordinator.mutationRevision, revisionBefore + 1)
        let pin = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).first
        )
        let liveTab = try XCTUnwrap(tabManager.liveShortcutTabs.tab(for: pin.id, in: window.id))
        XCTAssertEqual(recorder.publishedSelections, [liveTab.id])
        XCTAssertIdentical(recorder.preparedWindow, window)
        XCTAssertIdentical(recorder.activatedWindow, window)
        XCTAssertEqual(window.currentTabId, liveTab.id)
        XCTAssertEqual(window.currentShortcutPinId, pin.id)
        withExtendedLifetime(cancellable) {}
    }

    func testFailedActivationPreflightPublishesAndMutatesNothing() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = makeSpace(tabManager, profileID: profileID)
        let window = BrowserWindowState()
        window.currentSpaceId = space.id
        var publishCount = 0
        let cancellable = tabManager.tabStructureEventBus.structureChangedPublisher.sink {
            publishCount += 1
        }
        let service = makeService(tabManager: tabManager) { _ in nil }
        publishCount = 0
        let revisionBefore = tabManager.structuralLookupCoordinator.mutationRevision

        let inserted = service.insert(
            URL(string: "https://rejected.example")!,
            placement: placement(space: space, profileID: profileID),
            in: window
        )

        XCTAssertFalse(inserted)
        XCTAssertEqual(publishCount, 0)
        XCTAssertEqual(tabManager.structuralLookupCoordinator.mutationRevision, revisionBefore)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot[window.id]?.isEmpty ?? true)
        XCTAssertNil(window.currentTabId)
        XCTAssertNil(window.currentShortcutPinId)
        withExtendedLifetime(cancellable) {}
    }

    func testLatePresentationRejectionRollsBackInsertedPinWithoutEffects() throws {
        let tabManager = BrowserManager()
        let spaceProfileID = UUID()
        let mismatchedProfileID = UUID()
        let space = makeSpace(tabManager, profileID: spaceProfileID)
        let window = BrowserWindowState()
        window.currentSpaceId = space.id
        var publishCount = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { publishCount += 1 }
        let service = makeService(tabManager: tabManager) { _ in
            { _ in /* no-op */ }
        }
        publishCount = 0
        let revision = tabManager.structuralLookupCoordinator.mutationRevision
        let dirtyBefore = tabManager.structuralPersistence.dirtySet

        let inserted = service.insert(
            URL(string: "https://late-rejection.example")!,
            placement: ShortcutURLPlacement(
                role: .essential,
                profileID: mismatchedProfileID,
                executionProfileID: nil,
                spaceID: nil,
                folderID: nil,
                index: 0,
                openTargetFolder: false
            ),
            in: window
        )

        XCTAssertFalse(inserted)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: mismatchedProfileID).isEmpty
        )
        XCTAssertTrue(tabManager.liveShortcutTabs.snapshot[window.id]?.isEmpty ?? true)
        XCTAssertNil(window.currentTabId)
        XCTAssertNil(window.currentShortcutPinId)
        XCTAssertEqual(publishCount, 0)
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            revision
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.dirtyTabIds,
            dirtyBefore.dirtyTabIds
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.dirtySpaceIds,
            dirtyBefore.dirtySpaceIds
        )
        withExtendedLifetime(cancellable) {}
    }

    func testLateActivationSettlementRejectionDoesNotSelectOrQueueActivation() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = makeSpace(tabManager, profileID: profileID)
        let window = BrowserWindowState()
        window.currentSpaceId = space.id
        let stagedTab = Tab(loadsCachedFaviconOnInit: false)
        var activationCount = 0
        let service = makeService(
            tabManager: tabManager,
            activation: LateRejectingShortcutActivation(tab: stagedTab)
        ) { _ in
            { _ in activationCount += 1 }
        }
        let revision = tabManager.structuralLookupCoordinator.mutationRevision
        let dirtyBefore = tabManager.structuralPersistence.dirtySet

        let inserted = service.insert(
            URL(string: "https://late-settlement.example")!,
            placement: placement(space: space, profileID: profileID),
            in: window
        )

        XCTAssertFalse(inserted)
        XCTAssertNil(window.currentTabId)
        XCTAssertNil(window.currentShortcutPinId)
        XCTAssertEqual(activationCount, 0)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            revision
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.dirtyTabIds,
            dirtyBefore.dirtyTabIds
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.dirtySet.dirtySpaceIds,
            dirtyBefore.dirtySpaceIds
        )
    }

    func testRejectedFolderInsertionDoesNotOpenOrPersistFolder() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = makeSpace(tabManager, profileID: profileID)
        let folder = TabFolder(name: "Folder", spaceId: space.id)
        tabManager.folderCollectionStateOwner.replaceFoldersBySpace([
            space.id: [folder],
        ])
        let window = BrowserWindowState()
        window.currentSpaceId = space.id
        let service = makeService(
            tabManager: tabManager,
            activation: LateRejectingShortcutActivation(
                tab: Tab(loadsCachedFaviconOnInit: false)
            )
        ) { _ in
            { _ in /* no-op */ }
        }
        let persistenceRevision = tabManager.structuralPersistence
            .schedulingRevision

        XCTAssertFalse(
            service.insert(
                URL(string: "https://rejected-folder.example")!,
                placement: ShortcutURLPlacement(
                    role: .spacePinned,
                    profileID: nil,
                    executionProfileID: profileID,
                    spaceID: space.id,
                    folderID: folder.id,
                    index: 0,
                    openTargetFolder: true
                ),
                in: window
            )
        )
        XCTAssertFalse(folder.isOpen)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            persistenceRevision
        )
    }

    private func makeService(
        tabManager: BrowserManager,
        activation: (any ShortcutPresentationActivating)? = nil,
        prepareActivation: @escaping @MainActor @Sendable (
            BrowserWindowState
        ) -> (@MainActor @Sendable (Tab) -> Void)?
    ) -> ShortcutURLInsertionService {
        ShortcutURLInsertionService(
            transaction: ShortcutURLInsertionTransaction(
                store: tabManager.shortcutPinStoreOwner,
                activation: activation
                    ?? tabManager.shortcutPresentationActivation,
                structuralMutations: tabManager.structuralCollectionMutationOwner,
                structuralLookup: tabManager.structuralLookupCoordinator,
                folderOpenState: tabManager.folderOpenState
            ),
            prepareActivation: prepareActivation,
            schedulePersistence: {}
        )
    }

    private func placement(
        space: Space,
        profileID: UUID
    ) -> ShortcutURLPlacement {
        ShortcutURLPlacement(
            role: .spacePinned,
            profileID: nil,
            executionProfileID: profileID,
            spaceID: space.id,
            folderID: nil,
            index: 0,
            openTargetFolder: true
        )
    }

    private func makeSpace(
        _ browser: BrowserManager,
        profileID: UUID
    ) -> Space {
        let space = Space(name: "Drop", profileId: profileID)
        browser.spaceStateOwner.append(space)
        return space
    }
}

@MainActor
private final class LateRejectingShortcutActivation:
    ShortcutPresentationActivating {
    private let tab: Tab

    init(tab: Tab) {
        self.tab = tab
    }

    func withActivation(
        _: ShortcutPin,
        in _: UUID,
        presentationSpaceID _: UUID?,
        applying downstream: (Tab) -> Bool
    ) -> Bool {
        _ = downstream(tab)
        return false
    }
}

@MainActor
private final class ShortcutURLInsertionRecorder {
    var order: [String] = []
    var publishedSelections: [UUID?] = []
    weak var preparedWindow: BrowserWindowState?
    weak var activatedWindow: BrowserWindowState?
}
