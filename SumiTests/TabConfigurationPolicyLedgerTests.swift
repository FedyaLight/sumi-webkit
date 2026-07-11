import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabConfigurationPolicyLedgerTests: XCTestCase {
    func testProvisionalWebViewDoesNotChangeCommittedPolicy() {
        let ledger = TabConfigurationPolicyLedger()
        let webView = WKWebView()
        let receipt = ledger.prepare(
            state(profileID: UUID(), dataStore: webView.configuration.websiteDataStore),
            expectedSessionGeneration: 0
        )
        webView.sumiPreparedConfigurationPolicyChange = receipt

        XCTAssertEqual(ledger.committedState, .unknown)
        XCTAssertEqual(ledger.revision, 0)
        XCTAssertEqual(receipt.phase, .prepared)

        let changeSet = try! XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [webView],
                policyLedger: ledger
            )
        )
        changeSet.cancel()

        XCTAssertEqual(ledger.committedState, .unknown)
        XCTAssertEqual(ledger.revision, 0)
        XCTAssertEqual(receipt.phase, .cancelled)
        XCTAssertNil(webView.sumiPreparedConfigurationPolicyChange)
    }

    func testStaleReceiptCannotOverwriteNewerCommittedPolicy() throws {
        let ledger = TabConfigurationPolicyLedger()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let oldState = state(profileID: UUID(), dataStore: dataStore)
        var newState = oldState
        newState.autoplayState = .blockAll
        let oldWebView = WKWebView()
        let newWebView = WKWebView()
        let oldReceipt = ledger.prepare(
            oldState,
            expectedSessionGeneration: 4
        )
        let newReceipt = ledger.prepare(
            newState,
            expectedSessionGeneration: 4
        )
        oldWebView.sumiPreparedConfigurationPolicyChange = oldReceipt
        newWebView.sumiPreparedConfigurationPolicyChange = newReceipt

        let newChangeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [newWebView],
                policyLedger: ledger
            )
        )
        XCTAssertTrue(newChangeSet.commit(as: .canonicalGeneration))
        XCTAssertEqual(ledger.committedState, newState)
        XCTAssertEqual(ledger.revision, 1)

        let staleChangeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [oldWebView],
                policyLedger: ledger
            )
        )
        XCTAssertFalse(staleChangeSet.commit(as: .canonicalGeneration))
        XCTAssertEqual(oldReceipt.phase, .cancelled)
        XCTAssertEqual(ledger.committedState, newState)
        XCTAssertEqual(ledger.revision, 1)
    }

    func testCloneSetCommitsOneCoherentRevision() throws {
        let ledger = TabConfigurationPolicyLedger()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let policy = state(profileID: UUID(), dataStore: dataStore)
        let webViews = [WKWebView(), WKWebView()]
        let receipts = webViews.map { webView in
            let receipt = ledger.prepare(
                policy,
                expectedSessionGeneration: 7
            )
            webView.sumiPreparedConfigurationPolicyChange = receipt
            return receipt
        }

        let changeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: webViews,
                policyLedger: ledger
            )
        )
        XCTAssertTrue(changeSet.commit(as: .canonicalGeneration))

        XCTAssertEqual(ledger.committedState, policy)
        XCTAssertEqual(ledger.revision, 1)
        XCTAssertTrue(receipts.allSatisfy { $0.phase == .committed })
        XCTAssertTrue(
            webViews.allSatisfy {
                $0.sumiPreparedConfigurationPolicyChange == nil
            }
        )
    }

    func testAdditionalCloneCanOnlyConfirmCommittedFingerprint() throws {
        let ledger = TabConfigurationPolicyLedger()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let committed = state(profileID: UUID(), dataStore: dataStore)
        let primary = WKWebView()
        primary.sumiPreparedConfigurationPolicyChange = ledger.prepare(
            committed,
            expectedSessionGeneration: 0
        )
        let primaryChangeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [primary],
                policyLedger: ledger
            )
        )
        XCTAssertTrue(primaryChangeSet.commit(as: .canonicalGeneration))

        var different = committed
        different.autoplayState = .blockAudible
        let clone = WKWebView()
        clone.sumiPreparedConfigurationPolicyChange = ledger.prepare(
            different,
            expectedSessionGeneration: 1
        )
        let cloneChangeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [clone],
                policyLedger: ledger
            )
        )

        XCTAssertFalse(cloneChangeSet.canCommit(as: .additionalClone))
        XCTAssertFalse(cloneChangeSet.commit(as: .additionalClone))
        XCTAssertEqual(ledger.committedState, committed)
        XCTAssertEqual(ledger.revision, 1)
    }

    func testAdditionalCloneAcceptsSameEffectiveRulesAcrossHosts() throws {
        let ledger = TabConfigurationPolicyLedger()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        var committed = state(profileID: UUID(), dataStore: dataStore)
        committed.safariContentBlockerAttachment =
            SumiSafariContentBlockerAttachmentState(
                siteHost: "a.example",
                isEnabledForSite: true,
                enabledContentBlockerIds: ["logical-a"],
                enabledContentBlockerRuleIdentities: ["rules:v1"]
            )
        try commit(committed, to: ledger, generation: 0)

        var cloneState = committed
        cloneState.safariContentBlockerAttachment =
            SumiSafariContentBlockerAttachmentState(
                siteHost: "b.example",
                isEnabledForSite: true,
                enabledContentBlockerIds: ["logical-b"],
                enabledContentBlockerRuleIdentities: ["rules:v1"]
            )
        let clone = WKWebView()
        clone.sumiPreparedConfigurationPolicyChange = ledger.prepare(
            cloneState,
            expectedSessionGeneration: 1
        )
        let cloneChangeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [clone],
                policyLedger: ledger
            )
        )

        XCTAssertTrue(cloneChangeSet.canCommit(as: .additionalClone))
        XCTAssertTrue(cloneChangeSet.commit(as: .additionalClone))
        XCTAssertEqual(ledger.committedState, committed)
        XCTAssertEqual(ledger.revision, 1)
    }

    func testMixedClonePolicySetCancelsWithoutLedgerMutation() {
        let ledger = TabConfigurationPolicyLedger()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let firstState = state(profileID: UUID(), dataStore: dataStore)
        var secondState = firstState
        secondState.autoplayState = .blockAll
        let webViews = [WKWebView(), WKWebView()]
        let receipts = [firstState, secondState].enumerated().map {
            index, policyState in
            let receipt = ledger.prepare(
                policyState,
                expectedSessionGeneration: 2
            )
            webViews[index].sumiPreparedConfigurationPolicyChange = receipt
            return receipt
        }

        XCTAssertNil(
            PreparedConfigurationPolicyChangeSet(
                webViews: webViews,
                policyLedger: ledger
            )
        )
        XCTAssertTrue(receipts.allSatisfy { $0.phase == .cancelled })
        XCTAssertTrue(
            webViews.allSatisfy {
                $0.sumiPreparedConfigurationPolicyChange == nil
            }
        )
        XCTAssertEqual(ledger.committedState, .unknown)
        XCTAssertEqual(ledger.revision, 0)
    }

    func testNewerCloneSettlementMakesOlderCanonicalReceiptStale() throws {
        let ledger = TabConfigurationPolicyLedger()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let committed = state(profileID: UUID(), dataStore: dataStore)
        try commit(committed, to: ledger, generation: 0)

        var olderCanonicalState = committed
        olderCanonicalState.autoplayState = .blockAll
        let olderCanonical = WKWebView()
        olderCanonical.sumiPreparedConfigurationPolicyChange = ledger.prepare(
            olderCanonicalState,
            expectedSessionGeneration: 1
        )
        let olderCanonicalChangeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [olderCanonical],
                policyLedger: ledger
            )
        )

        let newerClone = WKWebView()
        newerClone.sumiPreparedConfigurationPolicyChange = ledger.prepare(
            committed,
            expectedSessionGeneration: 1
        )
        let newerCloneChangeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [newerClone],
                policyLedger: ledger
            )
        )
        XCTAssertTrue(
            newerCloneChangeSet.commit(as: .additionalClone)
        )

        XCTAssertFalse(
            olderCanonicalChangeSet.commit(as: .canonicalGeneration)
        )
        XCTAssertEqual(ledger.committedState, committed)
        XCTAssertEqual(ledger.revision, 1)
    }

    func testProfileAndDataStoreIdentityAdvancePhysicalPolicyRevision() throws {
        let ledger = TabConfigurationPolicyLedger()
        let firstStore = WKWebsiteDataStore.nonPersistent()
        let secondStore = WKWebsiteDataStore.nonPersistent()
        let first = state(profileID: UUID(), dataStore: firstStore)
        var second = first
        second.profileID = UUID()
        second.websiteDataStoreIdentity = ObjectIdentifier(secondStore)

        try commit(first, to: ledger, generation: 0)
        try commit(second, to: ledger, generation: 1)

        XCTAssertEqual(ledger.committedState, second)
        XCTAssertEqual(ledger.revision, 2)
    }

    func testReceiptSettlesOnlyOnce() throws {
        let ledger = TabConfigurationPolicyLedger()
        let webView = WKWebView()
        let receipt = ledger.prepare(
            state(profileID: UUID(), dataStore: webView.configuration.websiteDataStore),
            expectedSessionGeneration: 0
        )
        webView.sumiPreparedConfigurationPolicyChange = receipt
        let changeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [webView],
                policyLedger: ledger
            )
        )

        changeSet.cancel()
        changeSet.cancel()
        XCTAssertFalse(changeSet.commit(as: .canonicalGeneration))

        XCTAssertEqual(receipt.phase, .cancelled)
        XCTAssertEqual(ledger.revision, 0)
    }

    func testRawNormalCanonicalWebViewIsRejectedWithoutMutatingLedger() throws {
        let tab = Tab(url: URL(string: "https://example.com")!)
        try commit(
            TabConfigurationPolicyState(
                profileID: nil,
                websiteDataStoreIdentity: nil,
                protectionAttachment: .disabled(
                    siteHost: "old.example"
                ),
                safariContentBlockerAttachment: nil,
                autoplayState: nil
            ),
            to: tab.configurationPolicyLedger,
            generation: tab.webViewSession.generation
        )
        let oldRevision = tab.configurationPolicyLedger.revision
        let oldState = tab.configurationPolicyLedger.committedState
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        configuration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let rawNormalWebView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        XCTAssertNil(
            tab.configurationPolicyTransaction.preparePlacementAdmission(
                [rawNormalWebView],
                as: .canonicalGeneration
            )
        )
        XCTAssertEqual(tab.configurationPolicyLedger.committedState, oldState)
        XCTAssertEqual(
            tab.configurationPolicyLedger.revision,
            oldRevision
        )
        XCTAssertNil(
            tab.configurationPolicyTransaction.preparePlacementAdmission(
                [rawNormalWebView],
                as: .additionalClone
            )
        )
    }

    func testCommittedReceiptCannotAuthorizeRawNormalSubset() throws {
        let tab = Tab(url: URL(string: "https://example.com/subset")!)
        let evidenceConfiguration = WKWebViewConfiguration()
        evidenceConfiguration.sumiIsNormalTabWebViewConfiguration = true
        let evidenceWebView = WKWebView(
            frame: .zero,
            configuration: evidenceConfiguration
        )
        let receipt = tab.configurationPolicyLedger.prepare(
            state(
                profileID: UUID(),
                dataStore: evidenceWebView.configuration.websiteDataStore
            ),
            expectedSessionGeneration: tab.webViewSession.generation
        )
        evidenceWebView.sumiPreparedConfigurationPolicyChange = receipt
        let changeSet = try XCTUnwrap(
            tab.preparedConfigurationPolicyChangeSet(
                for: [evidenceWebView]
            )
        )
        XCTAssertTrue(changeSet.commit(as: .canonicalGeneration))
        evidenceWebView.sumiPreparedConfigurationPolicyChange = receipt

        let rawConfiguration = WKWebViewConfiguration()
        rawConfiguration.sumiIsNormalTabWebViewConfiguration = true
        let rawWebView = WKWebView(
            frame: .zero,
            configuration: rawConfiguration
        )
        let committedRevision = tab.configurationPolicyLedger.revision

        XCTAssertNil(
            tab.configurationPolicyTransaction.preparePlacementAdmission(
                [evidenceWebView, rawWebView],
                as: .canonicalGeneration
            )
        )
        XCTAssertEqual(receipt.phase, .committed)
        XCTAssertNil(
            evidenceWebView.sumiPreparedConfigurationPolicyChange,
            "A committed receipt is stale placement evidence and must be detached fail-closed"
        )
        XCTAssertEqual(
            tab.configurationPolicyLedger.revision,
            committedRevision
        )
    }

    func testCommittedReceiptCannotBeReplayed() throws {
        let tab = Tab(url: URL(string: "https://example.com/replay")!)
        let webView = WKWebView()
        let receipt = tab.configurationPolicyTransaction.prepare(
            state(
                profileID: UUID(),
                dataStore: webView.configuration.websiteDataStore
            )
        )
        webView.sumiPreparedConfigurationPolicyChange = receipt
        let changeSet = try XCTUnwrap(
            tab.preparedConfigurationPolicyChangeSet(for: [webView])
        )
        XCTAssertTrue(changeSet.commit(as: .canonicalGeneration))
        webView.sumiPreparedConfigurationPolicyChange = receipt
        let committedRevision = tab.configurationPolicyLedger.revision

        XCTAssertNil(
            tab.configurationPolicyTransaction.preparePlacementAdmission(
                [webView],
                as: .canonicalGeneration
            )
        )
        XCTAssertEqual(receipt.phase, .committed)
        XCTAssertNil(
            webView.sumiPreparedConfigurationPolicyChange,
            "A replay attempt must consume the stale WebView association without changing the committed receipt"
        )
        XCTAssertEqual(
            tab.configurationPolicyLedger.revision,
            committedRevision
        )
    }

    func testPolicyTransactionUsesConcreteSessionGeneration() {
        let tab = Tab(url: URL(string: "https://example.com/generation")!)
        let webView = WKWebView()
        let receipt = tab.configurationPolicyTransaction.prepare(
            state(
                profileID: UUID(),
                dataStore: webView.configuration.websiteDataStore
            )
        )
        webView.sumiPreparedConfigurationPolicyChange = receipt
        let preparedGeneration = receipt.expectedSessionGeneration

        tab.webViewSession.replaceUntracked(with: WKWebView())

        XCTAssertNotEqual(
            tab.webViewSession.generation,
            preparedGeneration
        )
        XCTAssertNil(
            tab.configurationPolicyTransaction.preparePlacementAdmission(
                [webView],
                as: .canonicalGeneration
            )
        )
        XCTAssertEqual(tab.configurationPolicyLedger.revision, 0)
        tab.cancelConfigurationPolicy(for: [webView])
    }

    func testPlacementAdmissionRejectsNoPlacement() throws {
        let tab = Tab(url: URL(string: "https://example.com/no-placement")!)
        let candidate = WKWebView()
        let receipt = tab.configurationPolicyTransaction.prepare(
            state(
                profileID: UUID(),
                dataStore: candidate.configuration.websiteDataStore
            )
        )
        candidate.sumiPreparedConfigurationPolicyChange = receipt
        let admission = try XCTUnwrap(
            tab.configurationPolicyTransaction.preparePlacementAdmission(
                [candidate],
                as: .canonicalGeneration
            )
        )

        XCTAssertFalse(
            tab.configurationPolicyTransaction.commit(admission)
        )
        XCTAssertEqual(receipt.phase, .prepared)
        XCTAssertEqual(tab.configurationPolicyLedger.committedState, .unknown)
        tab.cancelConfigurationPolicy(for: [candidate])
    }

    func testPlacementAdmissionRejectsStalePolicy() throws {
        let tab = Tab(url: URL(string: "https://example.com/stale-policy")!)
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let candidate = WKWebView()
        let candidateState = state(profileID: UUID(), dataStore: dataStore)
        let receipt = tab.configurationPolicyTransaction.prepare(
            candidateState
        )
        candidate.sumiPreparedConfigurationPolicyChange = receipt
        let admission = try XCTUnwrap(
            tab.configurationPolicyTransaction.preparePlacementAdmission(
                [candidate],
                as: .canonicalGeneration
            )
        )

        var newerState = candidateState
        newerState.autoplayState = .blockAll
        try commit(
            newerState,
            to: tab.configurationPolicyLedger,
            generation: tab.webViewSession.generation
        )
        tab.webViewSession.replaceUntracked(with: candidate)

        XCTAssertFalse(
            tab.configurationPolicyTransaction.commit(admission)
        )
        XCTAssertEqual(receipt.phase, .prepared)
        XCTAssertEqual(
            tab.configurationPolicyLedger.committedState,
            newerState
        )
        tab.cancelConfigurationPolicy(for: [candidate])
    }

    func testPlacementAdmissionRejectsWrongCanonicalWebView() throws {
        let tab = Tab(url: URL(string: "https://example.com/wrong-canonical")!)
        let candidate = WKWebView()
        let receipt = tab.configurationPolicyTransaction.prepare(
            state(
                profileID: UUID(),
                dataStore: candidate.configuration.websiteDataStore
            )
        )
        candidate.sumiPreparedConfigurationPolicyChange = receipt
        let admission = try XCTUnwrap(
            tab.configurationPolicyTransaction.preparePlacementAdmission(
                [candidate],
                as: .canonicalGeneration
            )
        )

        let wrongCanonical = WKWebView()
        tab.webViewSession.replaceUntracked(with: wrongCanonical)

        XCTAssertFalse(
            tab.configurationPolicyTransaction.commit(admission)
        )
        XCTAssertIdentical(
            tab.webViewSession.currentWebView,
            wrongCanonical
        )
        XCTAssertEqual(receipt.phase, .prepared)
        XCTAssertEqual(tab.configurationPolicyLedger.committedState, .unknown)
        tab.cancelConfigurationPolicy(for: [candidate])
    }

    func testPreparedWebViewCannotCommitThroughAnotherTabAtSameGeneration() {
        let preparingTab = Tab(url: URL(string: "https://a.example")!)
        let receivingTab = Tab(url: URL(string: "https://b.example")!)
        XCTAssertEqual(
            preparingTab.webViewSession.generation,
            receivingTab.webViewSession.generation
        )

        let webView = WKWebView()
        let receipt = preparingTab.configurationPolicyLedger.prepare(
            state(
                profileID: UUID(),
                dataStore: webView.configuration.websiteDataStore
            ),
            expectedSessionGeneration: receivingTab.webViewSession.generation
        )
        webView.sumiPreparedConfigurationPolicyChange = receipt

        XCTAssertNil(
            receivingTab.configurationPolicyTransaction
                .preparePlacementAdmission(
                    [webView],
                    as: .canonicalGeneration
                )
        )
        XCTAssertEqual(
            preparingTab.configurationPolicyLedger.committedState,
            .unknown
        )
        XCTAssertEqual(
            receivingTab.configurationPolicyLedger.committedState,
            .unknown
        )
        XCTAssertEqual(receipt.phase, .prepared)

        preparingTab.cancelConfigurationPolicy(for: [webView])
    }

    func testCancellingThroughAnotherTabPreservesForeignReceipt() {
        let preparingTab = Tab(url: URL(string: "https://a.example")!)
        let foreignTab = Tab(url: URL(string: "https://b.example")!)
        let webView = WKWebView()
        let receipt = preparingTab.configurationPolicyTransaction.prepare(
            state(
                profileID: UUID(),
                dataStore: webView.configuration.websiteDataStore
            )
        )
        webView.sumiPreparedConfigurationPolicyChange = receipt

        foreignTab.cancelConfigurationPolicy(for: [webView])

        XCTAssertEqual(receipt.phase, .prepared)
        XCTAssertIdentical(
            webView.sumiPreparedConfigurationPolicyChange,
            receipt
        )
        preparingTab.cancelConfigurationPolicy(for: [webView])
        XCTAssertEqual(receipt.phase, .cancelled)
        XCTAssertNil(webView.sumiPreparedConfigurationPolicyChange)
    }

    private func commit(
        _ state: TabConfigurationPolicyState,
        to ledger: TabConfigurationPolicyLedger,
        generation: UInt64
    ) throws {
        let webView = WKWebView()
        webView.sumiPreparedConfigurationPolicyChange = ledger.prepare(
            state,
            expectedSessionGeneration: generation
        )
        let changeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [webView],
                policyLedger: ledger
            )
        )
        XCTAssertTrue(changeSet.commit(as: .canonicalGeneration))
    }

    private func state(
        profileID: UUID,
        dataStore: WKWebsiteDataStore
    ) -> TabConfigurationPolicyState {
        TabConfigurationPolicyState(
            profileID: profileID,
            websiteDataStoreIdentity: ObjectIdentifier(dataStore),
            protectionAttachment: .disabled(siteHost: "example.com"),
            safariContentBlockerAttachment: .disabled(
                siteHost: "example.com"
            ),
            autoplayState: .allowAll
        )
    }
}
