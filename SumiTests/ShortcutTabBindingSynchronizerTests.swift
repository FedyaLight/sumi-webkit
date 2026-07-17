import Combine
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class ShortcutTabBindingSynchronizerTests: XCTestCase {
    /// Ordinary binding fixtures model a real inherited profile. Tests that
    /// exercise profileless/fallback behavior pass the full shared factory
    /// explicitly and therefore bypass this narrow convenience overload.
    private func makeProfiledShortcutBrowser(
        windowState: @escaping (UUID) -> BrowserWindowState? = { _ in nil },
        windows: @escaping () -> [(UUID, BrowserWindowState)] = { [] },
        persistWindowSession: @escaping (BrowserWindowState) -> Void = { _ in }
    ) -> BrowserManager {
        let profile = Profile(name: "Shortcut Binding Test")
        let browser = BrowserManager()
        installTestRuntime(
            TestRuntimePorts.make(
                currentProfileId: { profile.id },
                defaultProfileId: { profile.id },
                profile: { $0 == profile.id ? profile : nil },
                windowState: windowState,
                windows: windows,
                persistWindowSession: persistWindowSession
            ),
            in: browser
        )
        return browser
    }

    func testRefreshMovesRuntimeBindingWithoutSwitchingBackgroundWindowSpace() throws {
        let window = BrowserWindowState()
        let tabManager = makeProfiledShortcutBrowser(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let visibleSpace = installSpace("Visible", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )!
        window.currentSpaceId = visibleSpace.id
        window.currentTabId = UUID()
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        let moved = source.moved(to: targetSpace.id)

        shortcutBindings(for: tabManager).refreshInstances(for: moved)

        XCTAssertEqual(liveTab.spaceId, targetSpace.id)
        XCTAssertEqual(window.currentSpaceId, visibleSpace.id)
        XCTAssertEqual(liveTab.shortcutPinId, moved.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .spacePinned)
    }

    func testRebindDoesNotTreatStaleShortcutMetadataAsSelection() throws {
        let window = BrowserWindowState()
        let tabManager = makeProfiledShortcutBrowser(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let visibleSpace = installSpace("Visible", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        let target = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: targetSpace.id,
            index: 0,
            launchURL: source.launchURL,
            title: source.title
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )!
        let selectedTabId = UUID()
        window.currentSpaceId = visibleSpace.id
        window.currentTabId = selectedTabId
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role

        XCTAssertTrue(
            shortcutBindings(for: tabManager).rebind(
                liveTab,
                from: source,
                to: target
            )
        )

        XCTAssertEqual(window.currentSpaceId, visibleSpace.id)
        XCTAssertEqual(window.currentTabId, selectedTabId)
        XCTAssertNil(window.currentShortcutPinId)
        XCTAssertNil(window.currentShortcutPinRole)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: target.id, in: window.id),
            liveTab
        )
    }

    func testRefreshSwitchesSpaceOnlyForSelectedLiveInstance() throws {
        let window = BrowserWindowState()
        let tabManager = makeProfiledShortcutBrowser(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )!
        window.currentSpaceId = sourceSpace.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        let moved = source.moved(to: targetSpace.id)

        shortcutBindings(for: tabManager).refreshInstances(for: moved)

        XCTAssertEqual(window.currentSpaceId, targetSpace.id)
        XCTAssertEqual(window.currentShortcutPinRole, .spacePinned)
    }

    func testUnsettledProfileRejectsRefreshAndRebindWithoutResidenceMutation()
        throws {
        let window = BrowserWindowState()
        let tabManager = makeProfiledShortcutBrowser(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        let target = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: targetSpace.id,
            index: 0,
            launchURL: source.launchURL,
            title: source.title
        )
        let liveTab = try XCTUnwrap(tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        ))
        let sourceEntry = try XCTUnwrap(
            tabManager.liveShortcutTabs.entry(containing: liveTab)
        )
        let intent = liveTab.profileAssignment.begin(
            desiredProfileID: UUID(),
            resolvedProfileID: UUID(),
            targetURL: liveTab.url,
            navigationRevision: liveTab.mainFrameLoads.currentIntent.revision,
            requiresStructuralPersistence: false
        )

        XCTAssertFalse(
            shortcutBindings(for: tabManager).refreshInstances(
                for: source.moved(to: targetSpace.id)
            )
        )
        XCTAssertNil(
            tabManager.shortcutTabMaterializer.materialize(
                source,
                in: window.id,
                currentSpaceId: sourceSpace.id
            )
        )
        XCTAssertFalse(
            shortcutBindings(for: tabManager).rebind(
                liveTab,
                from: source,
                to: target
            )
        )
        XCTAssertTrue(liveTab.profileAssignment.isCurrent(intent))
        XCTAssertEqual(liveTab.spaceId, sourceSpace.id)
        XCTAssertTrue(
            tabManager.liveShortcutTabs.entry(containing: liveTab)?
                .isIdentical(to: sourceEntry) == true
        )
        liveTab.profileAssignment.abort(intent)
    }

    func testProfilelessSpaceRefreshUsesCapturedDefaultProfile() throws {
        let window = BrowserWindowState()
        let fallbackProfile = Profile(name: "Fallback")
        let tabManager = BrowserManager()
        installTestRuntime(
            TestRuntimePorts.make(
                currentProfileId: { nil },
                defaultProfileId: { fallbackProfile.id },
                profile: { $0 == fallbackProfile.id ? fallbackProfile : nil },
                windowState: { $0 == window.id ? window : nil },
                windows: { [(window.id, window)] }
            ),
            in: tabManager
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                source,
                in: window.id,
                currentSpaceId: sourceSpace.id
            )
        )

        XCTAssertNil(liveTab.profileId)
        XCTAssertTrue(
            shortcutBindings(for: tabManager).refreshInstances(
                for: source.moved(to: targetSpace.id)
            )
        )

        XCTAssertEqual(liveTab.spaceId, targetSpace.id)
        XCTAssertNil(liveTab.profileId)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: source.id, in: window.id),
            liveTab
        )
    }

    func testProfilelessSpaceRefreshUsesCapturedCurrentProfile() throws {
        let window = BrowserWindowState()
        let fallbackProfile = Profile(name: "Fallback")
        let tabManager = BrowserManager()
        installTestRuntime(
            TestRuntimePorts.make(
                currentProfileId: { fallbackProfile.id },
                defaultProfileId: { nil },
                profile: { $0 == fallbackProfile.id ? fallbackProfile : nil },
                windowState: { $0 == window.id ? window : nil },
                windows: { [(window.id, window)] }
            ),
            in: tabManager
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                source,
                in: window.id,
                currentSpaceId: sourceSpace.id
            )
        )

        XCTAssertTrue(
            shortcutBindings(for: tabManager).refreshInstances(
                for: source.moved(to: targetSpace.id)
            )
        )

        XCTAssertEqual(liveTab.spaceId, targetSpace.id)
        XCTAssertNil(liveTab.profileId)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: source.id, in: window.id),
            liveTab
        )
    }

    func testProfilelessRefreshRejectsBeforeMutationWithoutFallbackProfile()
        throws {
        let window = BrowserWindowState()
        let fallbackProfile = Profile(name: "Fallback")
        var currentProfileID: UUID?
        var defaultProfileID: UUID?
        var persistedWindowIDs: [UUID] = []
        let tabManager = BrowserManager()
        installTestRuntime(
            TestRuntimePorts.make(
                currentProfileId: { currentProfileID },
                defaultProfileId: { defaultProfileID },
                profile: { $0 == fallbackProfile.id ? fallbackProfile : nil },
                windowState: { $0 == window.id ? window : nil },
                windows: { [(window.id, window)] },
                persistWindowSession: { persistedWindowIDs.append($0.id) }
            ),
            in: tabManager
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        currentProfileID = fallbackProfile.id
        defaultProfileID = fallbackProfile.id
        let liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                source,
                in: window.id,
                currentSpaceId: sourceSpace.id
            )
        )
        let sourceEntry = try XCTUnwrap(
            tabManager.liveShortcutTabs.entry(containing: liveTab)
        )
        let sourceWindow = window.unpublishedShortcutMutationState
        let sourceRevision = liveTab.profileAssignment.changeRevision
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        currentProfileID = nil
        defaultProfileID = nil

        XCTAssertFalse(
            shortcutBindings(for: tabManager).refreshInstances(
                for: source.moved(to: targetSpace.id)
            )
        )

        XCTAssertEqual(liveTab.spaceId, sourceSpace.id)
        XCTAssertEqual(
            liveTab.profileAssignment.changeRevision,
            sourceRevision
        )
        XCTAssertEqual(window.unpublishedShortcutMutationState, sourceWindow)
        XCTAssertTrue(
            tabManager.liveShortcutTabs.entry(containing: liveTab)?
                .isIdentical(to: sourceEntry) == true
        )
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)
        _ = cancellable
    }

    func testDuplicateRefreshAdmissionRejectsWithoutResidenceMutationOrTrap()
        throws {
        let window = BrowserWindowState()
        let tabManager = makeProfiledShortcutBrowser(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        let target = source.moved(to: targetSpace.id)
        let liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                source,
                in: window.id,
                currentSpaceId: sourceSpace.id
            )
        )
        let sourceEntry = try XCTUnwrap(
            tabManager.liveShortcutTabs.entry(containing: liveTab)
        )
        let sourceWindow = window.unpublishedShortcutMutationState
        let admitted = try XCTUnwrap(
            shortcutBindings(for: tabManager).refreshAdmission(for: target)
        )
        let change = try XCTUnwrap(admitted.changes.first)
        let duplicate = LiveShortcutPresentationRefreshAdmission(
            pin: target,
            changes: [change, change]
        )
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        XCTAssertFalse(shortcutBindings(for: tabManager).refreshInstances(
            for: target,
            admission: duplicate
        ))

        XCTAssertTrue(
            tabManager.liveShortcutTabs.entry(containing: liveTab)?
                .isIdentical(to: sourceEntry) == true
        )
        XCTAssertEqual(liveTab.spaceId, sourceSpace.id)
        XCTAssertEqual(liveTab.shortcutPinId, source.id)
        XCTAssertEqual(window.unpublishedShortcutMutationState, sourceWindow)
        XCTAssertEqual(structuralEvents, 0)
        _ = cancellable
    }

    func testProfilelessRefreshRejectsFallbackDriftBeforeModelStage() throws {
        let window = BrowserWindowState()
        let firstProfile = Profile(name: "First")
        let replacementProfile = Profile(name: "Replacement")
        let profiles = [
            firstProfile.id: firstProfile,
            replacementProfile.id: replacementProfile,
        ]
        var currentProfileID: UUID? = firstProfile.id
        var executionCount = 0
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .rejecting,
            executePreparedProfileAssignments: {
                assignments,
                binding,
                _ in
                executionCount += 1
                currentProfileID = replacementProfile.id
                let transaction =
                    PreparedProfileAssignmentBatchModelTransaction(
                        assignments: assignments,
                        binding: binding
                    )
                XCTAssertFalse(transaction.validateForStaging())
                return .rejectedUnstaged(.stale)
            }
        )
        let tabManager = BrowserManager()
        installTestRuntime(
            TestRuntimePorts.make(
                currentProfileId: { currentProfileID },
                defaultProfileId: { nil },
                profile: { profiles[$0] },
                windowState: { $0 == window.id ? window : nil },
                windows: { [(window.id, window)] },
                webViewLifecycle: lifecycle
            ),
            in: tabManager
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                source,
                in: window.id,
                currentSpaceId: sourceSpace.id
            )
        )
        let sourceEntry = try XCTUnwrap(
            tabManager.liveShortcutTabs.entry(containing: liveTab)
        )
        let sourceWindow = window.unpublishedShortcutMutationState
        let sourceRevision = liveTab.profileAssignment.changeRevision

        XCTAssertFalse(
            shortcutBindings(for: tabManager).refreshInstances(
                for: source.moved(to: targetSpace.id)
            )
        )

        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(liveTab.spaceId, sourceSpace.id)
        XCTAssertEqual(
            liveTab.profileAssignment.changeRevision,
            sourceRevision
        )
        XCTAssertEqual(window.unpublishedShortcutMutationState, sourceWindow)
        XCTAssertTrue(
            tabManager.liveShortcutTabs.entry(containing: liveTab)?
                .isIdentical(to: sourceEntry) == true
        )
    }

    func testPipelineOwnedRefreshPublishesNothingAndRollsBackExactModel()
        throws {
        let window = BrowserWindowState()
        let sourceProfile = Profile(name: "Source")
        let targetProfile = Profile(name: "Target")
        let profiles = [
            sourceProfile.id: sourceProfile,
            targetProfile.id: targetProfile,
        ]
        var pending: (any WebViewReplacementModelTransaction)?
        var inspectBeforeRepositoryStage: (() -> Void)?
        var sourceWasExactBeforeRepositoryStage = false
        var persistedWindowIDs: [UUID] = []
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .rejecting,
            executePreparedProfileAssignments: {
                assignments,
                binding,
                _ in
                inspectBeforeRepositoryStage?()
                let transaction = PreparedProfileAssignmentBatchModelTransaction(
                    assignments: assignments,
                    binding: binding
                )
                guard transaction.validateForStaging() else {
                    return .rejectedUnstaged(.stale)
                }
                do { try transaction.stage() } catch {
                    return .rejectedSettled
                }
                pending = transaction
                return .pipelineOwned
            }
        )
        let tabManager = BrowserManager()
        installTestRuntime(
            TestRuntimePorts.make(
                currentProfileId: { sourceProfile.id },
                defaultProfileId: { sourceProfile.id },
                profile: { profiles[$0] },
                windowState: { $0 == window.id ? window : nil },
                windows: { [(window.id, window)] },
                webViewLifecycle: lifecycle,
                persistWindowSession: { persistedWindowIDs.append($0.id) }
            ),
            in: tabManager
        )
        let sourceSpace = installSpace(
            "Source",
            profileID: sourceProfile.id,
            in: tabManager
        )
        let targetSpace = installSpace(
            "Target",
            profileID: targetProfile.id,
            in: tabManager
        )
        let source = makePin(spaceId: sourceSpace.id)
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([source], for: sourceSpace.id)
        let liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                source,
                in: window.id,
                currentSpaceId: sourceSpace.id
            )
        )
        let sourceEntry = try XCTUnwrap(
            tabManager.liveShortcutTabs.entry(containing: liveTab)
        )
        window.currentSpaceId = sourceSpace.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        inspectBeforeRepositoryStage = {
            sourceWasExactBeforeRepositoryStage =
                tabManager.liveShortcutTabs.entry(containing: liveTab)?
                    .isIdentical(to: sourceEntry) == true
                && liveTab.spaceId == sourceSpace.id
                && liveTab.shortcutPinId == source.id
                && window.currentSpaceId == sourceSpace.id
                && window.currentShortcutPinId == source.id
        }

        XCTAssertTrue(
            shortcutBindings(for: tabManager).refreshInstances(
                for: source.moved(to: targetSpace.id)
            )
        )

        XCTAssertNotNil(pending)
        XCTAssertTrue(sourceWasExactBeforeRepositoryStage)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)

        let transaction = try XCTUnwrap(pending)
        try transaction.rollback()
        transaction.publishRollback()

        XCTAssertTrue(
            tabManager.liveShortcutTabs.entry(containing: liveTab)?
                .isIdentical(to: sourceEntry) == true
        )
        XCTAssertEqual(liveTab.spaceId, sourceSpace.id)
        XCTAssertNil(liveTab.profileId)
        XCTAssertEqual(window.currentSpaceId, sourceSpace.id)
        XCTAssertEqual(window.currentShortcutPinId, source.id)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)
        _ = cancellable
    }

    func testRebindRekeysExactInstanceAndRepairsSelectionMetadata() throws {
        let window = BrowserWindowState()
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Space")
        let tabManager = BrowserManager()
        installTestRuntime(
            TestRuntimePorts.make(
                currentProfileId: { profileID },
                defaultProfileId: { profileID },
                profile: { $0 == profileID ? profile : nil },
                windowState: { $0 == window.id ? window : nil },
                windows: { [(window.id, window)] }
            ),
            in: tabManager
        )
        let space = installSpace("Space", profileID: profileID, in: tabManager)
        let source = makePin(spaceId: space.id)
        let target = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: source.launchURL,
            title: source.title
        )
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([source], for: space.id)
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            [target],
            for: profileID
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: space.id
        )!
        window.currentSpaceId = space.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        window.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(source.id),
        ]

        XCTAssertTrue(
            shortcutBindings(for: tabManager).rebind(
                liveTab,
                from: source,
                to: target
            )
        )

        XCTAssertNil(tabManager.liveShortcutTabs.tab(for: source.id, in: window.id))
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: target.id, in: window.id),
            liveTab
        )
        XCTAssertEqual(window.currentShortcutPinId, target.id)
        XCTAssertEqual(window.currentShortcutPinRole, .essential)
        XCTAssertNil(liveTab.spaceId)
        XCTAssertNil(liveTab.folderId)
        XCTAssertEqual(
            window.selectionHistory.recentSelectionItemsBySpace[space.id],
            [.shortcutPin(target.id)]
        )
    }

    func testHistoryOnlyRefreshDoesNotPersistWindowSession() throws {
        let window = BrowserWindowState()
        var persistedWindowIds: [UUID] = []
        let tabManager = makeProfiledShortcutBrowser(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        _ = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )!
        window.currentSpaceId = sourceSpace.id
        window.currentTabId = UUID()
        window.selectionHistory.recentSelectionItemsBySpace[sourceSpace.id] = [
            .shortcutPin(source.id),
        ]

        shortcutBindings(for: tabManager).refreshInstances(
            for: source.moved(to: targetSpace.id)
        )

        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertNil(
            window.selectionHistory.recentSelectionItemsBySpace[sourceSpace.id]
        )
        XCTAssertEqual(
            window.selectionHistory.recentSelectionItemsBySpace[targetSpace.id],
            [.shortcutPin(source.id)]
        )
    }

    func testPreparedRefreshRejectsWindowDriftWithoutMutatingResidence() throws {
        let window = BrowserWindowState()
        var persistedWindowIDs: [UUID] = []
        let tabManager = makeProfiledShortcutBrowser(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            persistWindowSession: { persistedWindowIDs.append($0.id) }
        )
        let sourceSpace = installSpace("Source", in: tabManager)
        let targetSpace = installSpace("Target", in: tabManager)
        let source = makePin(spaceId: sourceSpace.id)
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([source], for: sourceSpace.id)
        let liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                source,
                in: window.id,
                currentSpaceId: sourceSpace.id
            )
        )
        window.currentSpaceId = sourceSpace.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        let transaction = ShortcutSplitLauncherMoveTransaction(
            batches: ShortcutSplitLauncherMoveBatchStaging(
                catalog: ShortcutSplitLauncherCatalogTransaction(
                    pinStore: tabManager.shortcutPinStoreOwner,
                    pins: tabManager.shortcutPinCollectionStateOwner
                ),
                bindingStaging: makeBindingStaging(tabManager: tabManager),
                residenceMutations: tabManager.liveShortcutTabs.staging,
                structuralMutations: tabManager.structuralCollectionMutationOwner,
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            windowMutations: tabManager.shortcutWindowMutationOwner,
            folderOpenState: tabManager.folderOpenState
        )
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let profileRevision = liveTab.profileAssignment.changeRevision

        let mutation = try XCTUnwrap(
            transaction.stage([
                PreparedShortcutSplitLauncherRestoration(
                    pin: source,
                    destination: ShortcutSplitLauncherDestination(
                        role: .spacePinned,
                        profileId: nil,
                        spaceId: targetSpace.id,
                        folderId: nil,
                        index: 0
                    )
                ),
            ])
        )

        XCTAssertEqual(
            tabManager.liveShortcutTabs.entry(containing: liveTab)?
                .presentationPage.page.spaceID,
            sourceSpace.id
        )
        XCTAssertEqual(liveTab.spaceId, sourceSpace.id)
        XCTAssertEqual(window.currentSpaceId, sourceSpace.id)
        XCTAssertEqual(liveTab.profileAssignment.changeRevision, profileRevision)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)

        let foreignTabID = UUID()
        window.currentTabId = foreignTabID

        XCTAssertFalse(mutation.isCurrent())
        XCTAssertTrue(mutation.rollback())
        XCTAssertEqual(
            tabManager.liveShortcutTabs.entry(containing: liveTab)?
                .presentationPage.page.spaceID,
            sourceSpace.id
        )
        XCTAssertEqual(window.currentTabId, foreignTabID)
        XCTAssertEqual(liveTab.spaceId, sourceSpace.id)
        XCTAssertEqual(liveTab.profileAssignment.changeRevision, profileRevision)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)
        _ = cancellable
    }

    func testLauncherBatchCapacityRaceRestoresRawCatalogAndResidences() throws {
        let window = BrowserWindowState()
        var persistedWindowIDs: [UUID] = []
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Source")
        let tabManager = BrowserManager()
        installTestRuntime(
            TestRuntimePorts.make(
                currentProfileId: { profileID },
                defaultProfileId: { profileID },
                profile: { $0 == profileID ? profile : nil },
                windowState: { $0 == window.id ? window : nil },
                windows: { [(window.id, window)] },
                persistWindowSession: { persistedWindowIDs.append($0.id) }
            ),
            in: tabManager
        )
        let space = installSpace("Source", profileID: profileID, in: tabManager)
        let firstID = UUID()
        let secondID = UUID()
        for (id, index) in [(firstID, 0), (secondID, 1)] {
            _ = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: id,
                    role: .spacePinned,
                    spaceId: space.id,
                    index: index,
                    launchURL: URL(string: "https://batch-\(index).example")!,
                    title: "Batch \(index)"
                ),
                at: index
            ))
        }
        let first = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: firstID)
        )
        let second = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: secondID)
        )
        let firstTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                first,
                in: window.id,
                currentSpaceId: space.id
            )
        )
        let secondTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                second,
                in: window.id,
                currentSpaceId: space.id
            )
        )
        let sourceWindow = window.unpublishedShortcutMutationState
        let sourceFirstRevision = firstTab.profileAssignment.changeRevision
        let sourceSecondRevision = secondTab.profileAssignment.changeRevision
        let essentials = (0..<(EssentialsShortcutPlacementOwner.CapacityPolicy.maxItems - 1))
            .map { index in
                ShortcutPin(
                    id: UUID(),
                    role: .essential,
                    profileId: profileID,
                    index: index,
                    launchURL: URL(string: "https://full-\(index).example")!,
                    title: "Full \(index)"
                )
            }
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            essentials,
            for: profileID
        )
        let batches = ShortcutSplitLauncherMoveBatchStaging(
            catalog: ShortcutSplitLauncherCatalogTransaction(
                pinStore: tabManager.shortcutPinStoreOwner,
                pins: tabManager.shortcutPinCollectionStateOwner
            ),
            bindingStaging: makeBindingStaging(tabManager: tabManager),
            residenceMutations: tabManager.liveShortcutTabs.staging,
            structuralMutations: tabManager.structuralCollectionMutationOwner,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        let transaction = ShortcutSplitLauncherMoveTransaction(
            batches: batches,
            windowMutations: tabManager.shortcutWindowMutationOwner,
            folderOpenState: tabManager.folderOpenState
        )
        let destination = ShortcutSplitLauncherDestination(
            role: .essential,
            profileId: profileID,
            spaceId: nil,
            folderId: nil,
            index: essentials.count
        )
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let mutation = try XCTUnwrap(transaction.stage([
            PreparedShortcutSplitLauncherRestoration(
                pin: first,
                destination: destination
            ),
            PreparedShortcutSplitLauncherRestoration(
                pin: second,
                destination: destination
            ),
        ]))
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: firstID),
            first
        )
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: secondID),
            second
        )

        XCTAssertFalse(mutation.settleModel())
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: firstID),
            first
        )
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: secondID),
            second
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: firstID, in: window.id),
            firstTab
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: secondID, in: window.id),
            secondTab
        )
        XCTAssertEqual(window.unpublishedShortcutMutationState, sourceWindow)
        XCTAssertGreaterThan(
            firstTab.profileAssignment.changeRevision,
            sourceFirstRevision
        )
        XCTAssertGreaterThan(
            secondTab.profileAssignment.changeRevision,
            sourceSecondRevision
        )
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)
        _ = cancellable
    }

    func testLauncherBatchExecutesAllProfilesBeforeAnyWindowPersistence() throws {
        let window = BrowserWindowState()
        let sourceProfile = Profile(name: "Source")
        let targetProfile = Profile(name: "Target")
        let profiles = [
            sourceProfile.id: sourceProfile,
            targetProfile.id: targetProfile,
        ]
        var profileExecutions = 0
        var profileCountsAtPersistence: [Int] = []
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .rejecting,
            executePreparedProfileAssignments: {
                assignments,
                binding,
                settlement in
                profileExecutions += assignments.count
                let model = PreparedProfileAssignmentBatchModelTransaction(
                    assignments: assignments,
                    binding: binding
                )
                guard model.validateForStaging() else {
                    return .rejectedUnstaged(.stale)
                }
                let outcome = ProfileTransitionModelOnlySettlement
                    .execute(.transaction(model))
                settlement(outcome.settlement)
                return outcome.batchExecution
            }
        )
        let tabManager = BrowserManager()
        installTestRuntime(
            TestRuntimePorts.make(
                currentProfileId: { sourceProfile.id },
                defaultProfileId: { sourceProfile.id },
                profile: { profiles[$0] },
                windowState: { $0 == window.id ? window : nil },
                windows: { [(window.id, window)] },
                webViewLifecycle: lifecycle,
                persistWindowSession: { _ in
                    profileCountsAtPersistence.append(profileExecutions)
                }
            ),
            in: tabManager
        )
        let sourceSpaces = (0..<2).map { index in
            installSpace(
                "Source \(index)",
                profileID: sourceProfile.id,
                in: tabManager
            )
        }
        let targetSpace = installSpace(
            "Target",
            profileID: targetProfile.id,
            in: tabManager
        )
        let pins = sourceSpaces.enumerated().map { index, space in
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: 0,
                launchURL: URL(string: "https://ordered-\(index).example")!,
                title: "Ordered \(index)"
            )
        }.compactMap { pin in
            tabManager.shortcutPinStoreOwner.insert(pin, at: pin.index)
        }
        XCTAssertEqual(pins.count, 2)
        let tabs = try zip(pins, sourceSpaces).map { pin, sourceSpace in
            try XCTUnwrap(tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: window.id,
                currentSpaceId: sourceSpace.id
            ))
        }
        window.currentSpaceId = sourceSpaces[0].id
        window.currentTabId = tabs[0].id
        window.currentShortcutPinId = pins[0].id
        window.currentShortcutPinRole = pins[0].role

        let batches = ShortcutSplitLauncherMoveBatchStaging(
            catalog: ShortcutSplitLauncherCatalogTransaction(
                pinStore: tabManager.shortcutPinStoreOwner,
                pins: tabManager.shortcutPinCollectionStateOwner
            ),
            bindingStaging: makeBindingStaging(tabManager: tabManager),
            residenceMutations: tabManager.liveShortcutTabs.staging,
            structuralMutations: tabManager.structuralCollectionMutationOwner,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        let transaction = ShortcutSplitLauncherMoveTransaction(
            batches: batches,
            windowMutations: tabManager.shortcutWindowMutationOwner,
            folderOpenState: tabManager.folderOpenState
        )
        let restorations = zip(pins, pins.indices).map { pin, index in
            PreparedShortcutSplitLauncherRestoration(
                pin: pin,
                destination: ShortcutSplitLauncherDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpace.id,
                    folderId: nil,
                    index: index
                )
            )
        }
        XCTAssertTrue(restorations.allSatisfy {
            transaction.accepts($0.pin, destination: $0.destination)
        })
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let mutation = try XCTUnwrap(transaction.stage(restorations))

        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(mutation.settleModel())
        XCTAssertEqual(structuralEvents, 1)
        XCTAssertEqual(tabs.map(\.profileId), [nil, nil])
        XCTAssertEqual(profileExecutions, 2)
        XCTAssertEqual(profileCountsAtPersistence, [2])

        mutation.commit()

        XCTAssertEqual(profileExecutions, 2)
        XCTAssertEqual(profileCountsAtPersistence, [2])
        XCTAssertEqual(structuralEvents, 1)
        _ = cancellable
    }

    func testResidenceTerminalDrainRejectsBeforeAbandoningAnyParticipant() {
        let first = TerminalDrainResidenceParticipant(canAbandon: true)
        let rejecting = TerminalDrainResidenceParticipant(canAbandon: false)
        let aggregate = ShortcutTabBindingResidenceCompositeTransaction([
            first,
            rejecting,
        ])

        XCTAssertFalse(aggregate.canAbandonForTerminalDrain())
        XCTAssertEqual(first.abandonCount, 0)
        XCTAssertEqual(rejecting.abandonCount, 0)
    }

    func testRetainedLauncherFailureSealsStructuralOwnerWithoutPublishing()
        throws {
        let tabManager = makeProfiledShortcutBrowser()
        let space = installSpace("Space", in: tabManager)
        let target = makePin(spaceId: space.id)
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let model = RetainedFailureLauncherBindingModel {
            tabManager.structuralCollectionMutationOwner
                .setSpacePinnedShortcuts([target], for: space.id)
        }
        let aggregate = ShortcutSplitLauncherBindingAggregateTransaction(
            model: model,
            structuralMutations: tabManager.structuralCollectionMutationOwner,
            structuralLookup: tabManager.structuralLookupCoordinator
        )

        XCTAssertThrowsError(try aggregate.stage())
        XCTAssertTrue(aggregate.retainsModelAfterFailedStage())
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: target.id),
            target
        )
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertNil(
            tabManager.structuralCollectionMutationOwner.prepareAggregate()
        )
        XCTAssertTrue(aggregate.canSettleTerminalDrain())
        XCTAssertTrue(aggregate.settleTerminalDrain())
        let unrelated = try XCTUnwrap(
            tabManager.structuralCollectionMutationOwner.prepareAggregate()
        )
        XCTAssertTrue(unrelated.rollback())
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: target.id),
            target
        )
        XCTAssertEqual(model.terminalDrainCount, 1)
        XCTAssertEqual(structuralEvents, 0)
        _ = cancellable
    }

    private func makePin(spaceId: UUID) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            launchURL: URL(string: "https://binding.example")!,
            title: "Binding"
        )
    }

    private func installTestRuntime(
        _ runtime: RuntimePortRegistry,
        in browser: BrowserManager
    ) {
        browser.tabRuntimeLifecycle.shutdown()
        browser.runtimePortConnection.attach(runtime)
        addTeardownBlock { @MainActor [browser] in
            browser.runtimePortConnection.detach()
        }
    }

    private func installSpace(
        _ name: String,
        profileID: UUID? = nil,
        in browser: BrowserManager
    ) -> Space {
        let resolvedProfileID = profileID
            ?? browser.runtimePortConnection.captureLease().defaultProfileID
        let space = Space(name: name, profileId: resolvedProfileID)
        browser.spaceStateOwner.append(space)
        return space
    }

    private func makeBindingStaging(
        tabManager: BrowserManager
    ) -> ShortcutSplitLauncherBindingStaging {
        let structuralLookup = tabManager.structuralLookupCoordinator
        return ShortcutSplitLauncherBindingStaging(
            refreshes: tabManager.liveShortcutPresentationRefreshes,
            resolution: tabManager.shortcutPinRuntimeResolutionOwner,
            batches: ShortcutTabBindingBatchFactory(
                runtimeConnection: tabManager.runtimePortConnection,
                windowMutations: tabManager.shortcutWindowMutationOwner,
                profiles: tabManager.tabProfileTransitions,
                persistence: ShortcutSplitLauncherWindowPersistence(
                    structuralLookup: structuralLookup
                ),
                structuralLookup: structuralLookup
            )
        )
    }

    private func shortcutBindings(
        for browser: BrowserManager
    ) -> ShortcutTabBindingSynchronizer {
        let targets = ShortcutTabBindingTargetMutationService(
            resolution: browser.shortcutPinRuntimeResolutionOwner,
            profiles: browser.tabProfileTransitions
        )
        return ShortcutTabBindingSynchronizer(
            presentationRefreshes: browser.liveShortcutPresentationRefreshes,
            runtimeMutations: ShortcutTabBindingRuntimeMutation(
                registry: browser.liveShortcutTabs,
                targets: targets,
                runtimeConnection: browser.runtimePortConnection,
                windowMutations: browser.shortcutWindowMutationOwner,
                structuralLookup: browser.structuralLookupCoordinator
            ),
            targets: targets
        )
    }
}

