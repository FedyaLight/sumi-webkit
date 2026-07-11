import XCTest

@testable import Sumi

@MainActor
final class TabExtensionPageRuntimeOwnerTests: XCTestCase {
    func testPrepareGenerationResetsReportedAndOpenNotificationState() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.lastReportedURL = URL(string: "https://old.example")
        XCTAssertTrue(owner.recordReportedLoadingCompleteIfChanged(true))
        owner.lastReportedTitle = "Old"
        owner.markEligible(for: 3)
        owner.noteCommittedMainDocumentNavigation(to: URL(string: "https://example.com")!)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 7,
            contextReadiness: .missing
        )
        owner.markDidOpenTab(generation: 3)

        owner.prepareGeneration(4)

        XCTAssertEqual(owner.controllerGeneration, 4)
        XCTAssertNil(owner.lastReportedURL)
        XCTAssertFalse(owner.hasReportedLoadingComplete)
        XCTAssertNil(owner.lastReportedTitle)
        XCTAssertEqual(owner.lastOpenNotificationGeneration, 0)
        XCTAssertEqual(owner.eligibleGeneration, 0)
        XCTAssertNil(owner.openNotifiedDocumentSequence)
        XCTAssertNil(owner.openNotifiedContextBindingGeneration)
        XCTAssertEqual(owner.openNotifiedContextReadiness, .notNotified)
        XCTAssertFalse(owner.didNotifyOpenToExtensions)
    }

    func testCommittedNavigationAdvancesPageIdentity() {
        let owner = TabExtensionPageRuntimeOwner()
        let tabId = UUID()
        let initial = owner.pageIdentity(tabId: tabId)

        owner.noteCommittedMainDocumentNavigation(to: URL(string: "https://example.com/page")!)
        let committed = owner.pageIdentity(tabId: tabId)

        XCTAssertEqual(initial.pageGeneration, "0")
        XCTAssertEqual(committed.pageGeneration, "1")
        XCTAssertEqual(committed.pageId, "\(committed.tabId):1")
        XCTAssertEqual(owner.committedMainDocumentURL, URL(string: "https://example.com/page")!)
        XCTAssertTrue(owner.isCurrentPage(
            tabId: tabId,
            pageId: committed.pageId,
            pageGeneration: committed.pageGeneration
        ))
        XCTAssertFalse(owner.isCurrentPage(
            tabId: tabId,
            pageId: initial.pageId,
            pageGeneration: initial.pageGeneration
        ))
    }

    func testOpenNotificationCapturesCurrentDocumentBinding() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.noteCommittedMainDocumentNavigation(to: URL(string: "https://example.com")!)

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 11,
            contextReadiness: .loaded
        )
        owner.markDidOpenTab(generation: 5)

        XCTAssertEqual(owner.openNotifiedDocumentSequence, owner.documentSequence)
        XCTAssertEqual(owner.openNotifiedContextBindingGeneration, 11)
        XCTAssertEqual(owner.openNotifiedContextReadiness, .loaded)
        XCTAssertEqual(owner.lastOpenNotificationGeneration, 5)
        XCTAssertTrue(owner.didNotifyOpenToExtensions)
        XCTAssertTrue(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: 5
        ))
        XCTAssertFalse(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: 4
        ))
    }

    func testDocumentBindingSnapshotAndLifecycleQueriesDescribeOwnedState() {
        let owner = TabExtensionPageRuntimeOwner()
        let url = URL(string: "https://example.com/page")!

        owner.noteCommittedMainDocumentNavigation(to: url)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 11,
            contextReadiness: .missing
        )

        let snapshot = owner.documentBindingSnapshot()
        XCTAssertEqual(snapshot.documentSequence, 1)
        XCTAssertEqual(snapshot.committedMainDocumentURL, url)
        XCTAssertEqual(snapshot.openNotifiedDocumentSequence, 1)
        XCTAssertEqual(snapshot.openNotifiedContextBindingGeneration, 11)
        XCTAssertEqual(snapshot.openNotifiedContextReadiness, .missing)
        XCTAssertEqual(owner.committedMainDocumentURLForCurrentPage(), url)
        XCTAssertTrue(owner.hasCommittedDocumentBinding())
        XCTAssertTrue(owner.hasDocumentBindingForLifecycleRebind())
        XCTAssertFalse(owner.shouldSkipPreCommitRebindForInitialDocument())
    }

    func testInitialDocumentOpenNotificationCanSkipPreCommitRebind() {
        let owner = TabExtensionPageRuntimeOwner()

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 11,
            contextReadiness: .loaded
        )

        XCTAssertTrue(owner.shouldSkipPreCommitRebindForInitialDocument())
        XCTAssertFalse(owner.hasCommittedDocumentBinding())
        XCTAssertTrue(owner.hasDocumentBindingForLifecycleRebind())
    }

    func testReportedTabPropertiesCoalesceThroughOwner() {
        let owner = TabExtensionPageRuntimeOwner()
        let url = URL(string: "https://example.com/page")!

        XCTAssertTrue(owner.recordReportedURLIfChanged(url))
        XCTAssertFalse(owner.recordReportedURLIfChanged(url))
        XCTAssertTrue(owner.recordReportedURLIfChanged(URL(string: "https://example.com/other")!))

        XCTAssertTrue(owner.recordReportedLoadingCompleteIfChanged(true))
        XCTAssertFalse(owner.recordReportedLoadingCompleteIfChanged(true))
        XCTAssertTrue(owner.recordReportedLoadingCompleteIfChanged(false))

        XCTAssertTrue(owner.recordReportedTitleIfChanged("Title"))
        XCTAssertFalse(owner.recordReportedTitleIfChanged("Title"))
        XCTAssertTrue(owner.recordReportedTitleIfChanged(nil))
    }

    func testResetDocumentBindingClearsCommittedURLAndOpenNotificationContext() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.noteCommittedMainDocumentNavigation(to: URL(string: "https://example.com")!)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 11,
            contextReadiness: .loaded
        )

        owner.resetDocumentBindingForContentScriptRebind()

        XCTAssertEqual(owner.documentSequence, 0)
        XCTAssertNil(owner.committedMainDocumentURL)
        XCTAssertNil(owner.openNotifiedDocumentSequence)
        XCTAssertNil(owner.openNotifiedContextBindingGeneration)
        XCTAssertEqual(owner.openNotifiedContextReadiness, .notNotified)
    }

    func testDidNotifyOpenSetterOnlyClearsGenerationForFalseCompatibilityWrite() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.markDidOpenTab(generation: 7)

        owner.didNotifyOpenToExtensions = true

        XCTAssertEqual(owner.lastOpenNotificationGeneration, 7)

        owner.didNotifyOpenToExtensions = false

        XCTAssertEqual(owner.lastOpenNotificationGeneration, 0)
        XCTAssertFalse(owner.didNotifyOpenToExtensions)
    }

    func testEligibilityIsOwnedByRuntimeGeneration() {
        let owner = TabExtensionPageRuntimeOwner()

        XCTAssertFalse(owner.isEligible(for: 2))

        owner.markEligible(for: 2)

        XCTAssertTrue(owner.isEligible(for: 2))
        XCTAssertFalse(owner.isEligible(for: 3))
    }

    func testCurrentDocumentOpenNotificationInvalidatesWhenDocumentChanges() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.noteCommittedMainDocumentNavigation(to: URL(string: "https://example.com/one")!)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 1,
            contextReadiness: .loaded
        )
        owner.markDidOpenTab(generation: 9)

        XCTAssertTrue(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: 9
        ))

        owner.invalidatePageForWebViewReplacement()

        XCTAssertFalse(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: 9
        ))
        XCTAssertEqual(owner.committedMainDocumentURL, URL(string: "https://example.com/one")!)
    }

    func testCommittedWindowPrepublicationRevokeRestoresExactSnapshot() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: 17)
        XCTAssertTrue(
            owner.commitWindowPrepublication(
                token,
                willEmitOpen: true
            )
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: 17,
                committedWindowPrepublication: token
            )
        )

        XCTAssertTrue(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: 17
            )
        )
        XCTAssertEqual(owner.controllerGeneration, 0)
        XCTAssertEqual(owner.currentEligibleGeneration(), 0)
        XCTAssertEqual(owner.currentOpenNotificationGeneration(), 0)
        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: 17
            )
        )
    }

    func testNewPublisherMakesOldWindowPrepublicationTokenStale() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: 23)
        XCTAssertTrue(
            owner.commitWindowPrepublication(
                token,
                willEmitOpen: true
            )
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: 23,
                committedWindowPrepublication: token
            )
        )

        let originalClaim = owner.currentOpenPublicationClaim(generation: 23)
        XCTAssertNotNil(originalClaim)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                originalClaim!,
                generation: 23
            )
        )
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 1,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: 23))

        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: 23
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: 23))
    }

    func testPreexistingOpenIsNotClaimedByWindowPrepublicationToken() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(29)
        owner.markEligible(for: 29)
        owner.markDidOpenTab(generation: 29)
        let token = owner.prepareForWindowPrepublication(generation: 29)

        XCTAssertTrue(
            owner.commitWindowPrepublication(
                token,
                willEmitOpen: false
            )
        )
        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: 29
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: 29))
    }

    func testSameGenerationPublisherInvalidatesPreparedWindowPrepublication() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: 31)

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 7,
            contextReadiness: .loaded
        )
        owner.markDidOpenTab(generation: 31)

        XCTAssertFalse(owner.canCommitWindowPrepublication(token))
        XCTAssertFalse(owner.rollbackWindowPrepublication(token))
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: 31))
        XCTAssertEqual(
            owner.documentBindingSnapshot()
                .openNotifiedContextBindingGeneration,
            7
        )
    }

    func testReplacementPreparationOwnsOriginalRollbackPoint() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.controllerGeneration = 3
        owner.eligibleGeneration = 3
        let first = owner.prepareForWindowPrepublication(generation: 37)
        let replacement = owner.prepareForWindowPrepublication(
            generation: 37
        )

        XCTAssertFalse(owner.canCommitWindowPrepublication(first))
        XCTAssertFalse(owner.rollbackWindowPrepublication(first))
        XCTAssertTrue(owner.rollbackWindowPrepublication(replacement))
        XCTAssertEqual(owner.controllerGeneration, 3)
        XCTAssertEqual(owner.currentEligibleGeneration(), 3)
    }

    func testNewGenerationOpenCannotBeRevokedByOldCommittedToken() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: 41)
        XCTAssertTrue(
            owner.commitWindowPrepublication(token, willEmitOpen: true)
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: 41,
                committedWindowPrepublication: token
            )
        )

        owner.prepareGeneration(43)
        owner.markEligible(for: 43)
        owner.markDidOpenTab(generation: 43)

        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: 41
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: 43))
    }

    func testCommittedTokenPageMutationCannotRestoreStaleSnapshot() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: 47)
        XCTAssertTrue(
            owner.commitWindowPrepublication(token, willEmitOpen: true)
        )
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 3,
            contextReadiness: .loaded
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: 47,
                committedWindowPrepublication: token
            )
        )

        let newerURL = URL(string: "https://newer.example/page")!
        owner.noteCommittedMainDocumentNavigation(to: newerURL)
        XCTAssertTrue(owner.recordReportedTitleIfChanged("Newer title"))

        XCTAssertTrue(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: 47
            )
        )
        XCTAssertEqual(owner.committedMainDocumentURL, newerURL)
        XCTAssertEqual(owner.documentSequence, 1)
        XCTAssertEqual(owner.lastReportedTitle, "Newer title")
        XCTAssertFalse(owner.hasAnyDidOpenTabNotification())
    }

    func testNewSameGenerationPreparationSupersedesOldCommittedRollbackRight() {
        let owner = TabExtensionPageRuntimeOwner()
        let oldToken = owner.prepareForWindowPrepublication(generation: 53)
        XCTAssertTrue(
            owner.commitWindowPrepublication(oldToken, willEmitOpen: true)
        )
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 5,
            contextReadiness: .loaded
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: 53,
                committedWindowPrepublication: oldToken
            )
        )
        let claim = owner.currentOpenPublicationClaim(generation: 53)
        let newToken = owner.prepareForWindowPrepublication(generation: 53)

        XCTAssertNotNil(claim)
        XCTAssertTrue(
            owner.finishWindowPrepublicationForDelegatedOpen(
                newToken,
                claim: claim!
            )
        )
        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                oldToken,
                openGeneration: 53
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: 53))
    }

    func testDelegatedClaimCannotCloseLaterSameGenerationOpen() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(59)
        owner.markEligible(for: 59)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 7,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: 59))
        let delegated = owner.currentOpenPublicationClaim(generation: 59)
        XCTAssertNotNil(delegated)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                delegated!,
                generation: 59
            )
        )

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 7,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: 59))
        let replacement = owner.currentOpenPublicationClaim(generation: 59)

        XCTAssertNotNil(replacement)
        XCTAssertFalse(delegated === replacement)
        XCTAssertFalse(
            owner.claimDidOpenTabNotificationForClose(
                delegated!,
                generation: 59
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: 59))
    }

    func testSupersededPreparationHandsOffToExactOrdinaryOpen() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: 61)

        owner.markEligible(for: 61)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 11,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: 61))
        let claim = owner.currentOpenPublicationClaim(generation: 61)

        XCTAssertNotNil(claim)
        XCTAssertTrue(
            owner.finishWindowPrepublicationForDelegatedOpen(
                token,
                claim: claim!
            )
        )
        XCTAssertFalse(owner.rollbackWindowPrepublication(token))
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: 61))
    }

    func testCommittedReceiptHandsOffToExactReentrantReplacementOpen() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: 67)
        XCTAssertTrue(
            owner.commitWindowPrepublication(token, willEmitOpen: true)
        )
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 13,
            contextReadiness: .loaded
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: 67,
                committedWindowPrepublication: token
            )
        )
        let original = owner.currentOpenPublicationClaim(generation: 67)
        XCTAssertNotNil(original)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                original!,
                generation: 67
            )
        )

        owner.markEligible(for: 67)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 13,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: 67))
        let replacement = owner.currentOpenPublicationClaim(generation: 67)

        XCTAssertNotNil(replacement)
        XCTAssertTrue(
            owner.finishWindowPrepublicationForDelegatedOpen(
                token,
                claim: replacement!
            )
        )
        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: 67
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: 67))
    }

    func testEligibilityAndBindingPreparationRemainRollbackCapableWithoutOpen() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.controllerGeneration = 5
        owner.eligibleGeneration = 5
        let token = owner.prepareForWindowPrepublication(generation: 71)

        // Ordinary registration reaches eligibility and document binding before
        // controller attachment. If attachment fails, no open is reserved and
        // the surrounding receipt must still be able to roll back exactly.
        owner.markEligible(for: 71)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 17,
            contextReadiness: .loaded
        )

        XCTAssertTrue(owner.canCommitWindowPrepublication(token))
        XCTAssertTrue(owner.rollbackWindowPrepublication(token))
        XCTAssertEqual(owner.controllerGeneration, 5)
        XCTAssertEqual(owner.currentEligibleGeneration(), 5)
        XCTAssertNil(owner.openNotifiedContextBindingGeneration)
        XCTAssertFalse(owner.hasAnyDidOpenTabNotification())
    }

    func testPendingHandoffTracksRepeatedExactCloseAndReopenUntilSettlement() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: 73)

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 19,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: 73))
        let first = owner.currentOpenPublicationClaim(generation: 73)
        XCTAssertNotNil(first)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                first!,
                generation: 73
            )
        )

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 19,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: 73))
        let second = owner.currentOpenPublicationClaim(generation: 73)
        XCTAssertNotNil(second)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                second!,
                generation: 73
            )
        )

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 19,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: 73))
        let third = owner.currentOpenPublicationClaim(generation: 73)

        XCTAssertNotNil(third)
        XCTAssertFalse(first === second)
        XCTAssertFalse(second === third)
        XCTAssertTrue(
            owner.finishWindowPrepublicationForDelegatedOpen(
                token,
                claim: third!
            )
        )
        XCTAssertFalse(owner.rollbackWindowPrepublication(token))
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: 73))
    }
}
