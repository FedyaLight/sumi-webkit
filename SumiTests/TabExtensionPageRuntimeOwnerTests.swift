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
}
