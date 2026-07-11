import Combine
import SumiDomain
import SumiWebRuntime
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabRemovalBatchTests: XCTestCase {
    func testCloseAllBelowRemovesInactiveMemberFromThreeMemberGroupOnce() throws {
        let probe = SplitClosureBatchProbe()
        let (_, tabManager) = try makeTabManager(probe: probe)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://first.example",
            in: space,
            activate: true
        )
        let second = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://second.example",
            in: space,
            activate: false
        )
        let inactive = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://inactive.example",
            in: space,
            activate: false
        )
        let group = try installGroup(
            tabs: [first, second, inactive],
            in: tabManager
        )
        var structuralPublishCount = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                structuralPublishCount += 1
            }

        tabManager.tabRemovalOwner.closeAllTabsBelow(second)

        XCTAssertEqual(probe.batches, [[inactive.id]])
        XCTAssertEqual(structuralPublishCount, 1)
        XCTAssertEqual(
            tabManager.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            [first.id, second.id]
        )
        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: group.id)?.memberIDs,
            [.regularTab(first.id), .regularTab(second.id)]
        )
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, first.id)
        withExtendedLifetime(cancellable) {}
    }

    func testCloseAllBelowDissolvesTwoMemberGroupAndPersistsNoDeadMember() async throws {
        let probe = SplitClosureBatchProbe()
        let (container, tabManager) = try makeTabManager(probe: probe)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let survivor = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://survivor.example",
            in: space,
            activate: true
        )
        let closed = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://closed.example",
            in: space,
            activate: false
        )
        let group = try installGroup(
            tabs: [survivor, closed],
            in: tabManager
        )
        let didSeedStore = await tabManager.structuralPersistence
            .persistFullReconcileAwaitingResult(reason: "batch close seed")
        XCTAssertTrue(didSeedStore)
        var structuralPublishCount = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                structuralPublishCount += 1
            }

        tabManager.tabRemovalOwner.closeAllTabsBelow(survivor)

        XCTAssertEqual(probe.batches, [[closed.id]])
        XCTAssertEqual(structuralPublishCount, 1)
        XCTAssertNil(tabManager.splitGroupStore.group(id: group.id))
        XCTAssertNil(tabManager.regularTabCollectionOwner.tab(for: closed.id))

        let didPersistFinalState = try await waitUntilPersisted {
            let context = ModelContext(container)
            let persistedTabIDs = Set(
                try context.fetch(FetchDescriptor<TabEntity>()).map(\.id)
            )
            guard persistedTabIDs.contains(survivor.id),
                  !persistedTabIDs.contains(closed.id),
                  let data = try context.fetch(
                      FetchDescriptor<TabsStateEntity>()
                  ).first?.splitGroupsData,
                  case .version2(groups: let groups, discardedEntryCount: _) =
                    try TabPersistenceCodec().decodeSplitGroupArchive(
                        from: data
                    ) else {
                return false
            }
            return groups.allSatisfy {
                !$0.contains(.regularTab(closed.id))
            }
        }
        XCTAssertTrue(didPersistFinalState)
        withExtendedLifetime(cancellable) {}
    }

    func testCloseAllBelowRequestsOneBatchCleanupAndOnePersistence() {
        let harness = RemovalDependencyHarness()
        let owner = harness.makeOwner()

        owner.closeAllTabsBelow(harness.tabs[0])

        XCTAssertEqual(harness.transactionCount, 1)
        XCTAssertEqual(harness.regularRemovalBatchCount, 1)
        XCTAssertEqual(
            harness.closedRegularTabBatches,
            [Set(harness.originalTabs.dropFirst().map(\.id))]
        )
        XCTAssertEqual(harness.persistenceRequestCount, 1)
        XCTAssertEqual(harness.tabs.map(\.id), [harness.originalTabs[0].id])
        XCTAssertEqual(
            Set(harness.capturedClosedTabIDs),
            Set(harness.originalTabs.dropFirst().map(\.id))
        )
    }

    private func makeTabManager(
        probe: SplitClosureBatchProbe
    ) throws -> (ModelContainer, TabManager) {
        let container = try makeInMemoryStartupModelContainer()
        let managerReference = WeakTabManagerReference()
        let runtime = TestRuntimePorts.make(
            handleTabClosures: { tabIDs in
                probe.batches.append(tabIDs)
                guard let tabManager = managerReference.value else { return }
                let expected = tabManager.splitGroupStore.groups
                let closedMemberIDs = Set(
                    tabIDs.map(SplitMemberID.regularTab)
                )
                let replacement = expected.compactMap { group in
                    closedMemberIDs.reduce(Optional(group)) {
                        candidate,
                        memberID in
                        guard let candidate,
                              candidate.contains(memberID) else {
                            return candidate
                        }
                        return candidate.removingMember(memberID)
                    }
                }
                guard replacement != expected else { return }
                _ = tabManager.splitGroupMutations.replaceAll(
                    expected: expected,
                    with: replacement
                )
            }
        )
        let tabManager = TabManager(
            runtimePorts: runtime,
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        managerReference.value = tabManager
        return (container, tabManager)
    }

    private func installGroup(
        tabs: [Tab],
        in tabManager: TabManager
    ) throws -> SumiDomain.SplitGroup {
        let group = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                members: tabs.map { .regularTab($0.id) },
                layoutKind: .vertical,
                container: .regularTabs(spaceId: tabs.first?.spaceId)
            )
        )
        XCTAssertTrue(
            tabManager.splitGroupMutations.insert(group, persist: false)
        )
        return group
    }

    private func waitUntilPersisted(
        attempts: Int = 40,
        condition: @escaping @MainActor () throws -> Bool
    ) async throws -> Bool {
        for _ in 0..<attempts {
            if try condition() { return true }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try condition()
    }
}

