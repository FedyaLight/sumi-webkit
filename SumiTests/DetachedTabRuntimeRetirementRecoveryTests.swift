import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class DetachedTabRuntimeRetirementRecoveryTests: XCTestCase {
    func testBeginModelConflictRetainsOldGenerationUntilDrain() throws {
        let repository = WebViewSessionRepository()
        var normalDestroyCount = 0
        var drainDestroyCount = 0
        var reentrantDrainResult: Bool?
        var replacementAttachment: TabRuntimeAttachmentWitness?
        var resetRuntime: (() -> Void)?
        var reenterDrain: (() -> Bool)?
        let lifecycleCount = DetachedRetirementEventCounter()
        let runtime = TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .init(
                    canRetire: { _ in true },
                    beginCommitted: { _ in
                        XCTFail("Begin conflict reached normal commit")
                        return false
                    },
                    committedRetirementIsExact: { _ in false },
                    destroy: { _ in normalDestroyCount += 1 },
                    destroyAfterTerminalDrain: { _ in
                        drainDestroyCount += 1
                        resetRuntime?()
                        reentrantDrainResult = reenterDrain?()
                    }
                )
            )
        )
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: runtime,
            context: container.mainContext,
            webViewSessions: repository,
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let retiredWebView = WKWebView()
        let source = tabManager.tabFactory.makeTab(
            spaceId: space.id,
            existingWebView: retiredWebView,
            loadsCachedFaviconOnInit: false
        )
        tabManager.regularTabCollectionOwner.insert(source, in: space.id, at: 0)
        let replacement = tabManager.tabFactory.makeTab(
            url: URL(string: "https://foreign-durable.example")!,
            loadsCachedFaviconOnInit: false
        )
        var witnessedSourceResidence = true
        let containerRemoval = ShortcutContainerRemovalOwner(
            pinnedByProfile: { [:] },
            setPinnedTabs: { _, _ in },
            removeRegularTab: { _, _, _ in
                witnessedSourceResidence = false
                tabManager.selectionStateOwner.replaceCurrentTab(replacement)
            },
            containsRegularTab: { tab, _ in
                witnessedSourceResidence && tab === source
            },
            currentSpaceId: { space.id }
        )
        let sourceModel = try XCTUnwrap(
            DetachedTabShortcutSourceModelTransaction(
                tab: source,
                container: containerRemoval,
                membership: tabManager.tabCollectionMembershipOwner,
                selection: tabManager.selectionStateOwner
            )
        )
        let attachment = TabRuntimeAttachmentWitness(
            connection: tabManager.runtimePortConnection,
            lease: tabManager.runtimePortConnection.captureLease()
        )
        let exposure = try XCTUnwrap(DetachedTabRuntimeExposureWitness(
            tab: source,
            attachment: attachment,
            windows: tabManager.shortcutTabWindowQuery
        ))
        let terminal = try XCTUnwrap(DetachedTabTerminalRetirementPublisher(
            tab: source,
            source: sourceModel,
            exposure: exposure,
            teardown: tabManager.runtimeTeardown
        ))
        let observer = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: source,
            queue: nil
        ) { _ in lifecycleCount.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        let participant = DetachedTabRuntimeRetirementParticipant(
            source: sourceModel,
            exposure: exposure,
            terminal: terminal
        )
        let replacementRuntime = TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .accepting
            )
        )
        resetRuntime = {
            tabManager.runtimePortConnection.attach(replacementRuntime)
            replacementAttachment = TabRuntimeAttachmentWitness(
                connection: tabManager.runtimePortConnection,
                lease: tabManager.runtimePortConnection.captureLease()
            )
        }
        reenterDrain = { participant.settleTerminalDrain() }

        switch participant.stage() {
        case .requiresModelConflictCompensation:
            break
        case .staged:
            return XCTFail("Source conflict unexpectedly staged")
        case .rejected:
            return XCTFail("Source conflict lost its repository lease")
        }
        XCTAssertTrue(participant.prepareStructuralRollback())
        XCTAssertFalse(participant.confirmStructuralRollback())
        XCTAssertTrue(participant.retainsCleanupAfterModelConflict)
        XCTAssertTrue(participant.canSettleTerminalDrain())
        XCTAssertEqual(drainDestroyCount, 0)

        XCTAssertTrue(participant.settleTerminalDrain())

        XCTAssertEqual(normalDestroyCount, 0)
        XCTAssertEqual(drainDestroyCount, 1)
        XCTAssertEqual(reentrantDrainResult, true)
        XCTAssertTrue(try XCTUnwrap(replacementAttachment).isCurrent())
        XCTAssertEqual(lifecycleCount.value, 0)
        XCTAssertNil(repository.residence(of: retiredWebView))
        XCTAssertIdentical(tabManager.selectionStateOwner.currentTab, replacement)
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: source.id),
            source
        )
        XCTAssertTrue(tabManager.regularTabCollectionOwner.contains(source))
    }

    func testPostCommitTopologyDriftPreservesForeignStateAndDrainsGeneration()
        throws {
        let repository = WebViewSessionRepository()
        var normalDestroyCount = 0
        var drainDestroyCount = 0
        var canRetireCount = 0
        var beginCommittedCount = 0
        var committedExactCount = 0
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .init(
                canRetire: { _ in
                    canRetireCount += 1
                    return true
                },
                beginCommitted: { _ in
                    beginCommittedCount += 1
                    return true
                },
                committedRetirementIsExact: { _ in
                    committedExactCount += 1
                    return true
                },
                destroy: { _ in normalDestroyCount += 1 },
                destroyAfterTerminalDrain: { _ in drainDestroyCount += 1 }
            )
        )
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: TestRuntimePorts.make(webViewLifecycle: lifecycle),
            context: container.mainContext,
            webViewSessions: repository,
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let retiredWebView = WKWebView()
        let source = tabManager.tabFactory.makeTab(
            spaceId: space.id,
            existingWebView: retiredWebView,
            loadsCachedFaviconOnInit: false
        )
        tabManager.regularTabCollectionOwner.insert(source, in: space.id, at: 0)
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://post-commit-drift.example/companion",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(source.id), .regularTab(companion.id)],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        let replacement = try XCTUnwrap(group.changingLayout(to: .horizontal))
        let topology = try XCTUnwrap(
            tabManager.splitGroupMutations.prepareReplaceAll(
                expected: [group],
                with: [replacement],
                persist: false
            )
        )
        let durable = RegularTabShortcutDurableStructureParticipant(
            mutations: tabManager.structuralCollectionMutationOwner,
            topology: topology
        )
        let sourceModel = try XCTUnwrap(
            DetachedTabShortcutSourceModelTransaction(
                tab: source,
                container: tabManager.shortcutContainerRemovalOwner,
                membership: tabManager.tabCollectionMembershipOwner,
                selection: tabManager.selectionStateOwner
            )
        )
        let attachment = TabRuntimeAttachmentWitness(
            connection: tabManager.runtimePortConnection,
            lease: tabManager.runtimePortConnection.captureLease()
        )
        let exposure = try XCTUnwrap(DetachedTabRuntimeExposureWitness(
            tab: source,
            attachment: attachment,
            windows: tabManager.shortcutTabWindowQuery
        ))
        let terminal = try XCTUnwrap(DetachedTabTerminalRetirementPublisher(
            tab: source,
            source: sourceModel,
            exposure: exposure,
            teardown: tabManager.runtimeTeardown
        ))
        let retirement = DetachedTabRuntimeRetirementParticipant(
            source: sourceModel,
            exposure: exposure,
            terminal: terminal
        )

        XCTAssertTrue(durable.begin())
        guard case .staged = retirement.stage() else {
            return XCTFail("Expected exact runtime retirement stage")
        }
        XCTAssertTrue(durable.stage())
        XCTAssertTrue(retirement.claimTerminalModel())
        let foreign = try XCTUnwrap(group.changingLayout(to: .grid))
        tabManager.splitGroupStore.replaceAll(with: [foreign])
        let durableDrain = try XCTUnwrap(durable.prepareTerminalDrain())
        XCTAssertTrue(retirement.canSettleTerminalDrain())

        durable.finishTerminalDrain(durableDrain)
        XCTAssertEqual(tabManager.splitGroupStore.groups, [foreign])
        XCTAssertTrue(retirement.settleTerminalDrain())

        XCTAssertEqual(canRetireCount, 3)
        XCTAssertEqual(beginCommittedCount, 1)
        XCTAssertGreaterThanOrEqual(committedExactCount, 1)
        XCTAssertEqual(normalDestroyCount, 0)
        XCTAssertEqual(drainDestroyCount, 1)
        XCTAssertNil(repository.residence(of: retiredWebView))
        XCTAssertTrue(source.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertEqual(tabManager.splitGroupStore.groups, [foreign])
    }
}

private final class DetachedRetirementEventCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
