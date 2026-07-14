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

        tabManager.tabClosureService.closeAllTabsBelow(second)

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

        tabManager.tabClosureService.closeAllTabsBelow(survivor)

        XCTAssertEqual(probe.batches, [[closed.id]])
        XCTAssertEqual(structuralPublishCount, 1)
        XCTAssertNil(tabManager.splitGroupStore.group(id: group.id))
        XCTAssertNil(tabManager.regularTabCollectionOwner.tab(for: closed.id))

        let scheduledPersistence = try XCTUnwrap(
            tabManager.structuralPersistence.scheduledPersistTask
        )
        await scheduledPersistence.value

        let didPersistFinalState = try {
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
        }()
        XCTAssertTrue(didPersistFinalState)
        withExtendedLifetime(cancellable) {}
    }

    func testCloseAllBelowRequestsOneBatchCleanupAndOnePersistence() throws {
        let probe = SplitClosureBatchProbe()
        let (_, tabManager) = try makeTabManager(probe: probe)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://0.example",
            in: space,
            activate: true
        )
        let second = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://1.example",
            in: space,
            activate: false
        )
        let third = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://2.example",
            in: space,
            activate: false
        )
        var structuralPublishCount = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                structuralPublishCount += 1
            }

        tabManager.tabClosureService.closeAllTabsBelow(first)

        XCTAssertEqual(probe.batches, [[second.id, third.id]])
        XCTAssertEqual(structuralPublishCount, 1)
        XCTAssertEqual(
            tabManager.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            [first.id]
        )
        withExtendedLifetime(cancellable) {}
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
}

@MainActor
private final class SplitClosureBatchProbe {
    var batches: [Set<UUID>] = []
}

@MainActor
private final class WeakTabManagerReference {
    weak var value: TabManager?
}