@MainActor
private final class SplitClosureBatchProbe {
    var batches: [Set<UUID>] = []
}

@MainActor
private final class WeakTabManagerReference {
    weak var value: TabManager?
}

@MainActor
private final class RemovalDependencyHarness {
    let space: Space
    let originalTabs: [Tab]
    var tabs: [Tab]
    var currentTab: Tab?
    var transactionCount = 0
    var regularRemovalBatchCount = 0
    var persistenceRequestCount = 0
    var closedRegularTabBatches: [Set<UUID>] = []
    var capturedClosedTabIDs: [UUID] = []

    init() {
        let space = Space(name: "Space")
        let tabs = (0..<3).map { index in
            Tab(
                url: URL(string: "https://\(index).example")!,
                spaceId: space.id,
                index: index,
                loadsCachedFaviconOnInit: false
            )
        }
        self.space = space
        originalTabs = tabs
        self.tabs = tabs
        currentTab = tabs[0]
    }

    func makeOwner() -> TabRemovalOwner {
        let space = self.space
        let runtime = TestRuntimePorts.make(
            handleTabClosures: { [weak self] in
                self?.closedRegularTabBatches.append($0)
            }
        )
        return TabRemovalOwner(
            dependencies: TabRemovalOwner.Dependencies(
                withStructuralUpdateTransaction: { [weak self] operation in
                    self?.transactionCount += 1
                    operation()
                },
                requireRuntimePorts: { runtime },
                cancelRuntimeStatePersistence: { _ in },
                currentTab: { [weak self] in self?.currentTab },
                replaceCurrentTab: { [weak self] in self?.currentTab = $0 },
                removeTransientExtensionTab: { _ in false },
                closeAuxiliaryMiniWindowTabIfPresent: { _ in false },
                removeRegularTabs: { [weak self] tabIDs, _, currentSpaceID in
                    guard let self else { return [] }
                    regularRemovalBatchCount += 1
                    var removals: [RegularTabCollectionOwner.Removal] = []
                    let existing = tabs
                    tabs = existing.enumerated().compactMap { index, tab in
                        guard tabIDs.contains(tab.id) else { return tab }
                        removals.append(
                            .init(
                                tab: tab,
                                spaceId: space.id,
                                indexInCurrentSpace:
                                    currentSpaceID == space.id ? index : nil
                            )
                        )
                        return nil
                    }
                    return removals
                },
                spaces: { [space] },
                currentSpace: { [space] in space },
                retireShortcutTabIfPresent: { _ in false },
                detach: { _ in },
                scheduleStructuralPersistence: { [weak self] in
                    self?.persistenceRequestCount += 1
                },
                activeEssentialTabs: { _ in [] },
                currentProfileId: { nil },
                liveSpacePinnedTabs: { _ in [] },
                regularTabs: { [weak self] _ in self?.tabs ?? [] },
                captureClosedTab: { [weak self] tab, _ in
                    self?.capturedClosedTabIDs.append(tab.id)
                },
                notifications: { nil },
                tabsBelow: { [weak self] tab in
                    guard let self,
                          let index = tabs.firstIndex(where: {
                              $0.id == tab.id
                          }) else {
                        return nil
                    }
                    return Array(tabs.dropFirst(index + 1))
                }
            )
        )
    }
}
