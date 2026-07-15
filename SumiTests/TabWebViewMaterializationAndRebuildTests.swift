import Combine
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewMaterializationAndRebuildTests: XCTestCase {
    func testRefreshPrimarySelectsAnAlreadyRegisteredCandidate() {
        let repository = WebViewSessionRepository()
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let windowID = UUID()
        let webView = WKWebView()
        register(webView, tabID: tab.id, windowID: windowID, in: repository)

        makeMaterializationService(
            repository: repository,
            primaryCandidate: { _ in
                (.init(tabID: tab.id, windowID: windowID), webView)
            }
        ).refreshPrimary(
            for: tab
        )

        XCTAssertEqual(tab.webViewSession.primaryWindowID, windowID)
        XCTAssertIdentical(tab.webViewSession.primaryWebView, webView)
    }

    func testCreatePrimaryForFileURLInvokesInitialDocumentHandoff() throws {
        let browserManager = BrowserManager()
        let repository = browserManager.webViewSessions
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(fileURLWithPath: "/tmp/sumi-create-primary/index.html"),
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = browserManager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let parked = try XCTUnwrap(
            tab.makeNormalTabWebView(
                reason: "TabWebViewMaterializationAndRebuildTests.parked"
            )
        )
        // Parked staging belongs to the normal surface family but is not an
        // active policy candidate. Explicitly abandon its provisional receipt
        // before placing it outside the canonical generation.
        tab.cancelConfigurationPolicy(for: [parked])
        XCTAssertNil(parked.sumiPreparedConfigurationPolicyChange)
        tab.parkExistingWebView(parked)
        let windowID = UUID()
        let created = try XCTUnwrap(
            makeMaterializationService(repository: repository).webView(
                for: tab,
                in: windowID
            )
        )

        XCTAssertFalse(created === parked)
        XCTAssertIdentical(repository.webView(for: tab.id, in: windowID), created)
        XCTAssertIdentical(tab.webViewSession.primaryWebView, created)
        XCTAssertEqual(tab.configurationPolicyLedger.revision, 1)
        XCTAssertNotEqual(tab.configurationPolicyLedger.committedState, .unknown)
    }

    func testAdoptingUntrackedPrimaryReschedulesInitialDocumentForTrackedResidence() {
        let repository = WebViewSessionRepository()
        let targetURL = URL(string: "https://example.com/adopt-primary")!
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        let windowID = UUID()
        let adopted = makeMaterializationService(repository: repository).webView(
            for: tab,
            in: windowID
        )

        XCTAssertIdentical(adopted, webView)
        XCTAssertEqual(
            repository.residence(of: webView),
            .window(.init(tabID: tab.id, windowID: windowID))
        )
    }

    func testLiveReplacementRunsRuntimePreparationAfterCanonicalCommit() throws {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let repository = browserManager.webViewSessions
        let webViewRuntime = browserManager.testWebViewRuntime()
        let replacementService = webViewRuntime.extensionTabWebViewReplacement
        let untrackedInstallation =
            webViewRuntime.untrackedWebViewInstallationService
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/extension-replacement")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = browserManager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let previous = WKWebView()
        XCTAssertEqual(
            untrackedInstallation.installUntracked(previous, for: tab),
            .committed
        )
        var preparationSawCanonicalResidence = false

        let replacement = try XCTUnwrap(
            replacementService.replace(
                for: tab,
                in: nil,
                reason: "TabWebViewMaterializationAndRebuildTests.replacement",
                prepareCommittedReplacement: { webView in
                    preparationSawCanonicalResidence =
                        repository.untrackedWebView(for: tab.id) === webView
                },
                validate: { _ in true }
            ).committedWebView
        )

        XCTAssertTrue(preparationSawCanonicalResidence)
        XCTAssertFalse(replacement === previous)
        XCTAssertIdentical(repository.untrackedWebView(for: tab.id), replacement)
        XCTAssertNil(repository.residence(of: previous))
    }

    func testTrackedLiveReplacementRunsRuntimePreparationAfterCanonicalCommit() throws {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let repository = browserManager.webViewSessions
        let runtime = browserManager.testWebViewRuntime()
        let trackedAdmission = runtime.trackedWebViewAdmission
        let replacementService = runtime.extensionTabWebViewReplacement
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/tracked-extension-replacement")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = browserManager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let windowID = UUID()
        let previous = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.tracked-live-previous")
        )
        XCTAssertTrue(
            trackedAdmission.attemptAssignment(
                previous,
                to: tab,
                in: windowID,
                replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
            ).isAccepted
        )
        var preparationSawCanonicalResidence = false

        let replacement = try XCTUnwrap(
            replacementService.replace(
                for: tab,
                in: windowID,
                reason: "TabWebViewMaterializationAndRebuildTests.trackedReplacement",
                prepareCommittedReplacement: { webView in
                    preparationSawCanonicalResidence =
                        repository.webView(for: tab.id, in: windowID) === webView
                },
                validate: { _ in true }
            ).committedWebView
        )

        XCTAssertTrue(preparationSawCanonicalResidence)
        XCTAssertFalse(replacement === previous)
        XCTAssertIdentical(repository.webView(for: tab.id, in: windowID), replacement)
        XCTAssertNil(repository.residence(of: previous))
    }

    func testTrackedAssignmentRejectsRawWebViewBeforeRepositoryMutation() {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let repository = browserManager.webViewSessions
        let trackedAdmission = browserManager.testWebViewRuntime().trackedWebViewAdmission
        let tab = browserManager.tabManager.tabFactory.makeTab(
            loadsCachedFaviconOnInit: false
        )
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        configuration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let rawNormalWebView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        XCTAssertEqual(
            trackedAdmission.attemptAssignment(
                rawNormalWebView,
                to: tab,
                in: UUID(),
                replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
            ),
            .rejected(.physicalTabIdentityMismatch)
        )
        XCTAssertNil(repository.residence(of: rawNormalWebView))
        XCTAssertTrue(tab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertEqual(tab.configurationPolicyLedger.revision, 0)
    }

    func testCanonicalPlacementRejectsPolicyReceiptFromAnotherTab() throws {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let repository = browserManager.webViewSessions
        let trackedAdmission = browserManager.testWebViewRuntime().trackedWebViewAdmission
        let preparingTab = browserManager.tabManager.tabFactory.makeTab(
            loadsCachedFaviconOnInit: false
        )
        let receivingTab = browserManager.tabManager.tabFactory.makeTab(
            loadsCachedFaviconOnInit: false
        )
        let profileID = try XCTUnwrap(browserManager.currentProfile?.id)
        for tab in [preparingTab, receivingTab] {
            tab.profileId = profileID
            tab.attachBrowserRuntime(
                TabBrowserRuntimeFactory.make(for: browserManager)
            )
        }
        let foreignCandidate = try XCTUnwrap(
            preparingTab.makeNormalTabWebView(
                reason: "test.foreign-policy-candidate"
            ) as? FocusableWKWebView
        )
        let receipt = try XCTUnwrap(
            foreignCandidate.sumiPreparedConfigurationPolicyChange
        )
        foreignCandidate.owningTab = receivingTab

        XCTAssertFalse(
            trackedAdmission.attemptAssignment(
                foreignCandidate,
                to: receivingTab,
                in: UUID(),
                replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
            ).isAccepted
        )
        XCTAssertNil(repository.residence(of: foreignCandidate))
        XCTAssertEqual(receipt.phase, .prepared)
        XCTAssertEqual(preparingTab.configurationPolicyLedger.revision, 0)
        XCTAssertEqual(receivingTab.configurationPolicyLedger.revision, 0)
        preparingTab.cancelConfigurationPolicy(for: [foreignCandidate])
        preparingTab.cleanupCloneWebView(foreignCandidate)
    }

    func testCanonicalPlacementReturnsProtectedCandidateWithoutMutation() {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let runtime = browserManager.testWebViewRuntime()
        let repository = browserManager.webViewSessions
        let tab = browserManager.tabManager.tabFactory.makeTab(
            loadsCachedFaviconOnInit: false
        )
        let sourceWindowID = UUID()
        let targetWindowID = UUID()
        let candidate = FocusableWKWebView()
        candidate.owningTab = tab
        XCTAssertTrue(
            runtime.trackedWebViewAdmission.attemptAssignment(
                candidate,
                to: tab,
                in: sourceWindowID,
                replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
            ).isAccepted
        )
        let generation = tab.webViewSession.generation
        let protection = runtime.mediaProtectionOwner
            .beginVisualHandoffProtection(for: candidate)
        defer {
            _ = runtime.mediaProtectionOwner.finishVisualHandoffProtection(
                protection
            )
        }

        XCTAssertEqual(
            runtime.canonicalWebViewPlacement.placeAuxiliaryTracked(
                candidate,
                for: tab,
                in: targetWindowID,
                promoteToPrimary: true
            ),
            .rejected(.trackedRegistration(.protectedCandidate))
        )
        XCTAssertIdentical(
            repository.webView(for: tab.id, in: sourceWindowID),
            candidate
        )
        XCTAssertNil(repository.webView(for: tab.id, in: targetWindowID))
        XCTAssertEqual(tab.webViewSession.generation, generation)
    }

    func testProtectedOccupantRejectsAndCancelsExactPolicyAdmission() throws {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let runtime = browserManager.testWebViewRuntime()
        let repository = browserManager.webViewSessions
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/protected-placement")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = try XCTUnwrap(browserManager.currentProfile?.id)
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        let windowID = UUID()
        let occupant = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.protected-occupant")
        )
        XCTAssertTrue(
            runtime.trackedWebViewAdmission.attemptAssignment(
                occupant,
                to: tab,
                in: windowID,
                replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
            ).isAccepted
        )
        let generation = tab.webViewSession.generation
        let policyRevision = tab.configurationPolicyLedger.revision
        let committedPolicy = tab.configurationPolicyLedger.committedState
        let candidate = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.protected-replacement")
        )
        let candidateReceipt = try XCTUnwrap(
            candidate.sumiPreparedConfigurationPolicyChange
        )
        let protection = runtime.mediaProtectionOwner
            .beginVisualHandoffProtection(for: occupant)
        defer {
            _ = runtime.mediaProtectionOwner.finishVisualHandoffProtection(
                protection
            )
            tab.cleanupCloneWebView(candidate)
        }

        XCTAssertEqual(
            runtime.canonicalWebViewPlacement.placeNormalTracked(
                candidate,
                for: tab,
                in: windowID,
                promoteToPrimary: true
            ),
            .rejected(.trackedRegistration(.protectedTrackedOccupant))
        )
        XCTAssertIdentical(repository.webView(for: tab.id, in: windowID), occupant)
        XCTAssertNil(repository.residence(of: candidate))
        XCTAssertEqual(tab.webViewSession.generation, generation)
        XCTAssertEqual(tab.configurationPolicyLedger.revision, policyRevision)
        XCTAssertEqual(tab.configurationPolicyLedger.committedState, committedPolicy)
        XCTAssertEqual(candidateReceipt.phase, .cancelled)
        XCTAssertNil(candidate.sumiPreparedConfigurationPolicyChange)
    }

    func testCanonicalAuxiliaryPlacementCancelsSameTabPolicyEvidence() {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let runtime = browserManager.testWebViewRuntime()
        let repository = browserManager.webViewSessions
        let tab = browserManager.tabManager.tabFactory.makeTab(
            loadsCachedFaviconOnInit: false
        )
        let sourceWindowID = UUID()
        let targetWindowID = UUID()
        let candidate = FocusableWKWebView()
        candidate.owningTab = tab
        XCTAssertTrue(
            runtime.trackedWebViewAdmission.attemptAssignment(
                candidate,
                to: tab,
                in: sourceWindowID,
                replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
            ).isAccepted
        )
        let generation = tab.webViewSession.generation
        let receipt = tab.configurationPolicyLedger.prepare(
            .unknown,
            expectedSessionGeneration: generation
        )
        candidate.sumiPreparedConfigurationPolicyChange = receipt

        XCTAssertEqual(
            runtime.canonicalWebViewPlacement.placeAuxiliaryTracked(
                candidate,
                for: tab,
                in: targetWindowID,
                promoteToPrimary: true
            ),
            .rejected(.unexpectedPolicyEvidence)
        )
        XCTAssertEqual(receipt.phase, .cancelled)
        XCTAssertNil(candidate.sumiPreparedConfigurationPolicyChange)
        XCTAssertIdentical(
            repository.webView(for: tab.id, in: sourceWindowID),
            candidate
        )
        XCTAssertNil(repository.webView(for: tab.id, in: targetWindowID))
        XCTAssertEqual(tab.webViewSession.generation, generation)
        XCTAssertEqual(tab.configurationPolicyLedger.revision, 0)
    }

    func testMaterializationCommitsAdditionalCloneThroughExactPlacement() throws {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let repository = browserManager.webViewSessions
        let trackedAdmission = browserManager.testWebViewRuntime().trackedWebViewAdmission
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/clone-placement")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = try XCTUnwrap(browserManager.currentProfile?.id)
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        let primaryWindowID = UUID()
        let cloneWindowID = UUID()

        let primary = try XCTUnwrap(
            trackedAdmission.webView(for: tab, in: primaryWindowID)
        )
        let committedRevision = tab.configurationPolicyLedger.revision
        let clone = try XCTUnwrap(
            trackedAdmission.webView(for: tab, in: cloneWindowID)
        )

        XCTAssertFalse(primary === clone)
        XCTAssertIdentical(
            repository.webView(for: tab.id, in: primaryWindowID),
            primary
        )
        XCTAssertIdentical(
            repository.webView(for: tab.id, in: cloneWindowID),
            clone
        )
        XCTAssertEqual(tab.webViewSession.allKnownWebViews.count, 2)
        XCTAssertEqual(tab.configurationPolicyLedger.revision, committedRevision)
        XCTAssertNil(clone.sumiPreparedConfigurationPolicyChange)
    }

    func testDetachedReplacementRejectsCancelledPolicyWithoutPlacement() throws {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let repository = browserManager.webViewSessions
        let webViewRuntime = browserManager.testWebViewRuntime()
        let detachedReplacement = webViewRuntime.detachedWebViewReplacement
        let untrackedInstallation =
            webViewRuntime.untrackedWebViewInstallationService
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/detached-rollback")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = try XCTUnwrap(browserManager.currentProfile?.id)
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        let previous = WKWebView()
        XCTAssertEqual(
            untrackedInstallation.installUntracked(previous, for: tab),
            .committed
        )
        let replacement = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.cancelled-detached")
        )
        tab.cancelConfigurationPolicy(for: [replacement])

        XCTAssertEqual(
            detachedReplacement.replace(
                previous,
                with: replacement,
                for: tab
            ),
            .rejected
        )
        XCTAssertIdentical(tab.webViewSession.untrackedWebView, previous)
        XCTAssertNil(repository.residence(of: replacement))
        XCTAssertEqual(tab.configurationPolicyLedger.revision, 0)
        tab.cleanupCloneWebView(replacement)
    }

    func testDetachedReplacementReportsConsumedAfterSynchronousPolicyRollback()
        throws {
        let repository = WebViewSessionRepository()
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/detached-settlement-rollback")
        )
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let previous = WKWebView()
        repository.noteUntrackedWebView(previous, for: tab.id)
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        configuration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let replacement = WKWebView(frame: .zero, configuration: configuration)
        let receipt = tab.configurationPolicyLedger.prepare(
            TabConfigurationPolicyState(
                profileID: nil,
                websiteDataStoreIdentity: ObjectIdentifier(
                    replacement.configuration.websiteDataStore
                ),
                protectionAttachment: nil,
                safariContentBlockerAttachment: nil,
                autoplayState: .allowAll
            ),
            expectedSessionGeneration: tab.webViewSession.generation
        )
        replacement.sumiPreparedConfigurationPolicyChange = receipt
        let changeSet = try XCTUnwrap(
            tab.preparedConfigurationPolicyChangeSet(for: [replacement])
        )
        var destroyed: [ObjectIdentifier] = []
        let retiredGenerationDestroyer = WebViewRetiredGenerationDestroyer(
            runtime: .init(
                webViewSessions: repository,
                retireNavigationGeneration: { tabID, webViews, _ in
                    XCTAssertEqual(tabID, tab.id)
                    XCTAssertEqual(
                        webViews.map(ObjectIdentifier.init),
                        [ObjectIdentifier(replacement)]
                    )
                },
                destroy: { tabID, webView in
                    XCTAssertEqual(tabID, tab.id)
                    destroyed.append(ObjectIdentifier(webView))
                },
                uninstallObservationsIfUntracked: { _ in }
            )
        )
        let pipeline = WebViewReplacementPipeline(runtime: .init(
            webViewSessions: repository,
            quiesce: { webView in
                XCTAssertIdentical(webView, previous)
                changeSet.cancel()
            },
            retiredGenerationDestroyer: retiredGenerationDestroyer,
            restore: { _, _ in }
        ))
        let service = DetachedWebViewReplacementService(
            runtimeTabs: WebViewRuntimeTabRegistry(
                webViewSessions: repository
            ),
            webViewSessions: repository,
            pipeline: pipeline
        )

        XCTAssertEqual(
            service.replace(previous, with: replacement, for: tab),
            .consumedByFailedTransaction
        )
        XCTAssertIdentical(tab.webViewSession.untrackedWebView, previous)
        XCTAssertNil(repository.residence(of: replacement))
        XCTAssertEqual(destroyed, [ObjectIdentifier(replacement)])
        XCTAssertEqual(receipt.phase, .cancelled)
        XCTAssertEqual(tab.configurationPolicyLedger.committedState, .unknown)
        XCTAssertEqual(tab.configurationPolicyLedger.revision, 0)
    }

    func testDetachedAuxiliaryReplacementRejectsForeignPolicyEvidence() {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let repository = browserManager.webViewSessions
        let webViewRuntime = browserManager.testWebViewRuntime()
        let detachedReplacement = webViewRuntime.detachedWebViewReplacement
        let untrackedInstallation =
            webViewRuntime.untrackedWebViewInstallationService
        let receivingTab = browserManager.tabManager.tabFactory.makeTab(
            loadsCachedFaviconOnInit: false
        )
        let foreignTab = browserManager.tabManager.tabFactory.makeTab(
            loadsCachedFaviconOnInit: false
        )
        let previous = WKWebView()
        XCTAssertEqual(
            untrackedInstallation.installUntracked(
                previous,
                for: receivingTab
            ),
            .committed
        )
        let replacement = WKWebView()
        let foreignReceipt = foreignTab.configurationPolicyLedger.prepare(
            .unknown,
            expectedSessionGeneration: foreignTab.webViewSession.generation
        )
        replacement.sumiPreparedConfigurationPolicyChange = foreignReceipt

        XCTAssertEqual(
            detachedReplacement.replace(
                previous,
                with: replacement,
                for: receivingTab
            ),
            .rejected
        )
        XCTAssertIdentical(receivingTab.webViewSession.untrackedWebView, previous)
        XCTAssertNil(repository.residence(of: replacement))
        XCTAssertEqual(foreignReceipt.phase, .prepared)
        XCTAssertIdentical(
            replacement.sumiPreparedConfigurationPolicyChange,
            foreignReceipt
        )
        XCTAssertEqual(receivingTab.configurationPolicyLedger.revision, 0)
        XCTAssertEqual(foreignTab.configurationPolicyLedger.revision, 0)

        foreignTab.cancelConfigurationPolicy(for: [replacement])
        receivingTab.cleanupCloneWebView(replacement)
    }

    func testTrackedInitialDocumentHandoffRejectsChangedWindowResidence() async {
        let repository = WebViewSessionRepository()
        let targetURL = URL(string: "https://example.com/tracked-initial")!
        let controller = AssignmentDelayedUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = AssignmentInitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let originalOwner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        let replacementOwner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        register(
            webView,
            tabID: originalOwner.tabID,
            windowID: originalOwner.windowID,
            in: repository
        )

        NormalTabInitialDocumentRuntimeHandoff.scheduleTrackedInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            expectedOwner: originalOwner,
            profileId: nil,
            registrationReason:
                "TabWebViewMaterializationAndRebuildTests.staleResidence",
            updatesTabPresentation: false
        )

        for _ in 0..<20 {
            await Task.yield()
            if controller.waitCallCount > 0 {
                break
            }
        }
        XCTAssertEqual(controller.waitCallCount, 1)

        register(
            webView,
            tabID: replacementOwner.tabID,
            windowID: replacementOwner.windowID,
            in: repository
        )
        XCTAssertEqual(repository.residence(of: webView), .window(replacementOwner))

        controller.finishInitialUserContentInstallation()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testGraphSettlementInvalidatesPermissionGenerationExactlyOnce() async throws {
        let repository = WebViewSessionRepository()
        let profile = Profile(name: "Permission Generation")
        let tab = Tab(
            url: URL(string: "https://example.com/permission-generation")!,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = profile.id
        tab.navigationRuntime.profileResolutionRuntime = TabProfileResolutionRuntime(
            ephemeralProfileForTab: { _, _ in nil },
            profile: { profileID in profileID == profile.id ? profile : nil },
            spaceProfile: { _ in nil },
            currentProfile: { profile },
            firstProfile: { profile }
        )
        let window = RebuildRuntimeWindowStub()
        let graph = makeWindowBoundRuntimeGraph(
            repository: repository,
            tab: tab,
            window: window
        )
        let oldWebView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "permission-generation.old")
        )
        register(oldWebView, tabID: tab.id, windowID: window.id, in: repository)
        let originalPageID = tab.currentPermissionPageId()
        let targetURL = URL(
            string: "https://example.com/permission-generation/rebuilt"
        )!
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        tab.url = targetURL

        let result = graph.rebuildService.rebuildLiveWebViewsResult(
            for: tab,
            preferredPrimaryWindowID: window.id,
            load: targetURL,
            reason: "permission-generation.rebuild"
        )

        XCTAssertEqual(result, .deferred)
        XCTAssertEqual(originalPageID, "\(tab.id.uuidString.lowercased()):0")
        await waitUntil {
            repository.residence(of: oldWebView) == nil
        }
        XCTAssertNil(repository.residence(of: oldWebView))
        XCTAssertEqual(
            tab.currentPermissionPageId(),
            "\(tab.id.uuidString.lowercased()):1"
        )
    }

    func testTrackedProfileAssignmentRejectsGenerationChangeDuringProvisioning() {
        let repository = WebViewSessionRepository()
        let oldProfile = Profile(name: "Old")
        let targetProfile = Profile(name: "Target")
        let tab = Tab(
            url: URL(string: "https://example.com/profile-tracked")!,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = oldProfile.id
        let oldState = SumiSafariContentBlockerAttachmentState.disabled(
            siteHost: "old.example"
        )
        let targetState = SumiSafariContentBlockerAttachmentState.disabled(
            siteHost: "target.example"
        )
        let oldConfiguration = WKWebViewConfiguration()
        oldConfiguration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let oldWebView = WKWebView(
            frame: .zero,
            configuration: oldConfiguration
        )
        commitConfigurationPolicy(
            on: tab,
            webView: oldWebView,
            profileID: oldProfile.id,
            safariAttachment: oldState
        )
        let window = RebuildRuntimeWindowStub()
        register(oldWebView, tabID: tab.id, windowID: window.id, in: repository)
        let concurrentParked = WKWebView()
        var didInvalidateGeneration = false
        attachProfileRuntime(
            to: tab,
            profiles: [oldProfile.id: oldProfile, targetProfile.id: targetProfile],
            safariState: {
                if didInvalidateGeneration == false {
                    didInvalidateGeneration = true
                    tab.webViewSession.park(concurrentParked)
                }
                return targetState
            }
        )
        let graph = makeWindowBoundRuntimeGraph(
            repository: repository,
            tab: tab,
            window: window
        )
        let intent = tab.profileAssignment.begin(
            desiredProfileID: targetProfile.id,
            resolvedProfileID: targetProfile.id,
            targetURL: tab.url,
            requiresStructuralPersistence: true
        )

        let outcome = graph.profileAssignmentService
            .executeProfileAssignment(
            for: tab,
            targetProfile: targetProfile,
            intent: intent,
            settlement: { _ in }
        )

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(tab.profileId, oldProfile.id)
        XCTAssertEqual(
            tab.safariContentBlockerAppliedAttachmentState,
            oldState
        )
        XCTAssertIdentical(repository.webView(for: tab.id, in: window.id), oldWebView)
        XCTAssertIdentical(
            tab.webViewSession.parkedWebView,
            concurrentParked
        )
        tab.profileAssignment.abort(intent)
    }

    func testDetachedProfileAssignmentRejectsGenerationChangeDuringProvisioning() {
        let repository = WebViewSessionRepository()
        let graph = makeTestWebViewRuntimeGraph(webViewSessions: repository)
        let oldProfile = Profile(name: "Old")
        let targetProfile = Profile(name: "Target")
        let tab = Tab(
            url: URL(string: "https://example.com/profile-detached")!,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = oldProfile.id
        let oldState = SumiSafariContentBlockerAttachmentState.disabled(
            siteHost: "old.example"
        )
        let targetState = SumiSafariContentBlockerAttachmentState.disabled(
            siteHost: "target.example"
        )
        let oldConfiguration = WKWebViewConfiguration()
        oldConfiguration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let oldWebView = WKWebView(
            frame: .zero,
            configuration: oldConfiguration
        )
        commitConfigurationPolicy(
            on: tab,
            webView: oldWebView,
            profileID: oldProfile.id,
            safariAttachment: oldState
        )
        tab.webViewSession.park(oldWebView)
        var didInvalidateGeneration = false
        attachProfileRuntime(
            to: tab,
            profiles: [oldProfile.id: oldProfile, targetProfile.id: targetProfile],
            safariState: {
                if didInvalidateGeneration == false {
                    didInvalidateGeneration = true
                    XCTAssertTrue(
                        tab.webViewSession.adoptParkedAsUntracked(oldWebView)
                    )
                }
                return targetState
            }
        )
        let intent = tab.profileAssignment.begin(
            desiredProfileID: targetProfile.id,
            resolvedProfileID: targetProfile.id,
            targetURL: tab.url,
            requiresStructuralPersistence: true
        )

        let outcome = graph.profileAssignmentService
            .executeProfileAssignment(
            for: tab,
            targetProfile: targetProfile,
            intent: intent,
            settlement: { _ in }
        )

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(tab.profileId, oldProfile.id)
        XCTAssertEqual(
            tab.safariContentBlockerAppliedAttachmentState,
            oldState
        )
        XCTAssertIdentical(
            tab.webViewSession.untrackedWebView,
            oldWebView
        )
        tab.profileAssignment.abort(intent)
    }

    func testCommittedReplacementRetiresWholeGenerationBeforeDestroyingIt()
        throws {
        let repository = WebViewSessionRepository()
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/replacement-commit")
        )
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let primaryWindowID = UUID()
        let cloneWindowID = UUID()
        let oldPrimary = WKWebView()
        let oldClone = WKWebView()
        let replacementConfiguration = WKWebViewConfiguration()
        replacementConfiguration.sumiIsNormalTabWebViewConfiguration = true
        replacementConfiguration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let replacement = WKWebView(
            frame: .zero,
            configuration: replacementConfiguration
        )
        register(
            oldPrimary,
            tabID: tab.id,
            windowID: primaryWindowID,
            in: repository
        )
        register(
            oldClone,
            tabID: tab.id,
            windowID: cloneWindowID,
            in: repository
        )

        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let primaryNavigation = try bindMainFrameParticipant(
            oldPrimary,
            to: tab
        )
        let cloneNavigation = try bindMainFrameParticipant(oldClone, to: tab)
        let replacementNavigation = try bindMainFrameParticipant(
            replacement,
            to: tab
        )
        guard case .publish = transaction.settleCommit(
            from: oldPrimary,
            navigationID: ObjectIdentifier(primaryNavigation),
            navigationLifetime: primaryNavigation,
            committedURL: targetURL
        ) else {
            return XCTFail("Expected old primary to publish the shared commit")
        }
        guard case .participant = transaction.settleCommit(
            from: oldClone,
            navigationID: ObjectIdentifier(cloneNavigation),
            navigationLifetime: cloneNavigation,
            committedURL: targetURL
        ) else {
            return XCTFail("Expected old clone to remain a recorded replica")
        }
        guard case .participant = transaction.settleCommit(
            from: replacement,
            navigationID: ObjectIdentifier(replacementNavigation),
            navigationLifetime: replacementNavigation,
            committedURL: targetURL
        ) else {
            return XCTFail("Expected replacement to remain a recorded replica")
        }

        let snapshot = repository.snapshot(for: tab.id)
        let committedPolicy = TabConfigurationPolicyState(
            profileID: nil,
            websiteDataStoreIdentity: ObjectIdentifier(
                replacement.configuration.websiteDataStore
            ),
            protectionAttachment: nil,
            safariContentBlockerAttachment: nil,
            autoplayState: .blockAll
        )
        replacement.sumiPreparedConfigurationPolicyChange =
            tab.configurationPolicyLedger.prepare(
                committedPolicy,
                expectedSessionGeneration: snapshot.generation
            )
        let policyChangeSet = try XCTUnwrap(
            tab.preparedConfigurationPolicyChangeSet(for: [replacement])
        )

        var departureBatches: [[ObjectIdentifier]] = []
        var events: [String] = []
        var destroyed: [ObjectIdentifier] = []
        let pipeline = replacementPipeline(
            repository: repository,
            tab: tab,
            departureBatches: { webViews in
                XCTAssertEqual(
                    tab.configurationPolicyLedger.committedState,
                    committedPolicy,
                    "Policy must commit before physical retirement begins"
                )
                events.append("departure")
                departureBatches.append(
                    webViews.map(ObjectIdentifier.init)
                )
            },
            destroy: { webView in
                events.append("destroy")
                destroyed.append(ObjectIdentifier(webView))
            }
        )
        let prepared = try XCTUnwrap(PreparedWebViewReplacement(
            tab: tab,
            snapshot: snapshot,
            placement: .windowSet(
                webViewsByWindowID: [primaryWindowID: replacement],
                primaryWindowID: primaryWindowID
            ),
            replacements: [replacement],
            trackedReplacements: [replacement],
            bindingReplacements: [],
            targetURL: targetURL,
            semanticRevision: intent.revision,
            profileID: nil,
            requiresExtensionRuntimePreparation: false,
            configurationPolicyChangeSet: policyChangeSet
        ))

        guard case .committed = pipeline.begin(
            [prepared],
            profileIDs: [],
            model: .noExternalModel,
            completion: { _ in }
        ) else {
            return XCTFail("Expected synchronous replacement commit")
        }

        XCTAssertEqual(departureBatches.count, 1)
        XCTAssertEqual(
            Set(departureBatches[0]),
            [ObjectIdentifier(oldPrimary), ObjectIdentifier(oldClone)]
        )
        XCTAssertEqual(events.first, "departure")
        XCTAssertEqual(Set(destroyed), Set(departureBatches[0]))
        XCTAssertEqual(
            transaction.role(
                from: oldPrimary,
                navigationID: ObjectIdentifier(primaryNavigation),
                isCurrent: true
            ),
            .stale
        )
        XCTAssertEqual(
            transaction.role(
                from: oldClone,
                navigationID: ObjectIdentifier(cloneNavigation),
                isCurrent: true
            ),
            .stale
        )
        XCTAssertEqual(
            transaction.role(
                from: replacement,
                navigationID: ObjectIdentifier(replacementNavigation),
                isCurrent: true
            ),
            .authority
        )
        XCTAssertNil(tab.committedDocumentRuntime.lease(for: oldPrimary))
        XCTAssertNil(tab.committedDocumentRuntime.lease(for: oldClone))
        XCTAssertEqual(
            tab.committedDocumentRuntime.lease(for: replacement)?.isAuthority,
            true
        )
    }

    func testReplacementRejectsPolicyEvidenceFromDifferentWebView()
        throws {
        let repository = WebViewSessionRepository()
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/evidence-identity")
        )
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let evidenceConfiguration = WKWebViewConfiguration()
        evidenceConfiguration.sumiIsNormalTabWebViewConfiguration = true
        let evidenceWebView = WKWebView(
            frame: .zero,
            configuration: evidenceConfiguration
        )
        let placedConfiguration = WKWebViewConfiguration()
        placedConfiguration.sumiIsNormalTabWebViewConfiguration = true
        let placedWebView = WKWebView(
            frame: .zero,
            configuration: placedConfiguration
        )
        let snapshot = repository.snapshot(for: tab.id)
        let receipt = tab.configurationPolicyLedger.prepare(
            TabConfigurationPolicyState(
                profileID: nil,
                websiteDataStoreIdentity: ObjectIdentifier(
                    evidenceWebView.configuration.websiteDataStore
                ),
                protectionAttachment: nil,
                safariContentBlockerAttachment: nil,
                autoplayState: .allowAll
            ),
            expectedSessionGeneration: snapshot.generation
        )
        evidenceWebView.sumiPreparedConfigurationPolicyChange = receipt
        let changeSet = try XCTUnwrap(
            tab.preparedConfigurationPolicyChangeSet(
                for: [evidenceWebView]
            )
        )
        let windowID = UUID()

        XCTAssertNil(
            PreparedWebViewReplacement(
                tab: tab,
                snapshot: snapshot,
                placement: .windowSet(
                    webViewsByWindowID: [windowID: placedWebView],
                    primaryWindowID: windowID
                ),
                replacements: [placedWebView],
                trackedReplacements: [placedWebView],
                bindingReplacements: [],
                targetURL: targetURL,
                semanticRevision: 0,
                profileID: nil,
                requiresExtensionRuntimePreparation: false,
                configurationPolicyChangeSet: changeSet
            )
        )
        XCTAssertEqual(receipt.phase, .prepared)
        XCTAssertIdentical(
            evidenceWebView.sumiPreparedConfigurationPolicyChange,
            receipt
        )
        XCTAssertEqual(tab.configurationPolicyLedger.revision, 0)
        changeSet.cancel()
    }

    func testCancelledPolicyEvidenceIsRejectedBeforeReplacementAdmission()
        throws {
        let repository = WebViewSessionRepository()
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/cancelled-evidence")
        )
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let windowID = UUID()
        let previous = WKWebView()
        register(
            previous,
            tabID: tab.id,
            windowID: windowID,
            in: repository
        )
        let snapshot = repository.snapshot(for: tab.id)
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        configuration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let replacement = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        replacement.sumiPreparedConfigurationPolicyChange =
            tab.configurationPolicyLedger.prepare(
                TabConfigurationPolicyState(
                    profileID: nil,
                    websiteDataStoreIdentity: ObjectIdentifier(
                        replacement.configuration.websiteDataStore
                    ),
                    protectionAttachment: nil,
                    safariContentBlockerAttachment: nil,
                    autoplayState: .allowAll
                ),
                expectedSessionGeneration: snapshot.generation
            )
        let changeSet = try XCTUnwrap(
            tab.preparedConfigurationPolicyChangeSet(
                for: [replacement]
            )
        )
        let prepared = try XCTUnwrap(
            PreparedWebViewReplacement(
                tab: tab,
                snapshot: snapshot,
                placement: .windowSet(
                    webViewsByWindowID: [windowID: replacement],
                    primaryWindowID: windowID
                ),
                replacements: [replacement],
                trackedReplacements: [replacement],
                bindingReplacements: [],
                targetURL: targetURL,
                semanticRevision: 0,
                profileID: nil,
                requiresExtensionRuntimePreparation: false,
                configurationPolicyChangeSet: changeSet
            )
        )
        changeSet.cancel()
        let pipeline = replacementPipeline(
            repository: repository,
            tab: tab,
            departureBatches: { _ in
                XCTFail("Invalid evidence cannot retire a generation")
            },
            destroy: { _ in
                XCTFail("Invalid evidence cannot destroy a WebView")
            }
        )

        guard case .invalid = pipeline.begin(
            [prepared],
            profileIDs: [],
            model: .noExternalModel,
            completion: { _ in
                XCTFail("Invalid evidence cannot start settlement")
            }
        ) else {
            return XCTFail("Expected pre-admission policy rejection")
        }

        let current = repository.snapshot(for: tab.id)
        XCTAssertEqual(current.generation, snapshot.generation)
        XCTAssertIdentical(current.windowWebViews[windowID], previous)
        XCTAssertNil(repository.residence(of: replacement))
        XCTAssertEqual(tab.configurationPolicyLedger.revision, 0)
        XCTAssertEqual(
            tab.configurationPolicyLedger.committedState,
            .unknown
        )
    }

    func testPolicyReceiptSubstitutionDuringModelValidationCannotMutatePlacement()
        throws {
        let fixture = try makePreparedPolicyReplacementFixture(
            path: "validation-receipt-substitution"
        )
        let newerReceipt = fixture.tab.configurationPolicyLedger.prepare(
            fixture.policyState,
            expectedSessionGeneration: fixture.snapshot.generation
        )
        defer {
            newerReceipt.cancel()
            if fixture.replacement.sumiPreparedConfigurationPolicyChange
                === newerReceipt {
                fixture.replacement.sumiPreparedConfigurationPolicyChange = nil
            }
        }
        var modelCommitWasCalled = false
        let pipeline = replacementPipeline(
            repository: fixture.repository,
            tab: fixture.tab,
            departureBatches: { _ in
                XCTFail("Invalid evidence cannot retire a generation")
            },
            destroy: { _ in
                XCTFail("Invalid evidence cannot destroy a WebView")
            }
        )

        guard case .invalid = pipeline.begin(
            [fixture.prepared],
            profileIDs: [],
            model: .transaction(TestWebViewReplacementModelTransaction(
                validate: {
                    fixture.replacement.sumiPreparedConfigurationPolicyChange =
                        newerReceipt
                    return true
                },
                stage: {
                    modelCommitWasCalled = true
                }
            )),
            completion: { _ in
                XCTFail("Invalid evidence cannot start settlement")
            }
        ) else {
            return XCTFail("Expected in-admission policy rejection")
        }

        XCTAssertFalse(modelCommitWasCalled)
        XCTAssertEqual(fixture.originalReceipt.phase, .cancelled)
        XCTAssertEqual(newerReceipt.phase, .prepared)
        XCTAssertIdentical(
            fixture.replacement.sumiPreparedConfigurationPolicyChange,
            newerReceipt
        )
        assertPlacementWasNotReplaced(fixture)
    }

    func testPolicyCancellationDuringModelCommitRollsBackRepositoryAdmission()
        throws {
        let fixture = try makePreparedPolicyReplacementFixture(
            path: "commit-receipt-cancellation"
        )
        var modelValue = "before"
        var modelRollbackCount = 0
        var rollbackPublicationCount = 0
        var departed: [ObjectIdentifier] = []
        var destroyed: [ObjectIdentifier] = []
        let pipeline = replacementPipeline(
            repository: fixture.repository,
            tab: fixture.tab,
            departureBatches: { webViews in
                departed.append(contentsOf: webViews.map(ObjectIdentifier.init))
            },
            destroy: { webView in
                destroyed.append(ObjectIdentifier(webView))
            }
        )

        guard case .modelCommitFailed = pipeline.begin(
            [fixture.prepared],
            profileIDs: [],
            model: .transaction(TestWebViewReplacementModelTransaction(
                stage: {
                    modelValue = "committed"
                    fixture.changeSet.cancel()
                },
                rollback: {
                    XCTAssertEqual(modelValue, "committed")
                    XCTAssertIdentical(
                        fixture.repository.webView(
                            for: fixture.tab.id,
                            in: fixture.windowID
                        ),
                        fixture.replacement
                    )
                    guard case .retiring = fixture.repository.residence(
                        of: fixture.previous
                    ) else {
                        return XCTFail(
                            "Model rollback must run inside repository lease"
                        )
                    }
                    modelValue = "before"
                    modelRollbackCount += 1
                },
                publishRollback: {
                    rollbackPublicationCount += 1
                    XCTAssertEqual(
                        destroyed,
                        [ObjectIdentifier(fixture.replacement)]
                    )
                    XCTAssertIdentical(
                        fixture.repository.webView(
                            for: fixture.tab.id,
                            in: fixture.windowID
                        ),
                        fixture.previous
                    )
                    XCTAssertNil(
                        fixture.repository.residence(of: fixture.replacement)
                    )
                }
            )),
            completion: { _ in
                XCTFail("Invalid evidence cannot start settlement")
            }
        ) else {
            return XCTFail("Expected compensated model-commit rejection")
        }

        XCTAssertEqual(modelRollbackCount, 1)
        XCTAssertEqual(rollbackPublicationCount, 1)
        XCTAssertEqual(departed, [ObjectIdentifier(fixture.replacement)])
        XCTAssertEqual(destroyed, [ObjectIdentifier(fixture.replacement)])
        XCTAssertEqual(modelValue, "before")
        XCTAssertEqual(fixture.originalReceipt.phase, .cancelled)
        XCTAssertNil(
            fixture.replacement.sumiPreparedConfigurationPolicyChange
        )
        assertPlacementWasNotReplaced(
            fixture,
            expectsUnchangedGeneration: false
        )
    }

    func testPolicyCancellationRollbackFailureRetainsTerminalOwner()
        throws {
        enum ExpectedFailure: Error { case failed }

        let fixture = try makePreparedPolicyReplacementFixture(
            path: "commit-receipt-rollback-failure"
        )
        var modelValue = "before"
        var modelRollbackCount = 0
        var terminalDrainCount = 0
        let pipeline = replacementPipeline(
            repository: fixture.repository,
            tab: fixture.tab,
            departureBatches: { _ in
                XCTFail("Quarantined generation cannot leave navigation yet")
            },
            destroy: { _ in
                XCTFail("Terminal runtime owns physical shutdown")
            }
        )

        guard case .settlementConflict = pipeline.begin(
            [fixture.prepared],
            profileIDs: [],
            model: .transaction(TestWebViewReplacementModelTransaction(
                stage: {
                    modelValue = "staged"
                    fixture.changeSet.cancel()
                },
                stagedModelIsExact: { modelValue == "staged" },
                rollback: {
                    modelRollbackCount += 1
                    XCTAssertIdentical(
                        fixture.repository.webView(
                            for: fixture.tab.id,
                            in: fixture.windowID
                        ),
                        fixture.replacement
                    )
                    guard case .retiring = fixture.repository.residence(
                        of: fixture.previous
                    ) else {
                        return XCTFail(
                            "Failed rollback must still own the predecessor"
                        )
                    }
                    throw ExpectedFailure.failed
                },
                settleTerminalDrain: {
                    modelValue = "terminal"
                    terminalDrainCount += 1
                }
            )),
            completion: { _ in
                XCTFail("Failed admission has no public settlement receipt")
            }
        ) else {
            return XCTFail("Expected retained admission quarantine")
        }

        XCTAssertEqual(modelRollbackCount, 1)
        XCTAssertEqual(modelValue, "staged")
        XCTAssertIdentical(
            fixture.repository.webView(
                for: fixture.tab.id,
                in: fixture.windowID
            ),
            fixture.replacement
        )
        guard case .retiring = fixture.repository.residence(
            of: fixture.previous
        ) else {
            return XCTFail("Predecessor must remain repository-owned")
        }
        XCTAssertEqual(fixture.originalReceipt.phase, .cancelled)

        let drained = fixture.repository.takeAllWebViewsForTerminalShutdown()
        XCTAssertEqual(
            Set(drained.map { ObjectIdentifier($0.webView) }),
            Set(
                [fixture.previous, fixture.replacement]
                    .map(ObjectIdentifier.init)
            )
        )
        pipeline.resetForTerminalShutdown()
        XCTAssertEqual(terminalDrainCount, 1)
        XCTAssertEqual(modelValue, "terminal")
        pipeline.resetForTerminalShutdown()
        XCTAssertEqual(terminalDrainCount, 1)
    }

    func testPolicyCancellationWhileAwaitingBindingRollsBackBeforeCommit()
        throws {
        let fixture = try makePreparedPolicyReplacementFixture(
            path: "binding-receipt-cancellation",
            requiresBinding: true
        )
        var modelValue = "before"
        var modelRollbackCount = 0
        var rollbackPublicationCount = 0
        let rollbackPublication = PassthroughSubject<Void, Never>()
        var reentrantObserverCount = 0
        var publicationObservedRestoredRepository = false
        var settlementOutcome: WebViewReplacementTransactionOutcome?
        var destroyed: [ObjectIdentifier] = []
        let rollbackObserver = rollbackPublication.sink {
            reentrantObserverCount += 1
            XCTAssertEqual(modelValue, "before")
            let restored = fixture.repository.snapshot(for: fixture.tab.id)
            XCTAssertIdentical(
                restored.windowWebViews[fixture.windowID],
                fixture.previous
            )
            XCTAssertNil(
                fixture.repository.residence(of: fixture.replacement)
            )
            publicationObservedRestoredRepository = true
        }
        let pipeline = replacementPipeline(
            repository: fixture.repository,
            tab: fixture.tab,
            departureBatches: { webViews in
                XCTAssertEqual(
                    webViews.map(ObjectIdentifier.init),
                    [ObjectIdentifier(fixture.replacement)]
                )
            },
            destroy: { destroyed.append(ObjectIdentifier($0)) }
        )

        guard case .started(let settlement) = pipeline.begin(
            [fixture.prepared],
            profileIDs: [],
            model: .transaction(TestWebViewReplacementModelTransaction(
                stage: { modelValue = "committed" },
                rollback: {
                    XCTAssertEqual(modelValue, "committed")
                    modelValue = "before"
                    modelRollbackCount += 1
                },
                publishRollback: {
                    rollbackPublicationCount += 1
                    rollbackPublication.send()
                }
            )),
            completion: { settlementOutcome = $0 }
        ), let token = settlement.bindingToken(for: fixture.replacement) else {
            return XCTFail("Expected asynchronous replacement settlement")
        }
        fixture.changeSet.cancel()
        let navigationLifetime = NSObject()

        XCTAssertEqual(
            pipeline.markBound(
                token,
                binding: WebViewReplacementNavigationBinding(
                    webView: fixture.replacement,
                    semanticRevision: token.semanticRevision,
                    navigationID: ObjectIdentifier(navigationLifetime),
                    navigationLifetime: navigationLifetime
                )
            ),
            .rolledBack(.commitValidationFailed)
        )

        XCTAssertEqual(
            settlementOutcome,
            .rolledBack(.commitValidationFailed)
        )
        XCTAssertEqual(modelRollbackCount, 1)
        XCTAssertEqual(rollbackPublicationCount, 1)
        XCTAssertEqual(reentrantObserverCount, 1)
        XCTAssertTrue(publicationObservedRestoredRepository)
        XCTAssertEqual(modelValue, "before")
        XCTAssertEqual(fixture.originalReceipt.phase, .cancelled)
        XCTAssertEqual(
            destroyed,
            [ObjectIdentifier(fixture.replacement)]
        )
        assertPlacementWasNotReplaced(
            fixture,
            expectsUnchangedGeneration: false
        )
        withExtendedLifetime(rollbackObserver) {}
    }

    func testRolledBackReplacementDiscardsOnlyReplacementGeneration()
        throws {
        let repository = WebViewSessionRepository()
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/replacement-rollback")
        )
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let primaryWindowID = UUID()
        let cloneWindowID = UUID()
        let oldPrimary = WKWebView()
        let oldClone = WKWebView()
        let replacementConfiguration = WKWebViewConfiguration()
        replacementConfiguration.sumiIsNormalTabWebViewConfiguration = true
        replacementConfiguration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let discardedReplacement = WKWebView(
            frame: .zero,
            configuration: replacementConfiguration
        )
        register(
            oldPrimary,
            tabID: tab.id,
            windowID: primaryWindowID,
            in: repository
        )
        register(
            oldClone,
            tabID: tab.id,
            windowID: cloneWindowID,
            in: repository
        )

        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let primaryNavigation = try bindMainFrameParticipant(
            oldPrimary,
            to: tab
        )
        let cloneNavigation = try bindMainFrameParticipant(oldClone, to: tab)
        let replacementNavigation = try bindMainFrameParticipant(
            discardedReplacement,
            to: tab
        )
        XCTAssertEqual(
            transaction.prepareAuthorityForCommit(
                from: discardedReplacement,
                navigationID: ObjectIdentifier(replacementNavigation),
                navigationLifetime: replacementNavigation
            ),
            .authority
        )

        let snapshot = repository.snapshot(for: tab.id)
        let pendingPolicy = TabConfigurationPolicyState(
            profileID: nil,
            websiteDataStoreIdentity: ObjectIdentifier(
                discardedReplacement.configuration.websiteDataStore
            ),
            protectionAttachment: nil,
            safariContentBlockerAttachment: nil,
            autoplayState: .blockAudible
        )
        let pendingReceipt = tab.configurationPolicyLedger.prepare(
            pendingPolicy,
            expectedSessionGeneration: snapshot.generation
        )
        discardedReplacement.sumiPreparedConfigurationPolicyChange =
            pendingReceipt
        let policyChangeSet = try XCTUnwrap(
            tab.preparedConfigurationPolicyChangeSet(
                for: [discardedReplacement]
            )
        )

        var departureBatches: [[ObjectIdentifier]] = []
        var events: [String] = []
        var destroyed: [ObjectIdentifier] = []
        let pipeline = replacementPipeline(
            repository: repository,
            tab: tab,
            departureBatches: { webViews in
                events.append("departure")
                departureBatches.append(
                    webViews.map(ObjectIdentifier.init)
                )
            },
            destroy: { webView in
                events.append("destroy")
                destroyed.append(ObjectIdentifier(webView))
            }
        )
        let prepared = try XCTUnwrap(PreparedWebViewReplacement(
            tab: tab,
            snapshot: snapshot,
            placement: .windowSet(
                webViewsByWindowID: [
                    primaryWindowID: discardedReplacement,
                ],
                primaryWindowID: primaryWindowID
            ),
            replacements: [discardedReplacement],
            trackedReplacements: [discardedReplacement],
            bindingReplacements: [discardedReplacement],
            targetURL: targetURL,
            semanticRevision: intent.revision,
            profileID: nil,
            requiresExtensionRuntimePreparation: false,
            configurationPolicyChangeSet: policyChangeSet
        ))
        var settlementOutcome: WebViewReplacementTransactionOutcome?
        guard case .started(let receipt) = pipeline.begin(
            [prepared],
            profileIDs: [],
            model: .noExternalModel,
            completion: { settlementOutcome = $0 }
        ), let token = receipt.bindingToken(for: discardedReplacement) else {
            return XCTFail("Expected replacement settlement receipt")
        }

        pipeline.fail(token, reason: .submissionFailed)

        XCTAssertEqual(
            settlementOutcome,
            .rolledBack(.bindingFailure(.submissionFailed))
        )
        XCTAssertEqual(pendingReceipt.phase, .cancelled)
        XCTAssertNil(
            discardedReplacement.sumiPreparedConfigurationPolicyChange
        )
        XCTAssertEqual(
            tab.configurationPolicyLedger.committedState,
            .unknown
        )
        XCTAssertEqual(tab.configurationPolicyLedger.revision, 0)
        XCTAssertEqual(departureBatches.count, 1)
        XCTAssertEqual(
            departureBatches[0],
            [ObjectIdentifier(discardedReplacement)]
        )
        XCTAssertEqual(events, ["departure", "destroy"])
        XCTAssertEqual(destroyed, [ObjectIdentifier(discardedReplacement)])
        XCTAssertIdentical(
            repository.webView(for: tab.id, in: primaryWindowID),
            oldPrimary
        )
        XCTAssertIdentical(
            repository.webView(for: tab.id, in: cloneWindowID),
            oldClone
        )
        XCTAssertEqual(
            transaction.role(
                from: discardedReplacement,
                navigationID: ObjectIdentifier(replacementNavigation),
                isCurrent: true
            ),
            .stale
        )
        XCTAssertEqual(
            transaction.role(
                from: oldPrimary,
                navigationID: ObjectIdentifier(primaryNavigation),
                isCurrent: true
            ),
            .authority
        )
        XCTAssertEqual(
            transaction.role(
                from: oldClone,
                navigationID: ObjectIdentifier(cloneNavigation),
                isCurrent: true
            ),
            .participant
        )
    }

    private func makeMaterializationService(
        repository: WebViewSessionRepository,
        primaryCandidate: @escaping @MainActor @Sendable (UUID) -> (
            owner: TrackedWebViewOwner,
            webView: WKWebView
        )? = { _ in nil }
    ) -> TabWebViewMaterializationService {
        let placement = makeTestWebViewRuntimeGraph(
            webViewSessions: repository
        ).canonicalWebViewPlacement
        return TabWebViewMaterializationService(
            runtime: .init(
                webViewSessions: repository,
                initialDocumentWarmup: {
                    InitialDocumentWarmupRuntime(
                        needsInitialDocumentExtensionContextLoad: { _ in false },
                        ensureInitialExtensionContextsLoaded: { _ in },
                        refreshCompositorForWindow: { _ in }
                    )
                },
                placement: placement,
                primaryCandidate: primaryCandidate,
                notifyActivatedIfCurrent: { _, _ in }
            ),
            planner: WebViewCreationPlanner()
        )
    }

    private func bindMainFrameParticipant(
        _ webView: WKWebView,
        to tab: Tab
    ) throws -> NSObject {
        let lease = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let navigation = NSObject()
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            matching: lease
        ))
        return navigation
    }

    private func commitConfigurationPolicy(
        on tab: Tab,
        webView: WKWebView,
        profileID: UUID,
        safariAttachment: SumiSafariContentBlockerAttachmentState
    ) {
        webView.sumiPreparedConfigurationPolicyChange =
            tab.configurationPolicyLedger.prepare(
                TabConfigurationPolicyState(
                    profileID: profileID,
                    websiteDataStoreIdentity: ObjectIdentifier(
                        webView.configuration.websiteDataStore
                    ),
                    protectionAttachment: nil,
                    safariContentBlockerAttachment: safariAttachment,
                    autoplayState: nil
                ),
                expectedSessionGeneration: tab.webViewSession.generation
            )
        guard let changeSet = tab.preparedConfigurationPolicyChangeSet(
            for: [webView]
        ) else {
            XCTFail("Expected exact configuration policy evidence")
            return
        }
        XCTAssertTrue(changeSet.commit(as: .canonicalGeneration))
    }

    private func replacementPipeline(
        repository: WebViewSessionRepository,
        tab: Tab,
        departureBatches: @escaping ([WKWebView]) -> Void,
        destroy: @escaping (WKWebView) -> Void
    ) -> WebViewReplacementPipeline {
        let retiredGenerationDestroyer = WebViewRetiredGenerationDestroyer(
            runtime: .init(
                webViewSessions: repository,
                retireNavigationGeneration: {
                    tabID,
                    webViews,
                    preferredWebView in
                    XCTAssertEqual(tabID, tab.id)
                    departureBatches(webViews)
                    tab.webViewsDidLeaveNavigationRuntime(
                        webViews,
                        preferredAuthorityWebView: preferredWebView
                    )
                },
                destroy: { tabID, webView in
                    XCTAssertEqual(tabID, tab.id)
                    destroy(webView)
                },
                uninstallObservationsIfUntracked: { _ in }
            )
        )
        return WebViewReplacementPipeline(runtime: .init(
            webViewSessions: repository,
            quiesce: { _ in },
            retiredGenerationDestroyer: retiredGenerationDestroyer,
            restore: { _, _ in }
        ))
    }

    private struct PreparedPolicyReplacementFixture {
        let repository: WebViewSessionRepository
        let tab: Tab
        let windowID: UUID
        let previous: WKWebView
        let replacement: WKWebView
        let snapshot: WebViewSessionSnapshot
        let policyState: TabConfigurationPolicyState
        let originalReceipt: PreparedConfigurationPolicyChange
        let changeSet: PreparedConfigurationPolicyChangeSet
        let prepared: PreparedWebViewReplacement
    }

    private func makePreparedPolicyReplacementFixture(
        path: String,
        requiresBinding: Bool = false
    ) throws -> PreparedPolicyReplacementFixture {
        let repository = WebViewSessionRepository()
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/\(path)")
        )
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let windowID = UUID()
        let previous = WKWebView()
        register(
            previous,
            tabID: tab.id,
            windowID: windowID,
            in: repository
        )
        let snapshot = repository.snapshot(for: tab.id)
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        configuration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let replacement = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        let policyState = TabConfigurationPolicyState(
            profileID: nil,
            websiteDataStoreIdentity: ObjectIdentifier(
                replacement.configuration.websiteDataStore
            ),
            protectionAttachment: nil,
            safariContentBlockerAttachment: nil,
            autoplayState: .allowAll
        )
        let receipt = tab.configurationPolicyLedger.prepare(
            policyState,
            expectedSessionGeneration: snapshot.generation
        )
        replacement.sumiPreparedConfigurationPolicyChange = receipt
        let changeSet = try XCTUnwrap(
            tab.preparedConfigurationPolicyChangeSet(for: [replacement])
        )
        let prepared = try XCTUnwrap(
            PreparedWebViewReplacement(
                tab: tab,
                snapshot: snapshot,
                placement: .windowSet(
                    webViewsByWindowID: [windowID: replacement],
                    primaryWindowID: windowID
                ),
                replacements: [replacement],
                trackedReplacements: [replacement],
                bindingReplacements: requiresBinding ? [replacement] : [],
                targetURL: targetURL,
                semanticRevision: 0,
                profileID: nil,
                requiresExtensionRuntimePreparation: false,
                configurationPolicyChangeSet: changeSet
            )
        )
        return PreparedPolicyReplacementFixture(
            repository: repository,
            tab: tab,
            windowID: windowID,
            previous: previous,
            replacement: replacement,
            snapshot: snapshot,
            policyState: policyState,
            originalReceipt: receipt,
            changeSet: changeSet,
            prepared: prepared
        )
    }

    private func assertPlacementWasNotReplaced(
        _ fixture: PreparedPolicyReplacementFixture,
        expectsUnchangedGeneration: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let current = fixture.repository.snapshot(for: fixture.tab.id)
        if expectsUnchangedGeneration {
            XCTAssertEqual(
                current.generation,
                fixture.snapshot.generation,
                file: file,
                line: line
            )
        } else {
            XCTAssertGreaterThan(
                current.generation,
                fixture.snapshot.generation,
                file: file,
                line: line
            )
        }
        XCTAssertIdentical(
            current.windowWebViews[fixture.windowID],
            fixture.previous,
            file: file,
            line: line
        )
        XCTAssertNil(
            fixture.repository.residence(of: fixture.replacement),
            file: file,
            line: line
        )
        XCTAssertEqual(
            fixture.tab.configurationPolicyLedger.revision,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            fixture.tab.configurationPolicyLedger.committedState,
            .unknown,
            file: file,
            line: line
        )
    }

    private func makeIsolatedOwnershipBrowserManager() -> BrowserManager {
        let defaults = UserDefaults(
            suiteName: "TabWebViewMaterializationAndRebuildTests.\(UUID().uuidString)"
        )!
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.disable(.extensions)
        let browserManager = BrowserManager(moduleRegistry: registry)
        return browserManager
    }

    private func attachProfileRuntime(
        to tab: Tab,
        profiles: [UUID: Profile],
        safariState: @escaping () -> SumiSafariContentBlockerAttachmentState
    ) {
        var runtime = TabBrowserRuntime.inactive
        runtime.profileResolutionRuntime = TabProfileResolutionRuntime(
            ephemeralProfileForTab: { _, _ in nil },
            profile: { profiles[$0] },
            spaceProfile: { _ in nil },
            currentProfile: { profiles.values.first },
            firstProfile: { profiles.values.first }
        )
        runtime.webViewConfigurationContext = {
            TabWebViewConfigurationContext(
                browserConfiguration: BrowserConfiguration(),
                extensionNormalTabUserScripts: { [] },
                boostsNormalTabUserScripts: { _, _, _ in [] },
                protectionDecision: { _, _ in nil },
                protectionDesiredAttachmentState: {
                    .disabled(siteHost: $0?.host)
                },
                safariContentBlockerAttachmentState: { _ in safariState() },
                safariBlockerDesiredAttachmentState: { _ in safariState() },
                enabledSafariContentBlockingServices: { _, _ in [] },
                prepareWebViewConfigForExtensionRuntime: { _, _, _ in }
            )
        }
        tab.attachBrowserRuntime(runtime)
    }

    private func register(
        _ webView: WKWebView,
        tabID: UUID,
        windowID: UUID,
        in repository: WebViewSessionRepository
    ) {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: .init(tabID: tabID, windowID: windowID),
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

    private func makeWindowBoundRuntimeGraph(
        repository: WebViewSessionRepository,
        tab: Tab,
        window: RebuildRuntimeWindowStub
    ) -> WebViewRuntimeGraph {
        let tabID = tab.id
        let windowID = window.id
        return makeTestWebViewRuntimeGraph(
            webViewSessions: repository,
            resolveRuntimeTab: { id in id == tabID ? tab : nil },
            windowServices: WebViewWindowServices(
                liveWindowIDs: { [windowID] },
                containsWindow: { $0 == windowID },
                currentTabID: { $0 == windowID ? tabID : nil },
                selectTab: { _, _ in },
                refreshCompositor: { _ in },
                notifyTabActivatedIfCurrent: { _, _ in }
            ),
            visibleContext: WebViewVisibleRuntimeContext(
                windowState: { id in id == windowID ? window : nil },
                currentTabId: { _ in tabID },
                splitVisibleTabIds: { _ in [] },
                resolveTab: { id, _ in id == tabID ? tab : nil },
                canMaterializeWebViewDuringStartup: { _, _ in true },
                markTabAccessed: { _ in },
                globallyVisibleTabIDs: { [tabID] in [tabID] },
                scheduleTabSuspensionReconcile: { _ in },
                scheduleBackgroundMediaReconcile: { _ in },
                refreshCompositor: { _ in }
            ),
            initialDocumentContext: InitialDocumentWebViewRuntimeContext(
                needsInitialDocumentExtensionContextLoad: { _ in false },
                ensureInitialExtensionContextsLoaded: { _ in },
                refreshCompositorForWindow: { _ in }
            )
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class RebuildRuntimeWindowStub: WebRuntimeWindowHandle {
    let id = UUID()
    var ephemeralTabHandles: [any WebRuntimeTabHandle] = []
}

@MainActor
private final class AssignmentInitialDocumentRecordingWebView: WKWebView {
    private(set) var loadedRequests: [URLRequest] = []

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return nil
    }
}

@MainActor
private final class AssignmentDelayedUserContentController:
    WKUserContentController,
    SumiNormalTabUserContentControlling {
    var normalTabUserScriptsProvider: SumiNormalTabUserScripts?
    var contentBlockingAssetSummary = SumiNormalTabContentBlockingAssetSummary(
        isInstalled: false,
        globalRuleListCount: 0,
        updateRuleCount: 0,
        isContentBlockingFeatureEnabled: false
    )
    var hasInstalledInitialUserContent = false
    private(set) var waitCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    var wkUserContentController: WKUserContentController {
        self
    }

    #if DEBUG
        var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> {
            Just(contentBlockingAssetSummary).eraseToAnyPublisher()
        }
    #endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async {
        normalTabUserScriptsProvider = provider
    }

    func waitForContentBlockingAssetsInstalled() async {
        waitCallCount += 1
        guard hasInstalledInitialUserContent == false else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishInitialUserContentInstallation() {
        hasInstalledInitialUserContent = true
        continuation?.resume()
        continuation = nil
    }

    func cleanUpBeforeClosing() {}
}