@MainActor
private final class TerminalDrainResidenceParticipant:
    ShortcutTabBindingResidenceTransaction {
    let canAbandon: Bool
    private(set) var abandonCount = 0

    init(canAbandon: Bool) {
        self.canAbandon = canAbandon
    }

    func validateForStaging() -> Bool { true }
    func stage() -> Bool { true }
    func stagedModelIsExact() -> Bool { true }
    func cancelPrepared() -> Bool { true }
    func canRollback() -> Bool { true }
    func publish() -> Bool { true }
    func rollback() -> Bool { true }
    func canAbandonForTerminalDrain() -> Bool { canAbandon }
    func abandonForTerminalDrain() { abandonCount += 1 }
}

@MainActor
private final class RetainedFailureLauncherBindingModel:
    ShortcutSplitLauncherBindingModelTransaction {
    let exactBindingTabs: [Tab] = []
    private let stageCatalogMutation: () -> Void
    private(set) var terminalDrainCount = 0

    init(stageCatalogMutation: @escaping () -> Void) {
        self.stageCatalogMutation = stageCatalogMutation
    }

    func validateForStaging() -> Bool { true }
    func stageCatalog() -> Bool {
        stageCatalogMutation()
        return true
    }
    func prepareStructuralRollbackAfterCatalogStage() -> Bool { false }
    func stageBinding() throws { throw RetainedFailure() }
    func stagedModelIsExact() -> Bool { false }
    func canClaimTerminalModel() -> Bool { false }
    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        .terminallyDrained
    }
    func claimedModelIsExact() -> Bool { false }
    func publishModelCommit(beforeWindowPublication: () -> Void) {
        preconditionFailure("Retained failure cannot publish")
    }
    func publishTerminalEffects() {
        preconditionFailure("Retained failure cannot publish")
    }
    func cancelPrepared() -> Bool { false }
    func rollbackBinding() throws { throw RetainedFailure() }
    func confirmStructuralRollback() -> Bool { false }
    func publishRollback() {}
    func retainsModelAfterFailedStage() -> Bool { true }
    func canSettleTerminalDrain() -> Bool { true }
    func settleTerminalDrain() -> Bool {
        terminalDrainCount += 1
        return true
    }

    private struct RetainedFailure: Error {}
}

private extension ShortcutPin {
    func moved(to spaceId: UUID) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: .spacePinned,
            executionProfileId: executionProfileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: launchURL,
            title: title,
            iconAsset: iconAsset
        )
    }
}
