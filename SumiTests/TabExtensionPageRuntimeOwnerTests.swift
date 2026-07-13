import XCTest

@testable import Sumi

@MainActor
final class TabExtensionPageRuntimeOwnerTests: XCTestCase {
    func testPrepareGenerationResetsReportedAndOpenNotificationState() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.lastReportedURL = URL(string: "https://old.example")
        XCTAssertTrue(owner.recordReportedLoadingCompleteIfChanged(true))
        owner.lastReportedTitle = "Old"
        owner.markEligible(for: revision(3))
        owner.noteCommittedMainDocumentNavigation(to: URL(string: "https://example.com")!)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 7,
            contextReadiness: .missing
        )
        owner.markDidOpenTab(generation: revision(3))

        owner.prepareGeneration(revision(4))

        XCTAssertEqual(owner.currentPreparedGeneration(), revision(4))
        XCTAssertNil(owner.lastReportedURL)
        XCTAssertFalse(owner.hasReportedLoadingComplete)
        XCTAssertNil(owner.lastReportedTitle)
        XCTAssertNil(owner.currentOpenNotificationGeneration())
        XCTAssertNil(owner.currentEligibleGeneration())
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
        owner.markDidOpenTab(generation: revision(5))

        XCTAssertEqual(owner.openNotifiedDocumentSequence, owner.documentSequence)
        XCTAssertEqual(owner.openNotifiedContextBindingGeneration, 11)
        XCTAssertEqual(owner.openNotifiedContextReadiness, .loaded)
        XCTAssertEqual(
            owner.currentOpenNotificationGeneration(),
            revision(5)
        )
        XCTAssertTrue(owner.didNotifyOpenToExtensions)
        XCTAssertTrue(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: revision(5)
        ))
        XCTAssertFalse(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: revision(4)
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
        owner.markDidOpenTab(generation: revision(7))

        owner.didNotifyOpenToExtensions = true

        XCTAssertEqual(
            owner.currentOpenNotificationGeneration(),
            revision(7)
        )

        owner.didNotifyOpenToExtensions = false

        XCTAssertNil(owner.currentOpenNotificationGeneration())
        XCTAssertFalse(owner.didNotifyOpenToExtensions)
    }

    func testEligibilityIsOwnedByRuntimeGeneration() {
        let owner = TabExtensionPageRuntimeOwner()

        XCTAssertFalse(owner.isEligible(for: revision(2)))

        owner.markEligible(for: revision(2))

        XCTAssertTrue(owner.isEligible(for: revision(2)))
        XCTAssertFalse(owner.isEligible(for: revision(3)))
    }

    func testOpenPublicationRequiresExactSettlement() throws {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(revision(13))
        owner.markEligible(for: revision(13))
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(13)))
        let claim = try XCTUnwrap(
            owner.currentOpenPublicationClaim(generation: revision(13))
        )

        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(13)))
        XCTAssertFalse(owner.hasSettledDidOpenTabNotification(for: revision(13)))
        XCTAssertTrue(
            owner.settleDidOpenTabNotification(claim, generation: revision(13))
        )
        XCTAssertTrue(owner.hasSettledDidOpenTabNotification(for: revision(13)))
    }

    func testStaleOpenSettlementCannotSettleReplacement() throws {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(revision(17))
        owner.markEligible(for: revision(17))
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(17)))
        let staleClaim = try XCTUnwrap(
            owner.currentOpenPublicationClaim(generation: revision(17))
        )
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                staleClaim,
                generation: revision(17)
            )
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(17)))
        let replacementClaim = try XCTUnwrap(
            owner.currentOpenPublicationClaim(generation: revision(17))
        )

        XCTAssertFalse(
            owner.settleDidOpenTabNotification(staleClaim, generation: revision(17))
        )
        XCTAssertFalse(owner.hasSettledDidOpenTabNotification(for: revision(17)))
        XCTAssertTrue(
            owner.settleDidOpenTabNotification(
                replacementClaim,
                generation: revision(17)
            )
        )
        XCTAssertTrue(owner.hasSettledDidOpenTabNotification(for: revision(17)))
    }

    func testRetiredOpenAdmissionCannotPublishAnotherGeneration() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(revision(19))
        owner.markEligible(for: revision(19))
        owner.retireFutureOpenPublications()

        XCTAssertFalse(owner.canPublishFutureOpenNotification())
        XCTAssertFalse(owner.markDidOpenTab(generation: revision(19)))
    }

    func testWindowPrepublicationRollbackRestoresSettledOpenClaim() throws {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(revision(23))
        owner.markEligible(for: revision(23))
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(23)))
        let claim = try XCTUnwrap(
            owner.currentOpenPublicationClaim(generation: revision(23))
        )
        XCTAssertTrue(
            owner.settleDidOpenTabNotification(claim, generation: revision(23))
        )

        let token = owner.prepareForWindowPrepublication(generation: revision(29))
        XCTAssertFalse(owner.hasSettledDidOpenTabNotification(for: revision(29)))
        XCTAssertTrue(owner.rollbackWindowPrepublication(token))

        XCTAssertTrue(owner.hasSettledDidOpenTabNotification(for: revision(23)))
        XCTAssertIdentical(
            owner.currentOpenPublicationClaim(generation: revision(23)),
            claim
        )
    }

    func testCurrentDocumentOpenNotificationInvalidatesWhenDocumentChanges() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.noteCommittedMainDocumentNavigation(to: URL(string: "https://example.com/one")!)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 1,
            contextReadiness: .loaded
        )
        owner.markDidOpenTab(generation: revision(9))

        XCTAssertTrue(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: revision(9)
        ))

        owner.invalidatePageForWebViewReplacement()

        XCTAssertFalse(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: revision(9)
        ))
        XCTAssertEqual(owner.committedMainDocumentURL, URL(string: "https://example.com/one")!)
    }

    func testCommittedWindowPrepublicationRevokeRestoresExactSnapshot() throws {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: revision(17))
        XCTAssertTrue(
            owner.commitWindowPrepublication(
                token,
                willEmitOpen: true
            )
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: revision(17),
                committedWindowPrepublication: token
            )
        )
        let claim = try XCTUnwrap(
            owner.currentOpenPublicationClaim(generation: revision(17))
        )
        XCTAssertTrue(
            owner.settleDidOpenTabNotification(claim, generation: revision(17))
        )
        XCTAssertTrue(owner.hasSettledDidOpenTabNotification(for: revision(17)))

        XCTAssertTrue(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: revision(17)
            )
        )
        XCTAssertNil(owner.currentPreparedGeneration())
        XCTAssertNil(owner.currentEligibleGeneration())
        XCTAssertNil(owner.currentOpenNotificationGeneration())
        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: revision(17)
            )
        )
    }

    func testNewPublisherMakesOldWindowPrepublicationTokenStale() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: revision(23))
        XCTAssertTrue(
            owner.commitWindowPrepublication(
                token,
                willEmitOpen: true
            )
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: revision(23),
                committedWindowPrepublication: token
            )
        )

        let originalClaim = owner.currentOpenPublicationClaim(generation: revision(23))
        XCTAssertNotNil(originalClaim)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                originalClaim!,
                generation: revision(23)
            )
        )
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 1,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(23)))

        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: revision(23)
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(23)))
    }

    func testPreexistingOpenIsNotClaimedByWindowPrepublicationToken() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(revision(29))
        owner.markEligible(for: revision(29))
        owner.markDidOpenTab(generation: revision(29))
        let token = owner.prepareForWindowPrepublication(generation: revision(29))

        XCTAssertTrue(
            owner.commitWindowPrepublication(
                token,
                willEmitOpen: false
            )
        )
        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: revision(29)
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(29)))
    }

    func testSameGenerationPublisherInvalidatesPreparedWindowPrepublication() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: revision(31))

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 7,
            contextReadiness: .loaded
        )
        owner.markDidOpenTab(generation: revision(31))

        XCTAssertFalse(owner.canCommitWindowPrepublication(token))
        XCTAssertFalse(owner.rollbackWindowPrepublication(token))
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(31)))
        XCTAssertEqual(
            owner.documentBindingSnapshot()
                .openNotifiedContextBindingGeneration,
            7
        )
    }

    func testReplacementPreparationOwnsOriginalRollbackPoint() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(revision(3))
        owner.markEligible(for: revision(3))
        let first = owner.prepareForWindowPrepublication(generation: revision(37))
        let replacement = owner.prepareForWindowPrepublication(
            generation: revision(37)
        )

        XCTAssertFalse(owner.canCommitWindowPrepublication(first))
        XCTAssertFalse(owner.rollbackWindowPrepublication(first))
        XCTAssertTrue(owner.rollbackWindowPrepublication(replacement))
        XCTAssertEqual(owner.currentPreparedGeneration(), revision(3))
        XCTAssertEqual(owner.currentEligibleGeneration(), revision(3))
    }

    func testNewGenerationOpenCannotBeRevokedByOldCommittedToken() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: revision(41))
        XCTAssertTrue(
            owner.commitWindowPrepublication(token, willEmitOpen: true)
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: revision(41),
                committedWindowPrepublication: token
            )
        )

        owner.prepareGeneration(revision(43))
        owner.markEligible(for: revision(43))
        owner.markDidOpenTab(generation: revision(43))

        XCTAssertFalse(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: revision(41)
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(43)))
    }

    func testCommittedTokenPageMutationCannotRestoreStaleSnapshot() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: revision(47))
        XCTAssertTrue(
            owner.commitWindowPrepublication(token, willEmitOpen: true)
        )
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 3,
            contextReadiness: .loaded
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: revision(47),
                committedWindowPrepublication: token
            )
        )

        let newerURL = URL(string: "https://newer.example/page")!
        owner.noteCommittedMainDocumentNavigation(to: newerURL)
        XCTAssertTrue(owner.recordReportedTitleIfChanged("Newer title"))

        XCTAssertTrue(
            owner.revokeCommittedWindowPrepublication(
                token,
                openGeneration: revision(47)
            )
        )
        XCTAssertEqual(owner.committedMainDocumentURL, newerURL)
        XCTAssertEqual(owner.documentSequence, 1)
        XCTAssertEqual(owner.lastReportedTitle, "Newer title")
        XCTAssertFalse(owner.hasAnyDidOpenTabNotification())
    }

    func testNewSameGenerationPreparationSupersedesOldCommittedRollbackRight() {
        let owner = TabExtensionPageRuntimeOwner()
        let oldToken = owner.prepareForWindowPrepublication(generation: revision(53))
        XCTAssertTrue(
            owner.commitWindowPrepublication(oldToken, willEmitOpen: true)
        )
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 5,
            contextReadiness: .loaded
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: revision(53),
                committedWindowPrepublication: oldToken
            )
        )
        let claim = owner.currentOpenPublicationClaim(generation: revision(53))
        let newToken = owner.prepareForWindowPrepublication(generation: revision(53))

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
                openGeneration: revision(53)
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(53)))
    }

    func testDelegatedClaimCannotCloseLaterSameGenerationOpen() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(revision(59))
        owner.markEligible(for: revision(59))
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 7,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(59)))
        let delegated = owner.currentOpenPublicationClaim(generation: revision(59))
        XCTAssertNotNil(delegated)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                delegated!,
                generation: revision(59)
            )
        )

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 7,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(59)))
        let replacement = owner.currentOpenPublicationClaim(generation: revision(59))

        XCTAssertNotNil(replacement)
        XCTAssertFalse(delegated === replacement)
        XCTAssertFalse(
            owner.claimDidOpenTabNotificationForClose(
                delegated!,
                generation: revision(59)
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(59)))
    }

    func testSupersededPreparationHandsOffToExactOrdinaryOpen() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: revision(61))

        owner.markEligible(for: revision(61))
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 11,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(61)))
        let claim = owner.currentOpenPublicationClaim(generation: revision(61))

        XCTAssertNotNil(claim)
        XCTAssertTrue(
            owner.finishWindowPrepublicationForDelegatedOpen(
                token,
                claim: claim!
            )
        )
        XCTAssertFalse(owner.rollbackWindowPrepublication(token))
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(61)))
    }

    func testCommittedReceiptHandsOffToExactReentrantReplacementOpen() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: revision(67))
        XCTAssertTrue(
            owner.commitWindowPrepublication(token, willEmitOpen: true)
        )
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 13,
            contextReadiness: .loaded
        )
        XCTAssertTrue(
            owner.markDidOpenTab(
                generation: revision(67),
                committedWindowPrepublication: token
            )
        )
        let original = owner.currentOpenPublicationClaim(generation: revision(67))
        XCTAssertNotNil(original)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                original!,
                generation: revision(67)
            )
        )

        owner.markEligible(for: revision(67))
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 13,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(67)))
        let replacement = owner.currentOpenPublicationClaim(generation: revision(67))

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
                openGeneration: revision(67)
            )
        )
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(67)))
    }

    func testEligibilityAndBindingPreparationRemainRollbackCapableWithoutOpen() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.prepareGeneration(revision(5))
        owner.markEligible(for: revision(5))
        let token = owner.prepareForWindowPrepublication(generation: revision(71))

        // Ordinary registration reaches eligibility and document binding before
        // controller attachment. If attachment fails, no open is reserved and
        // the surrounding receipt must still be able to roll back exactly.
        owner.markEligible(for: revision(71))
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 17,
            contextReadiness: .loaded
        )

        XCTAssertTrue(owner.canCommitWindowPrepublication(token))
        XCTAssertTrue(owner.rollbackWindowPrepublication(token))
        XCTAssertEqual(owner.currentPreparedGeneration(), revision(5))
        XCTAssertEqual(owner.currentEligibleGeneration(), revision(5))
        XCTAssertNil(owner.openNotifiedContextBindingGeneration)
        XCTAssertFalse(owner.hasAnyDidOpenTabNotification())
    }

    func testPendingHandoffTracksRepeatedExactCloseAndReopenUntilSettlement() {
        let owner = TabExtensionPageRuntimeOwner()
        let token = owner.prepareForWindowPrepublication(generation: revision(73))

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 19,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(73)))
        let first = owner.currentOpenPublicationClaim(generation: revision(73))
        XCTAssertNotNil(first)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                first!,
                generation: revision(73)
            )
        )

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 19,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(73)))
        let second = owner.currentOpenPublicationClaim(generation: revision(73))
        XCTAssertNotNil(second)
        XCTAssertTrue(
            owner.claimDidOpenTabNotificationForClose(
                second!,
                generation: revision(73)
            )
        )

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 19,
            contextReadiness: .loaded
        )
        XCTAssertTrue(owner.markDidOpenTab(generation: revision(73)))
        let third = owner.currentOpenPublicationClaim(generation: revision(73))

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
        XCTAssertTrue(owner.hasDidOpenTabNotification(for: revision(73)))
    }

    private func revision(_ generation: UInt64)
        -> ExtensionTabPublicationRevision {
        ExtensionTabPublicationRevision(generation: generation)
    }
}
