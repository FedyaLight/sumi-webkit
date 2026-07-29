import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewSessionRepositoryTests: XCTestCase {
    func testParkedToUntrackedToPrimaryAreMovesAcrossOneResidenceIndex() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let handle = WebViewSessionHandle(tabID: tabID, repository: repository)
        let webView = WKWebView()

        handle.park(webView)
        XCTAssertEqual(repository.residence(of: webView), .parked(tabID: tabID))

        XCTAssertTrue(handle.adoptParkedAsUntracked(webView))
        XCTAssertNil(handle.parkedWebView)
        XCTAssertIdentical(handle.untrackedWebView, webView)
        XCTAssertEqual(repository.residence(of: webView), .untracked(tabID: tabID))

        register(webView, tabID: tabID, windowID: windowID, in: repository)
        XCTAssertNil(handle.untrackedWebView)
        XCTAssertEqual(handle.primaryWindowID, windowID)
        XCTAssertIdentical(handle.primaryWebView, webView)
        XCTAssertEqual(
            repository.residence(of: webView),
            .window(.init(tabID: tabID, windowID: windowID))
        )
    }

    func testRepositoryTracksPrimaryAndClonesInOneForwardAndReverseIndex() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let primaryWindowID = UUID()
        let cloneWindowID = UUID()
        let primary = WKWebView()
        let clone = WKWebView()

        register(primary, tabID: tabID, windowID: primaryWindowID, in: repository)
        register(clone, tabID: tabID, windowID: cloneWindowID, in: repository)

        XCTAssertEqual(repository.primaryWindowID(for: tabID), primaryWindowID)
        XCTAssertIdentical(repository.queries.primaryWebView(for: tabID), primary)
        XCTAssertEqual(repository.queries.totalTrackedWebViewCount, 2)
        XCTAssertEqual(Set(repository.windowIDs(for: tabID)), [primaryWindowID, cloneWindowID])
        XCTAssertEqual(
            repository.trackedOwner(containing: clone),
            .init(tabID: tabID, windowID: cloneWindowID)
        )
    }

    func testWindowSecondaryIndexTracksEveryWindowMutationPath() {
        let repository = WebViewSessionRepository()
        let firstTabID = UUID()
        let secondTabID = UUID()
        let sharedWindowID = UUID()
        let oldCloneWindowID = UUID()
        let newCloneWindowID = UUID()
        let replacementWindowID = UUID()
        let firstSharedWebView = WKWebView()
        let replacementSharedWebView = WKWebView()
        let movingCloneWebView = WKWebView()
        let secondSharedWebView = WKWebView()
        let secondReplacementWebView = WKWebView()

        register(
            firstSharedWebView,
            tabID: firstTabID,
            windowID: sharedWindowID,
            in: repository
        )
        register(
            secondSharedWebView,
            tabID: secondTabID,
            windowID: sharedWindowID,
            in: repository
        )
        register(
            movingCloneWebView,
            tabID: firstTabID,
            windowID: oldCloneWindowID,
            in: repository
        )
        assertTrackedWebViews(
            [
                firstTabID: firstSharedWebView,
                secondTabID: secondSharedWebView,
            ],
            in: sharedWindowID,
            repository: repository
        )

        register(
            replacementSharedWebView,
            tabID: firstTabID,
            windowID: sharedWindowID,
            in: repository
        )
        assertTrackedWebViews(
            [
                firstTabID: replacementSharedWebView,
                secondTabID: secondSharedWebView,
            ],
            in: sharedWindowID,
            repository: repository
        )

        register(
            movingCloneWebView,
            tabID: firstTabID,
            windowID: newCloneWindowID,
            in: repository
        )
        assertTrackedWebViews(
            [:],
            in: oldCloneWindowID,
            repository: repository
        )
        assertTrackedWebViews(
            [firstTabID: movingCloneWebView],
            in: newCloneWindowID,
            repository: repository
        )

        let replacementResult = repository.placement.replaceWindowSet(
            for: secondTabID,
            expectedGeneration: repository.queries.generation(for: secondTabID),
            webViewsByWindowID: [replacementWindowID: secondReplacementWebView],
            primaryWindowID: replacementWindowID
        )
        guard case .committed = replacementResult else {
            return XCTFail("Expected second tab window-set replacement")
        }
        assertTrackedWebViews(
            [firstTabID: replacementSharedWebView],
            in: sharedWindowID,
            repository: repository
        )
        assertTrackedWebViews(
            [secondTabID: secondReplacementWebView],
            in: replacementWindowID,
            repository: repository
        )

        XCTAssertIdentical(repository.placement.removeWindowWebView(
            owner: .init(tabID: firstTabID, windowID: sharedWindowID),
            expectedWebView: replacementSharedWebView
        ), replacementSharedWebView)
        assertTrackedWebViews(
            [:],
            in: sharedWindowID,
            repository: repository
        )

        repository.placement.clearAll(for: secondTabID)
        assertTrackedWebViews(
            [:],
            in: replacementWindowID,
            repository: repository
        )
        repository.assertConsistency("testWindowSecondaryIndexTracksEveryWindowMutationPath")
    }

    func testExpectedIdentityMismatchDoesNotMutateForwardOrReverseIndex() {
        let repository = WebViewSessionRepository()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let installed = WKWebView()
        let staleExpectedValue = WKWebView()
        register(installed, owner: owner, in: repository)
        let generation = repository.queries.generation(for: owner.tabID)

        let removed = repository.placement.removeWindowWebView(
            owner: owner,
            expectedWebView: staleExpectedValue
        )

        XCTAssertNil(removed)
        XCTAssertIdentical(repository.queries.webView(for: owner), installed)
        XCTAssertEqual(repository.trackedOwner(containing: installed), owner)
        XCTAssertNil(repository.residence(of: staleExpectedValue))
        XCTAssertEqual(repository.queries.generation(for: owner.tabID), generation)
    }

    func testInstallingTrackedReplacementClearsPreviousUntrackedResidence() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let untracked = WKWebView()
        let tracked = WKWebView()

        repository.placement.noteUntrackedWebView(untracked, for: tabID)
        register(tracked, tabID: tabID, windowID: windowID, in: repository)

        XCTAssertNil(repository.queries.untrackedWebView(for: tabID))
        XCTAssertNil(repository.residence(of: untracked))
        XCTAssertEqual(
            repository.residence(of: tracked),
            .window(.init(tabID: tabID, windowID: windowID))
        )
        repository.assertConsistency("testInstallingTrackedReplacement")
    }

    func testNoOpDetachedClearAndPrimaryPromotionKeepGenerationStable() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let webView = WKWebView()
        register(webView, tabID: tabID, windowID: windowID, in: repository)
        let generation = repository.queries.generation(for: tabID)

        repository.placement.clearDetachedWebViews(for: tabID)
        XCTAssertTrue(repository.placement.promoteTrackedWebViewToPrimary(
            owner: .init(tabID: tabID, windowID: windowID),
            expectedWebView: webView
        ))

        XCTAssertEqual(repository.queries.generation(for: tabID), generation)
    }

    func testUnregisterHonorsRecentVisibilityRemovalPolicy() {
        let repository = WebViewSessionRepository()
        let lifecycle = WebViewTrackingLifecycleOwner()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let first = WKWebView()
        let second = WKWebView()
        var forgottenOwners: [TrackedWebViewOwner] = []
        register(first, owner: owner, in: repository)

        _ = lifecycle.unregisterTrackedWebViewSlot(
            owner: owner,
            expectedWebView: first,
            removeRecentVisibility: false,
            in: repository,
            removeFromContainers: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            forgetRecentVisibility: { forgottenOwners.append($0) }
        )
        XCTAssertTrue(forgottenOwners.isEmpty)

        register(second, owner: owner, in: repository)
        _ = lifecycle.unregisterTrackedWebViewSlot(
            owner: owner,
            expectedWebView: second,
            in: repository,
            removeFromContainers: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            forgetRecentVisibility: { forgottenOwners.append($0) }
        )
        XCTAssertEqual(forgottenOwners, [owner])
    }

    func testHandleUsesInjectedRepositoryWithoutMigration() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let handle = WebViewSessionHandle(tabID: tabID, repository: repository)
        let parked = WKWebView()
        handle.park(parked)

        handle.requireBacking(by: repository)
        XCTAssertTrue(handle.isBacked(by: repository))
        XCTAssertIdentical(repository.queries.parkedWebView(for: tabID), parked)
        XCTAssertEqual(repository.residence(of: parked), .parked(tabID: tabID))
    }

    func testStaleWindowSetReplacementLeavesLiveStateUntouched() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let oldWindowID = UUID()
        let newWindowID = UUID()
        let oldWebView = WKWebView()
        let newWebView = WKWebView()
        register(oldWebView, tabID: tabID, windowID: oldWindowID, in: repository)
        let staleGeneration = repository.queries.generation(for: tabID)
        repository.placement.noteParkedWebView(WKWebView(), for: tabID)

        let result = repository.placement.replaceWindowSet(
            for: tabID,
            expectedGeneration: staleGeneration,
            webViewsByWindowID: [newWindowID: newWebView],
            primaryWindowID: newWindowID
        )

        guard case .stale = result else {
            return XCTFail("Expected stale generation rejection")
        }
        XCTAssertIdentical(repository.queries.webView(for: tabID, in: oldWindowID), oldWebView)
        XCTAssertNil(repository.queries.webView(for: tabID, in: newWindowID))
        XCTAssertNil(repository.residence(of: newWebView))
    }

    func testAtomicWindowSetReplacementReturnsCompletePreviousSnapshot() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let old = WKWebView()
        let replacementPrimary = WKWebView()
        let replacementClone = WKWebView()
        register(old, tabID: tabID, windowID: firstWindowID, in: repository)
        let generation = repository.queries.generation(for: tabID)

        let result = repository.placement.replaceWindowSet(
            for: tabID,
            expectedGeneration: generation,
            webViewsByWindowID: [
                firstWindowID: replacementPrimary,
                secondWindowID: replacementClone,
            ],
            primaryWindowID: firstWindowID
        )

        guard case .committed(let previous) = result else {
            return XCTFail("Expected an atomic commit")
        }
        XCTAssertEqual(previous.generation, generation)
        XCTAssertIdentical(previous.windowWebViews[firstWindowID], old)
        XCTAssertNil(repository.residence(of: old))
        XCTAssertIdentical(repository.queries.primaryWebView(for: tabID), replacementPrimary)
        XCTAssertEqual(repository.trackedOwner(containing: replacementClone), .init(
            tabID: tabID,
            windowID: secondWindowID
        ))
    }

    func testAtomicWindowSetReplacementRejectsReusingLiveWebView() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let liveWebView = WKWebView()
        register(liveWebView, tabID: tabID, windowID: firstWindowID, in: repository)
        let generation = repository.queries.generation(for: tabID)

        let result = repository.placement.replaceWindowSet(
            for: tabID,
            expectedGeneration: generation,
            webViewsByWindowID: [secondWindowID: liveWebView],
            primaryWindowID: secondWindowID
        )

        guard case .invalid = result else {
            return XCTFail("Expected live WebView reuse to be rejected")
        }
        XCTAssertIdentical(repository.queries.webView(for: tabID, in: firstWindowID), liveWebView)
        XCTAssertNil(repository.queries.webView(for: tabID, in: secondWindowID))
        XCTAssertEqual(repository.queries.generation(for: tabID), generation)
    }

    func testSlotRegistrationCommitsOnceBeforeLifecycleSideEffects() {
        let repository = WebViewSessionRepository()
        let lifecycle = WebViewTrackingLifecycleOwner()
        let tabID = UUID()
        let sourceOwner = TrackedWebViewOwner(tabID: tabID, windowID: UUID())
        let targetOwner = TrackedWebViewOwner(tabID: tabID, windowID: UUID())
        let candidate = WKWebView()
        let displaced = WKWebView()
        register(candidate, owner: sourceOwner, in: repository)
        register(displaced, owner: targetOwner, in: repository)
        let generation = repository.queries.generation(for: tabID)
        var events: [String] = []

        func assertCommittedState(
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertNil(repository.queries.webView(for: sourceOwner), file: file, line: line)
            XCTAssertIdentical(
                repository.queries.webView(for: targetOwner),
                candidate,
                file: file,
                line: line
            )
            XCTAssertNil(repository.residence(of: displaced), file: file, line: line)
            XCTAssertEqual(
                repository.queries.generation(for: tabID),
                generation + 1,
                file: file,
                line: line
            )
        }

        lifecycle.registerTrackedWebView(
            candidate,
            for: targetOwner,
            in: repository,
            removeFromContainers: { webView in
                XCTAssertIdentical(webView, candidate)
                assertCommittedState()
                events.append("remove-candidate-container")
            },
            installRuntimeObservations: { webView in
                XCTAssertIdentical(webView, candidate)
                assertCommittedState()
                events.append("install-candidate-observations")
            },
            uninstallRuntimeObservationsIfUntracked: { webView in
                XCTAssertIdentical(webView, displaced)
                assertCommittedState()
                events.append("uninstall-displaced-observations")
            },
            pruneInvalidDeferredCommands: { reason in
                XCTAssertEqual(reason, "registerTrackedWebView")
                assertCommittedState()
                events.append("prune")
            },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { owner in
                XCTAssertEqual(owner, sourceOwner)
                assertCommittedState()
                events.append("forget-source-visibility")
            },
            didCommitPlacement: {
                assertCommittedState()
                events.append("did-commit-placement")
            },
            cleanupDisplacedWebView: { webView, cleanupTabID in
                XCTAssertIdentical(webView, displaced)
                XCTAssertEqual(cleanupTabID, tabID)
                assertCommittedState()
                events.append("cleanup-displaced")
            }
        )

        assertCommittedState()
        XCTAssertEqual(events, [
            "did-commit-placement",
            "remove-candidate-container",
            "forget-source-visibility",
            "uninstall-displaced-observations",
            "cleanup-displaced",
            "install-candidate-observations",
            "prune",
        ])
    }

    func testLifecycleRegistrationReturnsProtectedCandidateWithoutSideEffects() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let sourceOwner = TrackedWebViewOwner(tabID: tabID, windowID: UUID())
        let targetOwner = TrackedWebViewOwner(tabID: tabID, windowID: UUID())
        let candidate = WKWebView()
        register(candidate, owner: sourceOwner, in: repository)
        let generation = repository.queries.generation(for: tabID)
        var sideEffectCount = 0

        let result = lifecycleRegistration(
            candidate,
            owner: targetOwner,
            repository: repository,
            canDisplace: { $0 !== candidate },
            sideEffect: { sideEffectCount += 1 }
        )

        XCTAssertEqual(result, .rejected(.protectedCandidate))
        XCTAssertEqual(sideEffectCount, 0)
        XCTAssertIdentical(repository.queries.webView(for: sourceOwner), candidate)
        XCTAssertNil(repository.queries.webView(for: targetOwner))
        XCTAssertEqual(repository.queries.generation(for: tabID), generation)
    }

    func testLifecycleRegistrationReturnsProtectedOccupantWithoutSideEffects() {
        let repository = WebViewSessionRepository()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let occupant = WKWebView()
        let candidate = WKWebView()
        register(occupant, owner: owner, in: repository)
        let generation = repository.queries.generation(for: owner.tabID)
        var sideEffectCount = 0

        let result = lifecycleRegistration(
            candidate,
            owner: owner,
            repository: repository,
            canDisplace: { $0 !== occupant },
            sideEffect: { sideEffectCount += 1 }
        )

        XCTAssertEqual(result, .rejected(.protectedTrackedOccupant))
        XCTAssertEqual(sideEffectCount, 0)
        XCTAssertIdentical(repository.queries.webView(for: owner), occupant)
        XCTAssertNil(repository.residence(of: candidate))
        XCTAssertEqual(repository.queries.generation(for: owner.tabID), generation)
    }

    func testLifecycleRegistrationReturnsChangedPreflightWithoutSideEffects() {
        let repository = WebViewSessionRepository()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let alternateOwner = TrackedWebViewOwner(
            tabID: owner.tabID,
            windowID: UUID()
        )
        let occupant = WKWebView()
        let alternate = WKWebView()
        let candidate = WKWebView()
        register(occupant, owner: owner, in: repository)
        register(alternate, owner: alternateOwner, in: repository)
        let generation = repository.queries.generation(for: owner.tabID)
        var didMutatePreflight = false
        var sideEffectCount = 0

        let result = lifecycleRegistration(
            candidate,
            owner: owner,
            repository: repository,
            canDisplace: { _ in
                if didMutatePreflight == false {
                    didMutatePreflight = true
                    XCTAssertTrue(
                        repository.placement.promoteTrackedWebViewToPrimary(
                            owner: alternateOwner,
                            expectedWebView: alternate
                        )
                    )
                }
                return true
            },
            sideEffect: { sideEffectCount += 1 }
        )

        XCTAssertEqual(result, .rejected(.changedDuringPreflight))
        XCTAssertEqual(sideEffectCount, 0)
        XCTAssertIdentical(repository.queries.webView(for: owner), occupant)
        XCTAssertIdentical(
            repository.queries.webView(for: alternateOwner),
            alternate
        )
        XCTAssertNil(repository.residence(of: candidate))
        XCTAssertEqual(repository.queries.primaryWindowID(for: owner.tabID), alternateOwner.windowID)
        XCTAssertEqual(repository.queries.generation(for: owner.tabID), generation + 1)
    }

    func testSlotRegistrationRejectsCrossTabCandidateWithoutMutation() {
        let repository = WebViewSessionRepository()
        let sourceOwner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let targetOwner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let candidate = WKWebView()
        register(candidate, owner: sourceOwner, in: repository)
        let sourceGeneration = repository.queries.generation(for: sourceOwner.tabID)
        let targetGeneration = repository.queries.generation(for: targetOwner.tabID)

        let result = repository.placement.registerWindowWebView(
            candidate,
            for: targetOwner,
            canDisplaceWebView: { _ in true }
        )

        guard case .rejected(.crossTabCandidate) = result else {
            return XCTFail("Expected cross-tab identity rejection")
        }
        XCTAssertIdentical(repository.queries.webView(for: sourceOwner), candidate)
        XCTAssertNil(repository.queries.webView(for: targetOwner))
        XCTAssertEqual(repository.queries.generation(for: sourceOwner.tabID), sourceGeneration)
        XCTAssertEqual(repository.queries.generation(for: targetOwner.tabID), targetGeneration)
    }

    func testSlotRegistrationRejectsProtectedCandidateBeforeMovingIt() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let sourceOwner = TrackedWebViewOwner(tabID: tabID, windowID: UUID())
        let targetOwner = TrackedWebViewOwner(tabID: tabID, windowID: UUID())
        let candidate = WKWebView()
        register(candidate, owner: sourceOwner, in: repository)
        let generation = repository.queries.generation(for: tabID)

        let result = repository.placement.registerWindowWebView(
            candidate,
            for: targetOwner,
            canDisplaceWebView: { $0 !== candidate }
        )

        guard case .rejected(.protectedCandidate) = result else {
            return XCTFail("Expected protected candidate rejection")
        }
        XCTAssertIdentical(repository.queries.webView(for: sourceOwner), candidate)
        XCTAssertNil(repository.queries.webView(for: targetOwner))
        XCTAssertEqual(repository.queries.generation(for: tabID), generation)
    }

    func testSlotRegistrationRejectsProtectedTrackedOccupantBeforeDisplacement() {
        let repository = WebViewSessionRepository()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let occupant = WKWebView()
        let candidate = WKWebView()
        register(occupant, owner: owner, in: repository)
        let generation = repository.queries.generation(for: owner.tabID)

        let result = repository.placement.registerWindowWebView(
            candidate,
            for: owner,
            canDisplaceWebView: { $0 !== occupant }
        )

        guard case .rejected(.protectedTrackedOccupant) = result else {
            return XCTFail("Expected protected tracked occupant rejection")
        }
        XCTAssertIdentical(repository.queries.webView(for: owner), occupant)
        XCTAssertNil(repository.residence(of: candidate))
        XCTAssertEqual(repository.queries.generation(for: owner.tabID), generation)
    }

    func testSlotRegistrationCommitReturnsTrackedOccupantForPostCommitCleanup() {
        let repository = WebViewSessionRepository()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let occupant = WKWebView()
        let candidate = WKWebView()
        register(occupant, owner: owner, in: repository)
        let generation = repository.queries.generation(for: owner.tabID)

        let result = repository.placement.registerWindowWebView(
            candidate,
            for: owner,
            canDisplaceWebView: { _ in true }
        )

        guard case .committed(let commit) = result else {
            return XCTFail("Expected slot registration commit")
        }
        XCTAssertIdentical(commit.displacedTrackedWebView, occupant)
        XCTAssertNil(commit.displacedUntrackedWebView)
        XCTAssertNil(commit.vacatedOwner)
        XCTAssertEqual(commit.generation, generation + 1)
        XCTAssertIdentical(repository.queries.webView(for: owner), candidate)
        XCTAssertNil(repository.residence(of: occupant))
    }

    func testSlotRegistrationRejectsProtectedUntrackedOccupantBeforeDisplacement() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let owner = TrackedWebViewOwner(tabID: tabID, windowID: UUID())
        let occupant = WKWebView()
        let candidate = WKWebView()
        repository.placement.noteUntrackedWebView(occupant, for: tabID)
        let generation = repository.queries.generation(for: tabID)

        let result = repository.placement.registerWindowWebView(
            candidate,
            for: owner,
            canDisplaceWebView: { $0 !== occupant }
        )

        guard case .rejected(.protectedUntrackedOccupant) = result else {
            return XCTFail("Expected protected untracked occupant rejection")
        }
        XCTAssertIdentical(repository.queries.untrackedWebView(for: tabID), occupant)
        XCTAssertNil(repository.queries.webView(for: owner))
        XCTAssertNil(repository.residence(of: candidate))
        XCTAssertEqual(repository.queries.generation(for: tabID), generation)
    }

    func testRemovedSessionRevisionRejectsAbsentPresentAbsentABA() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let staleGeneration = repository.queries.generation(for: tabID)
        repository.placement.noteUntrackedWebView(WKWebView(), for: tabID)
        repository.placement.clearAll(for: tabID)
        let replacementWindowID = UUID()

        let result = repository.placement.replaceWindowSet(
            for: tabID,
            expectedGeneration: staleGeneration,
            webViewsByWindowID: [replacementWindowID: WKWebView()],
            primaryWindowID: replacementWindowID
        )

        guard case .stale(let currentGeneration) = result else {
            return XCTFail("Expected absent-present-absent ABA rejection")
        }
        XCTAssertNotEqual(currentGeneration, staleGeneration)
        XCTAssertTrue(repository.queries.allKnownWebViews(for: tabID).isEmpty)
    }

    func testPendingCleanupLeaseRetainsExactOwnerUntilConsumed() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let webView = WKWebView()

        guard let lease = repository.beginPendingCleanup(of: webView, for: tabID) else {
            return XCTFail("Expected a pending-cleanup lease")
        }

        XCTAssertEqual(repository.residence(of: webView), .pendingCleanup(lease))
        XCTAssertIdentical(repository.queries.webView(with: ObjectIdentifier(webView)), webView)
        XCTAssertEqual(repository.beginPendingCleanup(of: webView, for: tabID), lease)
        XCTAssertNil(repository.beginPendingCleanup(of: webView, for: UUID()))
        XCTAssertFalse(repository.consumePendingCleanup(
            of: webView,
            lease: .init(id: UUID(), tabID: tabID)
        ))
        XCTAssertTrue(repository.consumePendingCleanup(of: webView, lease: lease))
        XCTAssertNil(repository.residence(of: webView))
        XCTAssertNil(repository.queries.webView(with: ObjectIdentifier(webView)))
    }

    func testPendingCleanupWebViewCannotReenterTrackedSlot() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let webView = WKWebView()
        let owner = TrackedWebViewOwner(tabID: tabID, windowID: UUID())
        guard let lease = repository.beginPendingCleanup(of: webView, for: tabID) else {
            return XCTFail("Expected a pending-cleanup lease")
        }

        let result = repository.placement.registerWindowWebView(
            webView,
            for: owner,
            canDisplaceWebView: { _ in true }
        )

        guard case .rejected(.pendingCleanupCandidate) = result else {
            return XCTFail("Expected pending-cleanup candidate rejection")
        }
        XCTAssertEqual(repository.residence(of: webView), .pendingCleanup(lease))
        XCTAssertNil(repository.queries.webView(for: owner))
    }

    func testDetachedSetReplacementAtomicallyLeasesEveryOldResidence() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let parked = WKWebView()
        let untracked = WKWebView()
        let replacement = WKWebView()
        repository.placement.noteParkedWebView(parked, for: tabID)
        repository.placement.noteUntrackedWebView(untracked, for: tabID)
        let expectedGeneration = repository.queries.generation(for: tabID)

        let result = repository.replaceDetachedSetAndBeginPendingCleanup(
            with: replacement,
            residence: .untracked,
            expectedGeneration: expectedGeneration,
            for: tabID
        )

        guard case .committed(let claims) = result else {
            return XCTFail("Expected the detached set CAS to commit")
        }
        XCTAssertEqual(claims.count, 2)
        XCTAssertNil(repository.queries.parkedWebView(for: tabID))
        XCTAssertIdentical(repository.queries.untrackedWebView(for: tabID), replacement)
        XCTAssertEqual(repository.residence(of: replacement), .untracked(tabID: tabID))
        for displaced in [parked, untracked] {
            let claim = claims.first { $0.webView === displaced }
            XCTAssertNotNil(claim)
            if let claim {
                XCTAssertEqual(
                    repository.residence(of: displaced),
                    .pendingCleanup(claim.lease)
                )
                XCTAssertTrue(
                    repository.consumePendingCleanup(
                        of: displaced,
                        lease: claim.lease
                    )
                )
            }
        }
    }

    func testDetachedSetReplacementRejectsStaleGenerationWithoutMutation() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let parked = WKWebView()
        let concurrentlyAdded = WKWebView()
        let replacement = WKWebView()
        repository.placement.noteParkedWebView(parked, for: tabID)
        let staleGeneration = repository.queries.generation(for: tabID)
        repository.placement.noteUntrackedWebView(concurrentlyAdded, for: tabID)
        let currentGeneration = repository.queries.generation(for: tabID)

        let result = repository.replaceDetachedSetAndBeginPendingCleanup(
            with: replacement,
            residence: .parked,
            expectedGeneration: staleGeneration,
            for: tabID
        )

        guard case .stale(let reportedGeneration) = result else {
            return XCTFail("Expected stale detached replacement")
        }
        XCTAssertEqual(reportedGeneration, currentGeneration)
        XCTAssertIdentical(repository.queries.parkedWebView(for: tabID), parked)
        XCTAssertIdentical(repository.queries.untrackedWebView(for: tabID), concurrentlyAdded)
        XCTAssertEqual(repository.residence(of: parked), .parked(tabID: tabID))
        XCTAssertEqual(
            repository.residence(of: concurrentlyAdded),
            .untracked(tabID: tabID)
        )
        XCTAssertNil(repository.residence(of: replacement))
    }

    func testUntrackedReleaseAtomicallyLeasesDisplacedWebView() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let displaced = WKWebView()
        repository.placement.noteUntrackedWebView(displaced, for: tabID)

        guard let lease = repository.releaseUntrackedAndBeginPendingCleanup(
            displaced,
            for: tabID
        ) else {
            return XCTFail("Expected atomic untracked release")
        }

        XCTAssertNil(repository.queries.untrackedWebView(for: tabID))
        XCTAssertEqual(repository.residence(of: displaced), .pendingCleanup(lease))
        XCTAssertTrue(repository.consumePendingCleanup(of: displaced, lease: lease))
    }

    func testParkedReleaseAtomicallyLeasesDisplacedWebView() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let parked = WKWebView()
        repository.placement.noteParkedWebView(parked, for: tabID)

        guard let lease = repository.releaseParkedAndBeginPendingCleanup(
            parked,
            for: tabID
        ) else {
            return XCTFail("Expected atomic parked release")
        }

        XCTAssertNil(repository.queries.parkedWebView(for: tabID))
        XCTAssertEqual(repository.residence(of: parked), .pendingCleanup(lease))
        XCTAssertTrue(repository.consumePendingCleanup(of: parked, lease: lease))
    }

    func testTerminalShutdownAtomicallyDrainsEveryResidenceKind() throws {
        let repository = WebViewSessionRepository()
        let parkedTabID = UUID()
        let untrackedTabID = UUID()
        let trackedTabID = UUID()
        let pendingTabID = UUID()
        let windowID = UUID()
        let parked = WKWebView()
        let untracked = WKWebView()
        let tracked = WKWebView()
        let pending = WKWebView()

        repository.placement.noteParkedWebView(parked, for: parkedTabID)
        repository.placement.noteUntrackedWebView(untracked, for: untrackedTabID)
        register(tracked, tabID: trackedTabID, windowID: windowID, in: repository)
        let pendingLease = try XCTUnwrap(
            repository.beginPendingCleanup(of: pending, for: pendingTabID)
        )

        let drained = repository.takeAllWebViewsForTerminalShutdown()
        let drainedByID = Dictionary(
            uniqueKeysWithValues: drained.map { (ObjectIdentifier($0.webView), $0) }
        )

        XCTAssertEqual(drained.count, 4)
        XCTAssertEqual(
            drainedByID[ObjectIdentifier(parked)]?.residence,
            .parked(tabID: parkedTabID)
        )
        XCTAssertEqual(
            drainedByID[ObjectIdentifier(untracked)]?.residence,
            .untracked(tabID: untrackedTabID)
        )
        XCTAssertEqual(
            drainedByID[ObjectIdentifier(tracked)]?.residence,
            .window(.init(tabID: trackedTabID, windowID: windowID))
        )
        XCTAssertEqual(
            drainedByID[ObjectIdentifier(pending)]?.residence,
            .pendingCleanup(pendingLease)
        )
        XCTAssertTrue(repository.queries.isTrackingEmpty)
        XCTAssertEqual(repository.queries.totalTrackedWebViewCount, 0)
        for webView in [parked, untracked, tracked, pending] {
            XCTAssertNil(repository.residence(of: webView))
            XCTAssertNil(repository.queries.webView(with: ObjectIdentifier(webView)))
        }
        XCTAssertTrue(repository.takeAllWebViewsForTerminalShutdown().isEmpty)
    }

    func testPendingCleanupParticipatesInProcessResidenceGenerationAndBarrier() async throws {
        let repository = WebViewSessionRepository()
        let webView = WKWebView()
        let initialGeneration = repository.residenceGeneration
        let lease = try XCTUnwrap(
            repository.beginPendingCleanup(of: webView, for: UUID())
        )

        let admittedGeneration = repository.residenceGeneration
        XCTAssertGreaterThan(admittedGeneration, initialGeneration)
        let snapshot = repository.queries.pendingCleanupSnapshot()
        XCTAssertEqual(snapshot.generation, admittedGeneration)
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertIdentical(snapshot.entries.first?.webView, webView)
        XCTAssertEqual(snapshot.entries.first?.lease, lease)

        let barrier = Task { @MainActor in
            await repository.queries.waitUntilPendingCleanupIsEmpty()
        }
        await Task.yield()
        XCTAssertFalse(barrier.isCancelled)

        XCTAssertTrue(repository.consumePendingCleanup(of: webView, lease: lease))
        let didCrossBarrier = await barrier.value
        XCTAssertTrue(didCrossBarrier)
        XCTAssertGreaterThan(repository.residenceGeneration, admittedGeneration)
        XCTAssertTrue(repository.queries.pendingCleanupSnapshot().isEmpty)
    }

    func testTerminalShutdownReleasesPendingCleanupBarrierAsFailure() async throws {
        let repository = WebViewSessionRepository()
        let webView = WKWebView()
        _ = try XCTUnwrap(repository.beginPendingCleanup(of: webView, for: UUID()))

        let barrier = Task { @MainActor in
            await repository.queries.waitUntilPendingCleanupIsEmpty()
        }
        await Task.yield()
        _ = repository.takeAllWebViewsForTerminalShutdown()

        let didCrossBarrier = await barrier.value
        XCTAssertFalse(didCrossBarrier)
    }

    func testWindowReplacementRetainsPreviousGenerationUntilExactCommit() throws {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let primaryWindowID = UUID()
        let cloneWindowID = UUID()
        let oldPrimary = WKWebView()
        let oldClone = WKWebView()
        let replacementPrimary = WKWebView()
        let replacementClone = WKWebView()
        register(oldPrimary, tabID: tabID, windowID: primaryWindowID, in: repository)
        register(oldClone, tabID: tabID, windowID: cloneWindowID, in: repository)

        let result = repository.beginWindowSetReplacement(
            for: tabID,
            expectedGeneration: repository.queries.generation(for: tabID),
            webViewsByWindowID: [
                primaryWindowID: replacementPrimary,
                cloneWindowID: replacementClone,
            ],
            primaryWindowID: primaryWindowID
        )
        guard case .began(let lease) = result else {
            return XCTFail("Expected replacement batch to begin")
        }

        XCTAssertIdentical(repository.queries.primaryWebView(for: tabID), replacementPrimary)
        XCTAssertIdentical(
            repository.queries.webView(for: tabID, in: cloneWindowID),
            replacementClone
        )
        for oldWebView in [oldPrimary, oldClone] {
            guard case .retiring(let retirementLease) = repository.residence(
                of: oldWebView
            ) else {
                return XCTFail("Previous generation must remain retirement-owned")
            }
            XCTAssertEqual(retirementLease.batchID, lease.id)
            XCTAssertEqual(retirementLease.tabID, tabID)
            XCTAssertIdentical(
                repository.queries.webView(with: ObjectIdentifier(oldWebView)),
                oldWebView
            )
        }
        XCTAssertEqual(
            Set(repository.queries.runtimeOwnedWebViews(for: tabID).map(ObjectIdentifier.init)),
            Set([
                oldPrimary,
                oldClone,
                replacementPrimary,
                replacementClone,
            ].map(ObjectIdentifier.init))
        )
        XCTAssertEqual(
            repository.queries.ownershipTransitionSnapshot().retirementEntries.count,
            2
        )

        let installedGeneration = repository.queries.generation(for: tabID)
        let commit = repository.commitReplacementBatch(lease)
        guard case .committed(let retired) = commit else {
            return XCTFail("Expected exact replacement commit")
        }
        XCTAssertIdentical(
            retired[tabID]?.windowWebViews[primaryWindowID],
            oldPrimary
        )
        XCTAssertNil(repository.residence(of: oldPrimary))
        XCTAssertNil(repository.residence(of: oldClone))
        XCTAssertGreaterThan(repository.queries.generation(for: tabID), installedGeneration)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
        guard case .noLongerActive = repository.commitReplacementBatch(lease) else {
            return XCTFail("A retirement lease must commit exactly once")
        }
    }

    func testWindowReplacementRollbackRestoresCompletePreviousSnapshot() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let primaryWindowID = UUID()
        let cloneWindowID = UUID()
        let oldPrimary = WKWebView()
        let oldClone = WKWebView()
        let oldParked = WKWebView()
        let replacementPrimary = WKWebView()
        let replacementClone = WKWebView()
        register(oldPrimary, tabID: tabID, windowID: primaryWindowID, in: repository)
        register(oldClone, tabID: tabID, windowID: cloneWindowID, in: repository)
        repository.placement.noteParkedWebView(oldParked, for: tabID)

        let result = repository.beginWindowSetReplacement(
            for: tabID,
            expectedGeneration: repository.queries.generation(for: tabID),
            webViewsByWindowID: [
                primaryWindowID: replacementPrimary,
                cloneWindowID: replacementClone,
            ],
            primaryWindowID: cloneWindowID
        )
        guard case .began(let lease) = result else {
            return XCTFail("Expected replacement batch to begin")
        }
        var modelRollbackCount = 0

        let rollback = repository.rollbackReplacementBatch(lease) {
            modelRollbackCount += 1
        }

        guard case .rolledBack(let discarded) = rollback else {
            return XCTFail("Expected exact replacement rollback")
        }
        XCTAssertEqual(modelRollbackCount, 1)
        XCTAssertIdentical(repository.queries.primaryWebView(for: tabID), oldPrimary)
        XCTAssertIdentical(repository.queries.webView(for: tabID, in: cloneWindowID), oldClone)
        XCTAssertIdentical(repository.queries.parkedWebView(for: tabID), oldParked)
        XCTAssertIdentical(
            discarded[tabID]?.windowWebViews[cloneWindowID],
            replacementClone
        )
        XCTAssertNil(repository.residence(of: replacementPrimary))
        XCTAssertNil(repository.residence(of: replacementClone))
        XCTAssertEqual(
            repository.residence(of: oldPrimary),
            .window(.init(tabID: tabID, windowID: primaryWindowID))
        )
        XCTAssertEqual(repository.residence(of: oldParked), .parked(tabID: tabID))
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
        guard case .noLongerActive = repository.rollbackReplacementBatch(lease) else {
            return XCTFail("A retirement lease must roll back exactly once")
        }
    }

    func testDetachedReplacementRollbackRestoresParkedAndUntrackedSet() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let oldParked = WKWebView()
        let oldUntracked = WKWebView()
        let replacement = WKWebView()
        repository.placement.noteParkedWebView(oldParked, for: tabID)
        repository.placement.noteUntrackedWebView(oldUntracked, for: tabID)

        let result = repository.beginDetachedSetReplacement(
            with: replacement,
            residence: .parked,
            expectedGeneration: repository.queries.generation(for: tabID),
            for: tabID
        )
        guard case .began(let lease) = result else {
            return XCTFail("Expected detached replacement to begin")
        }
        XCTAssertIdentical(repository.queries.parkedWebView(for: tabID), replacement)
        XCTAssertNil(repository.queries.untrackedWebView(for: tabID))
        XCTAssertEqual(repository.queries.runtimeOwnedWebViews(for: tabID).count, 3)
        guard case .retiring = repository.residence(of: oldParked),
              case .retiring = repository.residence(of: oldUntracked) else {
            return XCTFail("Both detached predecessors must be retirement-owned")
        }

        guard case .rolledBack(let discarded) = repository
            .rollbackReplacementBatch(lease) else {
            return XCTFail("Expected detached replacement rollback")
        }
        XCTAssertIdentical(repository.queries.parkedWebView(for: tabID), oldParked)
        XCTAssertIdentical(repository.queries.untrackedWebView(for: tabID), oldUntracked)
        XCTAssertIdentical(discarded[tabID]?.parkedWebView, replacement)
        XCTAssertNil(repository.residence(of: replacement))
    }

    func testMixedBatchValidatesThenCommitsModelAgainstInstalledPlacements() {
        let repository = WebViewSessionRepository()
        let trackedTabID = UUID()
        let detachedTabID = UUID()
        let windowID = UUID()
        let oldTracked = WKWebView()
        let oldDetached = WKWebView()
        let replacementTracked = WKWebView()
        let replacementDetached = WKWebView()
        register(oldTracked, tabID: trackedTabID, windowID: windowID, in: repository)
        repository.placement.noteUntrackedWebView(oldDetached, for: detachedTabID)
        var events: [String] = []

        let result = repository.beginReplacementBatch(
            [
                WebViewReplacementBatchEntry(
                    tabID: trackedTabID,
                    expectedGeneration: repository.queries.generation(for: trackedTabID),
                    placement: .windowSet(
                        webViewsByWindowID: [windowID: replacementTracked],
                        primaryWindowID: windowID
                    )
                ),
                WebViewReplacementBatchEntry(
                    tabID: detachedTabID,
                    expectedGeneration: repository.queries.generation(for: detachedTabID),
                    placement: .detached(
                        webView: replacementDetached,
                        residence: .untracked
                    )
                ),
            ],
            validateModel: {
                events.append("validate")
                XCTAssertIdentical(
                    repository.queries.webView(for: trackedTabID, in: windowID),
                    oldTracked
                )
                return true
            },
            modelCommit: {
                events.append("commit-model")
                XCTAssertIdentical(
                    repository.queries.webView(for: trackedTabID, in: windowID),
                    replacementTracked
                )
                XCTAssertIdentical(
                    repository.queries.untrackedWebView(for: detachedTabID),
                    replacementDetached
                )
            }
        )
        guard case .began(let lease) = result else {
            return XCTFail("Expected mixed replacement batch")
        }
        XCTAssertEqual(events, ["validate", "commit-model"])
        guard case .committed(let retired) = repository
            .commitReplacementBatch(lease) else {
            return XCTFail("Expected mixed batch commit")
        }
        XCTAssertIdentical(
            retired[trackedTabID]?.windowWebViews[windowID],
            oldTracked
        )
        XCTAssertIdentical(retired[detachedTabID]?.untrackedWebView, oldDetached)
        XCTAssertNil(repository.residence(of: oldTracked))
        XCTAssertNil(repository.residence(of: oldDetached))
    }

    func testBatchStalenessRejectsEveryEntryBeforeModelCallbacks() {
        let repository = WebViewSessionRepository()
        let firstTabID = UUID()
        let secondTabID = UUID()
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let firstOld = WKWebView()
        let secondOld = WKWebView()
        let firstReplacement = WKWebView()
        let secondReplacement = WKWebView()
        register(firstOld, tabID: firstTabID, windowID: firstWindowID, in: repository)
        register(secondOld, tabID: secondTabID, windowID: secondWindowID, in: repository)
        let staleSecondGeneration = repository.queries.generation(for: secondTabID)
        _ = repository.placement.promoteTrackedWebViewToPrimary(
            owner: .init(tabID: secondTabID, windowID: secondWindowID),
            expectedWebView: secondOld
        )
        repository.placement.noteParkedWebView(WKWebView(), for: secondTabID)
        var didValidateModel = false
        var didCommitModel = false

        let result = repository.beginReplacementBatch(
            [
                .init(
                    tabID: firstTabID,
                    expectedGeneration: repository.queries.generation(for: firstTabID),
                    placement: .windowSet(
                        webViewsByWindowID: [firstWindowID: firstReplacement],
                        primaryWindowID: firstWindowID
                    )
                ),
                .init(
                    tabID: secondTabID,
                    expectedGeneration: staleSecondGeneration,
                    placement: .windowSet(
                        webViewsByWindowID: [secondWindowID: secondReplacement],
                        primaryWindowID: secondWindowID
                    )
                ),
            ],
            validateModel: {
                didValidateModel = true
                return true
            },
            modelCommit: { didCommitModel = true }
        )

        guard case .stale(let tabID, _) = result else {
            return XCTFail("Expected whole-batch stale rejection")
        }
        XCTAssertEqual(tabID, secondTabID)
        XCTAssertFalse(didValidateModel)
        XCTAssertFalse(didCommitModel)
        XCTAssertIdentical(repository.queries.webView(for: firstTabID, in: firstWindowID), firstOld)
        XCTAssertIdentical(repository.queries.webView(for: secondTabID, in: secondWindowID), secondOld)
        XCTAssertNil(repository.residence(of: firstReplacement))
        XCTAssertNil(repository.residence(of: secondReplacement))
    }

    func testReplacementBatchConflictsWithAffectedTabPendingCleanup() throws {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        let pendingCleanup = WKWebView()
        register(oldWebView, tabID: tabID, windowID: windowID, in: repository)
        let cleanupLease = try XCTUnwrap(
            repository.beginPendingCleanup(of: pendingCleanup, for: tabID)
        )
        var didValidateModel = false

        let result = repository.beginWindowSetReplacement(
            for: tabID,
            expectedGeneration: repository.queries.generation(for: tabID),
            webViewsByWindowID: [windowID: replacement],
            primaryWindowID: windowID
        )
        if case .began = result {
            return XCTFail("Pending cleanup must block same-tab replacement")
        }
        guard case .conflict(let conflictTabID) = result else {
            return XCTFail("Expected pending-cleanup replacement conflict")
        }
        XCTAssertEqual(conflictTabID, tabID)
        XCTAssertFalse(didValidateModel)
        XCTAssertIdentical(repository.queries.webView(for: tabID, in: windowID), oldWebView)
        XCTAssertNil(repository.residence(of: replacement))

        XCTAssertTrue(
            repository.consumePendingCleanup(
                of: pendingCleanup,
                lease: cleanupLease
            )
        )
        let retry = repository.beginReplacementBatch(
            [
                .init(
                    tabID: tabID,
                    expectedGeneration: repository.queries.generation(for: tabID),
                    placement: .windowSet(
                        webViewsByWindowID: [windowID: replacement],
                        primaryWindowID: windowID
                    )
                ),
            ],
            validateModel: {
                didValidateModel = true
                return true
            }
        )
        guard case .began(let lease) = retry else {
            return XCTFail("Replacement should retry after cleanup settlement")
        }
        XCTAssertTrue(didValidateModel)
        _ = repository.rollbackReplacementBatch(lease)
    }

    func testThrowingModelCommitInternallyRollsBackRepositoryBatch() {
        enum ExpectedFailure: Error { case failed }

        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        register(oldWebView, tabID: tabID, windowID: windowID, in: repository)
        var modelRollbackSawRepositoryQuarantine = false

        let result = repository.beginReplacementBatch(
            [
                .init(
                    tabID: tabID,
                    expectedGeneration: repository.queries.generation(for: tabID),
                    placement: .windowSet(
                        webViewsByWindowID: [windowID: replacement],
                        primaryWindowID: windowID
                    )
                ),
            ],
            modelCommit: { throw ExpectedFailure.failed },
            modelRollback: {
                modelRollbackSawRepositoryQuarantine = repository.queries
                    .webView(for: tabID, in: windowID) === replacement
                    && {
                        if case .retiring = repository.residence(
                            of: oldWebView
                        ) {
                            return true
                        }
                        return false
                    }()
            }
        )

        guard case .modelCommitFailed(let discarded) = result else {
            return XCTFail("Expected model failure to reject the batch")
        }
        XCTAssertIdentical(
            discarded[tabID]?.windowWebViews[windowID],
            replacement
        )
        XCTAssertIdentical(repository.queries.webView(for: tabID, in: windowID), oldWebView)
        XCTAssertEqual(
            repository.residence(of: oldWebView),
            .window(.init(tabID: tabID, windowID: windowID))
        )
        XCTAssertNil(repository.residence(of: replacement))
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
        XCTAssertTrue(modelRollbackSawRepositoryQuarantine)
    }

    func testModelValidationFailureLeavesPreparedReplacementCallerOwned() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        register(oldWebView, tabID: tabID, windowID: windowID, in: repository)
        var modelCommitCount = 0
        var modelRollbackCount = 0

        let result = repository.beginReplacementBatch(
            [
                .init(
                    tabID: tabID,
                    expectedGeneration: repository.queries.generation(
                        for: tabID
                    ),
                    placement: .windowSet(
                        webViewsByWindowID: [windowID: replacement],
                        primaryWindowID: windowID
                    )
                ),
            ],
            validateModel: { false },
            modelCommit: { modelCommitCount += 1 },
            modelRollback: { modelRollbackCount += 1 }
        )

        guard case .modelValidationFailed = result else {
            return XCTFail("Expected pre-apply model rejection")
        }
        XCTAssertEqual(modelCommitCount, 0)
        XCTAssertEqual(modelRollbackCount, 0)
        XCTAssertIdentical(
            repository.queries.webView(for: tabID, in: windowID),
            oldWebView
        )
        XCTAssertNil(repository.residence(of: replacement))
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testThrowingFailedCommitCompensationQuarantinesBothGenerations() {
        enum ExpectedFailure: Error { case failed }

        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        register(oldWebView, tabID: tabID, windowID: windowID, in: repository)

        let result = repository.beginReplacementBatch(
            [
                .init(
                    tabID: tabID,
                    expectedGeneration: repository.queries.generation(
                        for: tabID
                    ),
                    placement: .windowSet(
                        webViewsByWindowID: [windowID: replacement],
                        primaryWindowID: windowID
                    )
                ),
            ],
            modelCommit: { throw ExpectedFailure.failed },
            modelRollback: { throw ExpectedFailure.failed }
        )

        guard case .modelRollbackFailed(let lease) = result else {
            return XCTFail("Expected typed failed-compensation quarantine")
        }
        XCTAssertIdentical(
            repository.queries.webView(for: tabID, in: windowID),
            replacement
        )
        guard case .retiring = repository.residence(of: oldWebView) else {
            return XCTFail("Predecessor must remain retirement-owned")
        }
        XCTAssertEqual(
            repository.residence(of: replacement),
            .window(.init(tabID: tabID, windowID: windowID))
        )
        guard case .noLongerActive = repository.rollbackReplacementBatch(
            lease
        ) else {
            return XCTFail("Claimed rollback must reject a second settlement")
        }

        let drained = repository.takeAllWebViewsForTerminalShutdown()
        XCTAssertEqual(
            Set(drained.map { ObjectIdentifier($0.webView) }),
            Set([oldWebView, replacement].map(ObjectIdentifier.init))
        )
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testTerminalDrainDuringModelCommitReturnsNoActiveReplacementLease() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        register(oldWebView, tabID: tabID, windowID: windowID, in: repository)
        var drained: [WebViewTerminalCleanupEntry] = []
        var drainedBatchID: UUID?

        let result = repository.beginReplacementBatch(
            [
                .init(
                    tabID: tabID,
                    expectedGeneration: repository.queries.generation(
                        for: tabID
                    ),
                    placement: .windowSet(
                        webViewsByWindowID: [windowID: replacement],
                        primaryWindowID: windowID
                    )
                ),
            ],
            modelCommit: {
                guard case .retiring(let lease) = repository.residence(
                    of: oldWebView
                ) else {
                    return XCTFail("Model commit must see quarantined predecessor")
                }
                drainedBatchID = lease.batchID
                drained = repository.takeAllWebViewsForTerminalShutdown()
            }
        )

        guard case .noLongerActive = result else {
            return XCTFail("Terminal drain must reject the vanished batch")
        }
        XCTAssertEqual(
            Set(drained.map { ObjectIdentifier($0.webView) }),
            Set([oldWebView, replacement].map(ObjectIdentifier.init))
        )
        XCTAssertTrue(repository.snapshot(for: tabID).allKnownWebViews.isEmpty)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
        guard let drainedBatchID else {
            return XCTFail("Drain must preserve the exact batch identity")
        }
        let staleLease = WebViewReplacementBatchLease(id: drainedBatchID)
        guard case .noLongerActive = repository.commitReplacementBatch(
            staleLease
        ) else {
            return XCTFail("Drained replacement lease must stay inactive")
        }
        guard case .noLongerActive = repository.rollbackReplacementBatch(
            staleLease
        ) else {
            return XCTFail("Drained replacement lease must not restore runtime")
        }
    }

    func testTerminalDrainThenThrowDuringModelCommitIsTypedLeaseLoss() {
        enum ExpectedFailure: Error { case failed }

        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        register(oldWebView, tabID: tabID, windowID: windowID, in: repository)

        let result = repository.beginReplacementBatch(
            [
                .init(
                    tabID: tabID,
                    expectedGeneration: repository.queries.generation(
                        for: tabID
                    ),
                    placement: .windowSet(
                        webViewsByWindowID: [windowID: replacement],
                        primaryWindowID: windowID
                    )
                ),
            ],
            modelCommit: {
                _ = repository.takeAllWebViewsForTerminalShutdown()
                throw ExpectedFailure.failed
            }
        )

        guard case .noLongerActive = result else {
            return XCTFail("Terminal drain must dominate model rejection")
        }
        XCTAssertTrue(repository.snapshot(for: tabID).allKnownWebViews.isEmpty)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testTerminalDrainDuringModelRollbackOwnsBothGenerations() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        repository.noteUntrackedWebView(oldWebView, for: tabID)
        guard case .began(let lease) = repository.beginReplacementBatch(
            [
                .init(
                    tabID: tabID,
                    expectedGeneration: repository.snapshot(
                        for: tabID
                    ).generation,
                    placement: .detached(
                        webView: replacement,
                        residence: .untracked
                    )
                ),
            ]
        ) else {
            return XCTFail("Expected replacement lease")
        }
        var drained: [WebViewTerminalCleanupEntry] = []

        let result = repository.rollbackReplacementBatch(
            lease,
            modelRollback: {
                guard case .retiring = repository.residence(of: oldWebView)
                else {
                    return XCTFail(
                        "Predecessor must stay quarantined during model rollback"
                    )
                }
                XCTAssertEqual(
                    repository.residence(of: replacement),
                    .untracked(tabID: tabID)
                )
                drained = repository.takeAllWebViewsForTerminalShutdown()
            }
        )

        guard case .terminallyDrained = result else {
            return XCTFail("Expected typed rollback drain")
        }
        XCTAssertEqual(
            Set(drained.map { ObjectIdentifier($0.webView) }),
            Set([oldWebView, replacement].map(ObjectIdentifier.init))
        )
        XCTAssertTrue(repository.snapshot(for: tabID).allKnownWebViews.isEmpty)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testThrowingModelRollbackStaysQuarantinedWithoutCrashing() {
        enum ExpectedFailure: Error { case failed }

        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        repository.noteUntrackedWebView(oldWebView, for: tabID)
        guard case .began(let lease) = repository.beginReplacementBatch(
            [
                .init(
                    tabID: tabID,
                    expectedGeneration: repository.snapshot(
                        for: tabID
                    ).generation,
                    placement: .detached(
                        webView: replacement,
                        residence: .untracked
                    )
                ),
            ]
        ) else {
            return XCTFail("Expected replacement lease")
        }

        let result = repository.rollbackReplacementBatch(
            lease,
            modelRollback: {
                guard case .retiring = repository.residence(of: oldWebView)
                else {
                    return XCTFail("Rollback must run inside repository lease")
                }
                XCTAssertEqual(
                    repository.residence(of: replacement),
                    .untracked(tabID: tabID)
                )
                throw ExpectedFailure.failed
            }
        )

        guard case .modelRollbackFailed = result else {
            return XCTFail("Expected typed model rollback failure")
        }
        XCTAssertIdentical(repository.untrackedWebView(for: tabID), replacement)
        guard case .retiring = repository.residence(of: oldWebView) else {
            return XCTFail("Failed rollback must retain predecessor quarantine")
        }
        let drained = repository.takeAllWebViewsForTerminalShutdown()
        XCTAssertEqual(
            Set(drained.map { ObjectIdentifier($0.webView) }),
            Set([oldWebView, replacement].map(ObjectIdentifier.init))
        )
    }

    func testUnifiedBarrierWaitsForCleanupAndRetirementSettlement() async throws {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let cleanupTabID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        let pendingCleanup = WKWebView()
        register(oldWebView, tabID: tabID, windowID: windowID, in: repository)
        guard case .began(let replacementLease) = repository
            .beginWindowSetReplacement(
                for: tabID,
                expectedGeneration: repository.queries.generation(for: tabID),
                webViewsByWindowID: [windowID: replacement],
                primaryWindowID: windowID
            ) else {
            return XCTFail("Expected replacement batch")
        }
        let cleanupLease = try XCTUnwrap(
            repository.beginPendingCleanup(
                of: pendingCleanup,
                for: cleanupTabID
            )
        )
        XCTAssertTrue(repository.hasOwnershipTransition(for: tabID))
        XCTAssertTrue(repository.hasOwnershipTransition(for: cleanupTabID))
        var barrierResult: Bool?
        let barrier = Task { @MainActor in
            let result = await repository.waitUntilOwnershipTransitionsAreSettled()
            barrierResult = result
            return result
        }
        await Task.yield()

        _ = repository.commitReplacementBatch(replacementLease)
        await Task.yield()
        XCTAssertFalse(repository.hasOwnershipTransition(for: tabID))
        XCTAssertTrue(repository.hasOwnershipTransition(for: cleanupTabID))
        XCTAssertNil(barrierResult)

        XCTAssertTrue(
            repository.consumePendingCleanup(
                of: pendingCleanup,
                lease: cleanupLease
            )
        )
        XCTAssertFalse(repository.hasOwnershipTransition(for: cleanupTabID))
        let didCrossBarrier = await barrier.value
        XCTAssertTrue(didCrossBarrier)
        XCTAssertEqual(barrierResult, true)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testTerminalShutdownDrainsActiveAndRetiringGenerationsOnce() async {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        register(oldWebView, tabID: tabID, windowID: windowID, in: repository)
        guard case .began(let lease) = repository.beginWindowSetReplacement(
            for: tabID,
            expectedGeneration: repository.queries.generation(for: tabID),
            webViewsByWindowID: [windowID: replacement],
            primaryWindowID: windowID
        ) else {
            return XCTFail("Expected replacement batch")
        }
        let barrier = Task { @MainActor in
            await repository.waitUntilOwnershipTransitionsAreSettled()
        }
        await Task.yield()

        let drained = repository.takeAllWebViewsForTerminalShutdown()

        XCTAssertEqual(drained.count, 2)
        let drainedByID = Dictionary(
            uniqueKeysWithValues: drained.map { (ObjectIdentifier($0.webView), $0) }
        )
        XCTAssertEqual(
            drainedByID[ObjectIdentifier(replacement)]?.residence,
            .window(.init(tabID: tabID, windowID: windowID))
        )
        guard case .retiring(let retirementLease)? = drainedByID[
            ObjectIdentifier(oldWebView)
        ]?.residence else {
            return XCTFail("Terminal drain must include the retiring generation")
        }
        XCTAssertEqual(retirementLease.batchID, lease.id)
        let didCrossBarrier = await barrier.value
        XCTAssertFalse(didCrossBarrier)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
        guard case .noLongerActive = repository.commitReplacementBatch(lease) else {
            return XCTFail("Terminal drain must consume the replacement lease")
        }
        XCTAssertTrue(repository.takeAllWebViewsForTerminalShutdown().isEmpty)
    }

    func testRuntimeOwnedTabIDsIncludeActiveRetiringAndPendingCleanupOnlyOnce() throws {
        let repository = WebViewSessionRepository()
        let replacingTabID = UUID()
        let pendingOnlyTabID = UUID()
        let windowID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        register(
            oldWebView,
            tabID: replacingTabID,
            windowID: windowID,
            in: repository
        )
        guard case .began = repository.beginWindowSetReplacement(
            for: replacingTabID,
            expectedGeneration: repository.queries.generation(for: replacingTabID),
            webViewsByWindowID: [windowID: replacement],
            primaryWindowID: windowID
        ) else {
            return XCTFail("Expected replacement batch")
        }
        _ = try XCTUnwrap(
            repository.beginPendingCleanup(
                of: WKWebView(),
                for: pendingOnlyTabID
            )
        )

        XCTAssertEqual(
            repository.runtimeOwnedTabIDs,
            [replacingTabID, pendingOnlyTabID]
        )
    }

    private func lifecycleRegistration(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        repository: WebViewSessionRepository,
        canDisplace: @escaping (WKWebView) -> Bool,
        sideEffect: @escaping () -> Void
    ) -> WebViewTrackedRegistrationResult {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: owner,
            in: repository,
            removeFromContainers: { _ in sideEffect() },
            installRuntimeObservations: { _ in sideEffect() },
            uninstallRuntimeObservationsIfUntracked: { _ in sideEffect() },
            pruneInvalidDeferredCommands: { _ in sideEffect() },
            canDisplaceWebView: canDisplace,
            removeRecentVisibility: { _ in sideEffect() },
            didCommitPlacement: sideEffect,
            cleanupDisplacedWebView: { _, _ in sideEffect() }
        )
    }

    private func register(
        _ webView: WKWebView,
        tabID: UUID,
        windowID: UUID,
        in repository: WebViewSessionRepository
    ) {
        register(
            webView,
            owner: .init(tabID: tabID, windowID: windowID),
            in: repository
        )
    }

    private func register(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        in repository: WebViewSessionRepository
    ) {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: owner,
            in: repository,
            removeFromContainers: { _ in },
            installRuntimeObservations: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in },
            cleanupDisplacedWebView: { _, _ in }
        )
    }

    private func assertTrackedWebViews(
        _ expectedByTabID: [UUID: WKWebView],
        in windowID: UUID,
        repository: WebViewSessionRepository,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tracked = repository.trackedWebViews(in: windowID)
        XCTAssertEqual(tracked.count, expectedByTabID.count, file: file, line: line)

        var actualTabIDs: Set<UUID> = []
        for (owner, webView) in tracked {
            XCTAssertEqual(owner.windowID, windowID, file: file, line: line)
            guard let expectedWebView = expectedByTabID[owner.tabID] else {
                XCTFail("Unexpected tab in tracked-window index", file: file, line: line)
                continue
            }
            XCTAssertTrue(actualTabIDs.insert(owner.tabID).inserted, file: file, line: line)
            XCTAssertIdentical(webView, expectedWebView, file: file, line: line)
        }
        XCTAssertEqual(actualTabIDs, Set(expectedByTabID.keys), file: file, line: line)
    }
}
