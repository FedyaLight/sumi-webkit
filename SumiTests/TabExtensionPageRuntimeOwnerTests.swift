import XCTest

@testable import Sumi

@MainActor
final class TabExtensionPageRuntimeOwnerTests: XCTestCase {
    func testPrepareGenerationResetsReportedAndOpenNotificationState() {
        let owner = TabExtensionPageRuntimeOwner()
        owner.lastReportedURL = URL(string: "https://old.example")
        owner.lastReportedLoadingComplete = true
        owner.lastReportedTitle = "Old"
        owner.markEligible(for: 3)
        owner.noteCommittedMainDocumentNavigation(to: URL(string: "https://example.com")!)
        owner.noteOpenNotification(
            extensionContextBindingGeneration: 7,
            loadedContexts: false
        )
        owner.markDidOpenTab(generation: 3)

        owner.prepareGeneration(4)

        XCTAssertEqual(owner.controllerGeneration, 4)
        XCTAssertNil(owner.lastReportedURL)
        XCTAssertNil(owner.lastReportedLoadingComplete)
        XCTAssertNil(owner.lastReportedTitle)
        XCTAssertEqual(owner.lastOpenNotificationGeneration, 0)
        XCTAssertEqual(owner.eligibleGeneration, 0)
        XCTAssertNil(owner.openNotifiedDocumentSequence)
        XCTAssertNil(owner.openNotifiedExtensionContextBindingGeneration)
        XCTAssertNil(owner.openNotifiedWithLoadedContexts)
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
            loadedContexts: true
        )
        owner.markDidOpenTab(generation: 5)

        XCTAssertEqual(owner.openNotifiedDocumentSequence, owner.documentSequence)
        XCTAssertEqual(owner.openNotifiedExtensionContextBindingGeneration, 11)
        XCTAssertEqual(owner.openNotifiedWithLoadedContexts, true)
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
            loadedContexts: false
        )

        let snapshot = owner.documentBindingSnapshot()
        XCTAssertEqual(snapshot.documentSequence, 1)
        XCTAssertEqual(snapshot.committedMainDocumentURL, url)
        XCTAssertEqual(snapshot.openNotifiedDocumentSequence, 1)
        XCTAssertEqual(snapshot.openNotifiedExtensionContextBindingGeneration, 11)
        XCTAssertEqual(snapshot.openNotifiedWithLoadedContexts, false)
        XCTAssertEqual(owner.committedMainDocumentURLForCurrentPage(), url)
        XCTAssertTrue(owner.hasCommittedDocumentBinding())
        XCTAssertTrue(owner.hasDocumentBindingForLifecycleRebind())
        XCTAssertFalse(owner.shouldSkipPreCommitRebindForInitialDocument())
    }

    func testInitialDocumentOpenNotificationCanSkipPreCommitRebind() {
        let owner = TabExtensionPageRuntimeOwner()

        owner.noteOpenNotification(
            extensionContextBindingGeneration: 11,
            loadedContexts: true
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
            loadedContexts: true
        )

        owner.resetDocumentBindingForContentScriptRebind()

        XCTAssertEqual(owner.documentSequence, 0)
        XCTAssertNil(owner.committedMainDocumentURL)
        XCTAssertNil(owner.openNotifiedDocumentSequence)
        XCTAssertNil(owner.openNotifiedExtensionContextBindingGeneration)
        XCTAssertNil(owner.openNotifiedWithLoadedContexts)
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
            loadedContexts: true
        )
        owner.markDidOpenTab(generation: 9)

        XCTAssertTrue(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: 9
        ))

        owner.invalidateCurrentPageForWebViewReplacement()

        XCTAssertFalse(owner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: 9
        ))
        XCTAssertEqual(owner.committedMainDocumentURL, URL(string: "https://example.com/one")!)
    }
}
