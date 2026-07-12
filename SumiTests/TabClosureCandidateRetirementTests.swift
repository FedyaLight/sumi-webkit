import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class TabClosureCandidateRetirementTests: XCTestCase {
    func testDuplicateCandidateIDsAreRetiredOnce() throws {
        let tabManager = try makeInMemoryTabManager()
        let persistence = TabClosurePersistenceSpy()
        let retirement = makeRetirement(
            tabManager: tabManager,
            persistence: persistence
        )
        let id = UUID()

        let result = retirement.retire([id, id, id])

        XCTAssertEqual(result.regularCandidates, [id])
        XCTAssertEqual(persistence.cancelledTabIDs, [id])
    }

    func testMixedLiveCandidatesUseTheirConcreteLifecycleAuthorities() throws {
        let window = BrowserWindowState()
        var auxiliaryCloseIDs: [UUID] = []
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: TestRuntimePorts.make(
                windowState: { $0 == window.id ? window : nil },
                windows: { [(window.id, window)] },
                windowStates: { [window] },
                closeAuxiliaryMiniWindow: { tab, _ in
                    auxiliaryCloseIDs.append(tab.id)
                }
            ),
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        window.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let regular = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://regular.example",
            in: space,
            activate: false
        )
        let transient = tabManager.transientWebKitTabLifecycleOwner
            .createTransientExtensionTab(
                url: "https://transient.example",
                in: space,
                webExtensionContextOverride: nil
            )
        let auxiliary = tabManager.transientWebKitTabLifecycleOwner
            .createAuxiliaryMiniWindowTab(
                openerTab: regular,
                profileId: nil,
                urlString: "https://auxiliary.example",
                webExtensionContextOverride: nil
            )
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://shortcut.example")!,
            title: "Shortcut"
        )
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: space.id)
        let shortcut = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: window.id,
            currentSpaceId: space.id
        )
        let missing = UUID()
        let persistence = TabClosurePersistenceSpy()
        let retirement = makeRetirement(
            tabManager: tabManager,
            persistence: persistence
        )

        let result = retirement.retire([
            shortcut.id,
            transient.id,
            auxiliary.id,
            regular.id,
            missing,
        ])

        XCTAssertNil(tabManager.liveShortcutTabs.entry(tabId: shortcut.id))
        XCTAssertNil(
            tabManager.transientTabRegistryOwner
                .transientExtensionTabsByID[transient.id]
        )
        XCTAssertEqual(auxiliaryCloseIDs, [auxiliary.id])
        XCTAssertEqual(result.regularCandidates, [regular.id, missing])
        XCTAssertEqual(
            persistence.cancelledTabIDs,
            [transient.id, auxiliary.id, regular.id, missing]
        )
    }

    private func makeRetirement(
        tabManager: TabManager,
        persistence: any TabClosurePersistence
    ) -> TabClosureCandidateRetirement {
        TabClosureCandidateRetirement(
            shortcutRetirement: tabManager.shortcutLiveTabRetirement,
            persistence: persistence,
            transientTabs: tabManager.transientWebKitTabLifecycleOwner
        )
    }
}

@MainActor
final class TabClosurePersistenceSpy: TabClosurePersistence {
    private(set) var cancelledTabIDs: [UUID] = []
    private(set) var scheduleCount = 0

    func cancelRuntimeStatePersistence(for tabId: UUID) {
        cancelledTabIDs.append(tabId)
    }

    func scheduleStructuralPersistence() {
        scheduleCount += 1
    }
}
