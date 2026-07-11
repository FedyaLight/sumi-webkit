import Combine
import XCTest

@testable import Sumi

@MainActor
final class ShortcutURLInsertionServiceTests: XCTestCase {
    func testOneOuterPublishContainsPinLiveTabAndFinalSelectionBeforeActivation() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileID = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Drop",
            profileId: profileID
        )
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
        let tabManager = try makeInMemoryTabManager()
        let profileID = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Drop",
            profileId: profileID
        )
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

    private func makeService(
        tabManager: TabManager,
        prepareActivation: @escaping @MainActor @Sendable (
            BrowserWindowState
        ) -> (@MainActor @Sendable (Tab) -> Void)?
    ) -> ShortcutURLInsertionService {
        ShortcutURLInsertionService(
            store: tabManager.shortcutPinStoreOwner,
            materializer: tabManager.shortcutTabMaterializer,
            structuralLookup: tabManager.structuralLookupCoordinator,
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
}

@MainActor
private final class ShortcutURLInsertionRecorder {
    var order: [String] = []
    var publishedSelections: [UUID?] = []
    weak var preparedWindow: BrowserWindowState?
    weak var activatedWindow: BrowserWindowState?
}
