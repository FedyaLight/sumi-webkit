import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewRuntimeTabRegistryTests: XCTestCase {
    func testBindPublishesExactRuntimeTabIdentity() {
        let repository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let tab = makeTab(webViewSessions: repository)

        XCTAssertEqual(registry.bind(tab), .bound)
        XCTAssertIdentical(registry.boundTab(tab.id), tab)
    }

    func testBindingExactRuntimeTabTwiceIsAlreadyBound() {
        let repository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let tab = makeTab(webViewSessions: repository)

        XCTAssertEqual(registry.bind(tab), .bound)
        XCTAssertEqual(registry.bind(tab), .alreadyBound)
        XCTAssertIdentical(registry.boundTab(tab.id), tab)
    }

    func testBindingLiveSameIDTabRejectsConflictAndPreservesOriginalIdentity() {
        let repository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let tabID = UUID()
        let original = makeTab(id: tabID, webViewSessions: repository)
        let conflicting = makeTab(id: tabID, webViewSessions: repository)

        XCTAssertEqual(registry.bind(original), .bound)
        XCTAssertEqual(registry.bind(conflicting), .identityConflict)
        XCTAssertIdentical(registry.boundTab(tabID), original)
    }

    func testAtomicBindingConflictDoesNotBindAcceptedPrefix() {
        let repository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let conflictID = UUID()
        let canonical = makeTab(id: conflictID, webViewSessions: repository)
        let acceptedPrefix = makeTab(webViewSessions: repository)
        let conflicting = makeTab(
            id: conflictID,
            webViewSessions: repository
        )
        XCTAssertEqual(registry.bind(canonical), .bound)

        XCTAssertFalse(registry.bindAtomically([acceptedPrefix, conflicting]))

        XCTAssertNil(registry.boundTab(acceptedPrefix.id))
        XCTAssertIdentical(registry.boundTab(conflictID), canonical)
    }

    func testAtomicBindingRejectsDuplicateInputWithoutMutation() {
        let repository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let tab = makeTab(webViewSessions: repository)

        XCTAssertFalse(registry.bindAtomically([tab, tab]))
        XCTAssertNil(registry.boundTab(tab.id))
    }

    func testAtomicBindingRejectsWrongRepositoryWithoutBindingPrefix() {
        let repository = WebViewSessionRepository()
        let otherRepository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let acceptedPrefix = makeTab(webViewSessions: repository)
        let wrongRepositoryTab = makeTab(webViewSessions: otherRepository)

        XCTAssertFalse(registry.bindAtomically([
            acceptedPrefix,
            wrongRepositoryTab,
        ]))

        XCTAssertNil(registry.boundTab(acceptedPrefix.id))
        XCTAssertNil(registry.boundTab(wrongRepositoryTab.id))
    }

    func testResolveFailsClosedWhenAuthoritativeResolverReturnsDifferentSameIDTab() {
        let repository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let tabID = UUID()
        let bound = makeTab(id: tabID, webViewSessions: repository)
        let conflicting = makeTab(id: tabID, webViewSessions: repository)
        XCTAssertEqual(registry.bind(bound), .bound)

        let resolved = registry.resolve(tabID) { resolvedID in
            XCTAssertEqual(resolvedID, tabID)
            return conflicting
        }

        XCTAssertNil(resolved)
        XCTAssertIdentical(registry.boundTab(tabID), bound)
    }

    func testLifecyclePackageCallbackRejectsStaleSameIDTabIdentity() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let stale = makeTab(id: tabID, webViewSessions: repository)
        let replacement = makeTab(id: tabID, webViewSessions: repository)
        let graph = makeTestWebViewRuntimeGraph(
            webViewSessions: repository,
            resolveRuntimeTab: { id in id == tabID ? replacement : nil }
        )

        XCTAssertEqual(graph.runtimeTabs.bind(stale), .bound)
        XCTAssertNil(graph.lifecycleService.tabForPackageCallback(stale))
        XCTAssertIdentical(graph.runtimeTabs.boundTab(tabID), stale)
    }

    func testLifecyclePackageCallbackAcceptsExactRetiringTabIdentity() {
        let repository = WebViewSessionRepository()
        let tab = makeTab(webViewSessions: repository)
        let graph = makeTestWebViewRuntimeGraph(
            webViewSessions: repository,
            resolveRuntimeTab: { id in id == tab.id ? tab : nil }
        )

        XCTAssertTrue(graph.runtimeTabs.beginRetirement(tab))
        XCTAssertIdentical(graph.lifecycleService.tabForPackageCallback(tab), tab)
    }

    func testRetiredIdentityCannotRebindButDistinctSameIDTabCanBind() {
        let repository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let tabID = UUID()
        let original = makeTab(id: tabID, webViewSessions: repository)
        let replacement = makeTab(id: tabID, webViewSessions: repository)
        XCTAssertEqual(registry.bind(original), .bound)

        XCTAssertFalse(registry.beginRetirement(replacement))
        XCTAssertIdentical(registry.boundTab(tabID), original)
        XCTAssertTrue(registry.beginRetirement(original))
        XCTAssertEqual(registry.bind(original), .retiredIdentity)
        XCTAssertNil(registry.boundTab(tabID))
        XCTAssertTrue(registry.finishRetirementIfDrained(tabID))
        XCTAssertFalse(registry.beginRetirement(original))
        XCTAssertEqual(registry.bind(replacement), .bound)
        XCTAssertIdentical(registry.boundTab(tabID), replacement)
    }

    func testCommittedCompletionPreservesLaterSameIDRuntimeIdentity() {
        let repository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let tabID = UUID()
        let retired = makeTab(id: tabID, webViewSessions: repository)
        let replacement = makeTab(id: tabID, webViewSessions: repository)

        XCTAssertTrue(registry.beginRetirement(retired))
        XCTAssertEqual(
            registry.completeCommittedRetirement(retired),
            .finished
        )
        XCTAssertEqual(registry.bind(replacement), .bound)

        XCTAssertEqual(
            registry.completeCommittedRetirement(retired),
            .alreadyFinished
        )
        XCTAssertIdentical(registry.boundTab(tabID), replacement)
    }

    func testCommittedCompletionAcceptsTerminalRuntimeWithoutReopeningIt() {
        let repository = WebViewSessionRepository()
        let registry = WebViewRuntimeTabRegistry(webViewSessions: repository)
        let retired = makeTab(webViewSessions: repository)

        XCTAssertTrue(registry.beginRetirement(retired))
        registry.resetForTerminalShutdown()

        XCTAssertEqual(
            registry.completeCommittedRetirement(retired),
            .runtimeTerminated
        )
        XCTAssertEqual(registry.bind(retired), .runtimeTerminated)
        XCTAssertNil(registry.boundTab(retired.id))
    }

    func testTrackedAdmissionRejectsIdentityConflictBeforeRepositoryMutation() {
        let repository = WebViewSessionRepository()
        let graph = makeTestWebViewRuntimeGraph(webViewSessions: repository)
        let tabID = UUID()
        let bound = makeTab(id: tabID, webViewSessions: repository)
        let conflicting = makeTab(id: tabID, webViewSessions: repository)
        let candidate = FocusableWKWebView()
        candidate.owningTab = conflicting
        let windowID = UUID()
        XCTAssertEqual(graph.runtimeTabs.bind(bound), .bound)
        let generationBeforeAdmission = repository.residenceGeneration

        XCTAssertEqual(
            graph.trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                candidate,
                for: conflicting,
                in: windowID
            ),
            .rejected(.runtimeTabIdentityConflict)
        )

        XCTAssertEqual(repository.residenceGeneration, generationBeforeAdmission)
        XCTAssertTrue(repository.runtimeOwnedTabIDs.isEmpty)
        XCTAssertNil(repository.residence(of: candidate))
        XCTAssertNil(repository.webView(for: tabID, in: windowID))
        XCTAssertIdentical(graph.runtimeTabs.boundTab(tabID), bound)
    }

    func testConflictingTabCannotRetireCanonicalWebViews() {
        let repository = WebViewSessionRepository()
        let graph = makeTestWebViewRuntimeGraph(webViewSessions: repository)
        let tabID = UUID()
        let canonical = makeTab(id: tabID, webViewSessions: repository)
        let conflicting = makeTab(id: tabID, webViewSessions: repository)
        let webView = FocusableWKWebView()
        webView.owningTab = canonical
        let windowID = UUID()
        XCTAssertEqual(graph.runtimeTabs.bind(canonical), .bound)
        XCTAssertTrue(graph.trackedWebViewAdmission
            .registerAuxiliaryTrackedWebView(
                webView,
                for: canonical,
                in: windowID
            ).isAccepted)
        let generationBeforeTeardown = repository.residenceGeneration

        let result = graph.lifecycleService.removeAllWebViews(
            for: conflicting,
            intent: .retirement
        )

        XCTAssertEqual(result, .none)
        XCTAssertEqual(repository.residenceGeneration, generationBeforeTeardown)
        XCTAssertIdentical(repository.webView(for: tabID, in: windowID), webView)
        XCTAssertIdentical(graph.runtimeTabs.boundTab(tabID), canonical)
    }

    func testConflictingTabCannotSuspendCanonicalWebViews() {
        let repository = WebViewSessionRepository()
        let graph = makeTestWebViewRuntimeGraph(webViewSessions: repository)
        let tabID = UUID()
        let canonical = makeTab(id: tabID, webViewSessions: repository)
        let conflicting = makeTab(id: tabID, webViewSessions: repository)
        let webView = FocusableWKWebView()
        webView.owningTab = canonical
        let windowID = UUID()
        XCTAssertEqual(graph.runtimeTabs.bind(canonical), .bound)
        XCTAssertTrue(graph.trackedWebViewAdmission
            .registerAuxiliaryTrackedWebView(
                webView,
                for: canonical,
                in: windowID
            ).isAccepted)
        let generationBeforeSuspension = repository.residenceGeneration

        XCTAssertFalse(graph.lifecycleService.suspendWebViews(
            for: conflicting,
            reason: "same-id-conflict"
        ))

        XCTAssertEqual(repository.residenceGeneration, generationBeforeSuspension)
        XCTAssertIdentical(repository.webView(for: tabID, in: windowID), webView)
        XCTAssertIdentical(graph.runtimeTabs.boundTab(tabID), canonical)
    }

    func testSuspensionKeepsBindingAndRetirementUnbindsExactTab() {
        let repository = WebViewSessionRepository()
        let graph = makeTestWebViewRuntimeGraph(webViewSessions: repository)
        let tab = makeTab(webViewSessions: repository)
        XCTAssertEqual(graph.runtimeTabs.bind(tab), .bound)

        _ = graph.lifecycleService.removeAllWebViews(
            for: tab,
            intent: .suspension
        )
        XCTAssertIdentical(graph.runtimeTabs.boundTab(tab.id), tab)

        _ = graph.lifecycleService.removeAllWebViews(
            for: tab,
            intent: .retirement
        )
        XCTAssertNil(graph.runtimeTabs.boundTab(tab.id))
        XCTAssertEqual(graph.runtimeTabs.bind(tab), .retiredIdentity)
    }

    func testCommittedBatchRetirementTombstonesRuntimeIdentityBeforeDestroy()
        throws {
        let repository = WebViewSessionRepository()
        let tab = makeTab(webViewSessions: repository)
        let graph = makeTestWebViewRuntimeGraph(
            webViewSessions: repository,
            resolveRuntimeTab: { id in id == tab.id ? tab : nil }
        )
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        repository.noteParkedWebView(webView, for: tab.id)
        let retirement = WebViewCommittedTabRetirementService(
            runtimeTabs: graph.runtimeTabs,
            generations: graph.retiredGenerationDestroyer
        )
        XCTAssertTrue(retirement.canAdmit([tab]))
        let modelReceipt = WebViewRetirementModelTransactionReceipt(
            isCurrent: { true },
            commit: { true },
            rollback: { true }
        )
        guard case .began(let lease) = repository.beginRetirementBatch(
            [WebViewRetirementBatchEntry(
                tabID: tab.id,
                expectedGeneration: tab.webViewSession.generation
            )],
            modelTransaction: modelReceipt
        ) else { return XCTFail("Expected exact retirement lease") }
        guard case .committed(let retired) = repository
            .commitRetirementBatch(lease) else {
            return XCTFail("Expected committed retirement generation")
        }
        let generation = RetiredTabWebViewGeneration(
            tabID: tab.id,
            snapshot: try XCTUnwrap(retired[tab.id])
        )

        XCTAssertTrue(retirement.beginCommitted([tab]))
        XCTAssertNil(graph.runtimeTabs.boundTab(tab.id))
        XCTAssertTrue(graph.runtimeTabs.isRetiring(tab))
        XCTAssertEqual(graph.runtimeTabs.bind(tab), .retiredIdentity)
        let replacement = makeTab(
            id: tab.id,
            webViewSessions: repository
        )
        XCTAssertEqual(
            graph.runtimeTabs.bind(replacement),
            .identityConflict
        )

        retirement.destroy([generation], completing: [tab])

        XCTAssertFalse(graph.runtimeTabs.isRetiring(tab))
        XCTAssertEqual(graph.runtimeTabs.bind(tab), .retiredIdentity)
        XCTAssertEqual(graph.runtimeTabs.bind(replacement), .bound)
        XCTAssertNil(repository.residence(of: webView))
    }

    func testRetirementReportsBlockedRepositoryReplacementWithoutDestroyingIt() {
        let repository = WebViewSessionRepository()
        let graph = makeTestWebViewRuntimeGraph(webViewSessions: repository)
        let transaction = TabMainFrameRuntimeTransaction(
            initialURL: URL(string: "about:blank")!
        )
        let tab = makeTab(
            webViewSessions: repository,
            mainFrameRuntimeTransaction: transaction
        )
        let windowID = UUID()
        let current = FocusableWKWebView()
        current.owningTab = tab
        XCTAssertTrue(
            graph.trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                current,
                for: tab,
                in: windowID
            ).isAccepted
        )
        _ = transaction.beginRecovery(on: current)
        XCTAssertTrue(graph.processRecoveryService.retain(current, for: tab))
        XCTAssertTrue(graph.processRecoveryService.hasPendingRecovery(for: current))
        let replacement = FocusableWKWebView()
        replacement.owningTab = tab
        guard case .began(let lease) = repository.beginWindowSetReplacement(
            for: tab.id,
            expectedGeneration: repository.queries.generation(for: tab.id),
            webViewsByWindowID: [windowID: replacement],
            primaryWindowID: windowID
        ) else {
            return XCTFail("Expected raw repository replacement transaction")
        }

        let blocked = graph.lifecycleService.removeAllWebViews(
            for: tab,
            intent: .retirement
        )

        XCTAssertEqual(blocked, .init(
            discoveredWebViewCount: 1,
            cleanedWebViewCount: 0,
            deferredWebViewCount: 0,
            unscheduledProtectedWebViewCount: 0,
            blockedWebViewCount: 1
        ))
        XCTAssertTrue(graph.runtimeTabs.isRetiring(tab))
        XCTAssertIdentical(
            repository.webView(for: tab.id, in: windowID),
            replacement
        )
        guard case .retiring = repository.residence(of: current) else {
            return XCTFail("Retired generation lost its transaction residence")
        }
        XCTAssertTrue(graph.processRecoveryService.hasPendingRecovery(for: current))

        guard case .rolledBack = repository.rollbackReplacementBatch(lease) else {
            return XCTFail("Expected raw transaction rollback")
        }
        let completed = graph.lifecycleService.removeAllWebViews(
            for: tab,
            intent: .retirement
        )
        XCTAssertTrue(completed.isComplete)
        XCTAssertTrue(repository.runtimeOwnedTabIDs.isEmpty)
        XCTAssertFalse(graph.runtimeTabs.isRetiring(tab))
        XCTAssertFalse(graph.processRecoveryService.hasPendingRecovery(for: current))
    }

    func testRepeatedProtectedRetirementKeepsCleanupIdentityUntilResidenceDrains()
        async throws {
        let manager = BrowserManager()
        let graph = manager.testWebViewRuntime()
        let tab = manager.tabFactory.makeTab(
            url: URL(string: "https://example.com/protected-retirement")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = manager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: manager))
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(
                reason: "test.protected-retirement",
                prepareExtensionRuntime: false
            ) as? FocusableWKWebView
        )
        XCTAssertIdentical(webView.owningTab, tab)
        XCTAssertTrue(
            graph.untrackedWebViewInstallationService
                .installUntracked(webView, for: tab).isAccepted
        )
        let protection = graph.mediaProtectionOwner
            .beginVisualHandoffProtection(for: webView)
        let expected = WebViewTabTeardownResult(
            discoveredWebViewCount: 1,
            cleanedWebViewCount: 0,
            deferredWebViewCount: 1,
            unscheduledProtectedWebViewCount: 0
        )

        XCTAssertEqual(
            graph.lifecycleService.removeAllWebViews(
                for: tab,
                intent: .retirement
            ),
            expected
        )
        XCTAssertTrue(graph.runtimeTabs.isRetiring(tab))
        XCTAssertEqual(graph.runtimeTabs.bind(tab), .retiredIdentity)
        XCTAssertNil(graph.runtimeTabs.resolve(tab.id) { _ in tab })
        let blockedReplacement = makeTab(
            id: tab.id,
            webViewSessions: graph.webViewSessions
        )
        XCTAssertEqual(
            graph.runtimeTabs.bind(blockedReplacement),
            .identityConflict
        )
        XCTAssertIdentical(tab.webViewSession.untrackedWebView, webView)

        XCTAssertEqual(
            graph.lifecycleService.removeAllWebViews(
                for: tab,
                intent: .retirement
            ),
            expected
        )
        XCTAssertTrue(graph.runtimeTabs.isRetiring(tab))
        XCTAssertIdentical(
            graph.runtimeTabs.tabForCleanup(tab.id) { _ in nil },
            tab
        )

        let webViewID = try XCTUnwrap(
            graph.mediaProtectionOwner.finishVisualHandoffProtection(protection)
        )
        graph.protectionRuntime.flush(for: webViewID)
        for _ in 0..<20 {
            await Task.yield()
            if tab.webViewSession.untrackedWebView == nil { break }
        }

        XCTAssertNil(tab.webViewSession.untrackedWebView)
        XCTAssertFalse(graph.runtimeTabs.isRetiring(tab))
        let replacement = makeTab(
            id: tab.id,
            webViewSessions: graph.webViewSessions
        )
        XCTAssertEqual(graph.runtimeTabs.bind(replacement), .bound)
    }

    func testRetiredTabCannotRecreateTrackedOrExtensionWebView() {
        let manager = BrowserManager()
        let graph = manager.testWebViewRuntime()
        let tab = manager.tabFactory.makeTab(
            url: URL(string: "https://example.com/retired")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = manager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: manager))
        XCTAssertEqual(graph.runtimeTabs.bind(tab), .bound)
        _ = graph.lifecycleService.removeAllWebViews(
            for: tab,
            intent: .retirement
        )
        let generationAfterRetirement = graph.webViewSessions
            .residenceGeneration

        XCTAssertNil(graph.trackedWebViewAdmission.webView(
            for: tab,
            in: UUID()
        ))
        let replacement = graph.extensionTabWebViewReplacement.replace(
            for: tab,
            in: UUID(),
            reason: "test.retired-replacement"
        )

        guard case .rejected(.runtimeTabIdentityConflict) = replacement else {
            return XCTFail("Retired Tab replacement must fail closed")
        }
        XCTAssertEqual(
            graph.webViewSessions.residenceGeneration,
            generationAfterRetirement
        )
        XCTAssertTrue(graph.webViewSessions.runtimeOwnedTabIDs.isEmpty)
    }

    func testTerminalRuntimeCannotRebindOrRecreateWebViews() {
        let manager = BrowserManager()
        let graph = manager.testWebViewRuntime()
        let tab = manager.tabFactory.makeTab(
            url: URL(string: "https://example.com/terminal")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = manager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: manager))
        XCTAssertEqual(graph.runtimeTabs.bind(tab), .bound)

        graph.lifecycleService.cleanupAfterBrowserRuntimeDeallocation()
        let generationAfterShutdown = graph.webViewSessions.residenceGeneration

        XCTAssertEqual(graph.runtimeTabs.bind(tab), .runtimeTerminated)
        XCTAssertNil(graph.runtimeTabs.boundTab(tab.id))
        XCTAssertNil(graph.trackedWebViewAdmission.webView(
            for: tab,
            in: UUID()
        ))
        guard case .rejected(.runtimeTabIdentityConflict) =
            graph.extensionTabWebViewReplacement.replace(
                for: tab,
                in: nil,
                reason: "test.terminal-replacement"
            ) else {
            return XCTFail("Terminal runtime replacement must fail closed")
        }
        XCTAssertEqual(
            graph.webViewSessions.residenceGeneration,
            generationAfterShutdown
        )
        XCTAssertTrue(graph.webViewSessions.runtimeOwnedTabIDs.isEmpty)
    }

    private func makeTab(
        id: UUID = UUID(),
        webViewSessions: WebViewSessionRepository,
        mainFrameRuntimeTransaction: TabMainFrameRuntimeTransaction? = nil
    ) -> Tab {
        Tab(
            id: id,
            url: URL(string: "about:blank")!,
            webViewSessions: webViewSessions,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: mainFrameRuntimeTransaction
        )
    }
}
