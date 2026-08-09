import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebsiteDataCleanupTransactionTests: XCTestCase {
    func testSynchronousCleanupStartIsSuppressedBeforeBlankLoaderReturns()
        async throws {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        var wasSuppressedDuringLoad = false
        var coverWasVisibleDuringLoad = false
        var didDelete = false

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { webView in
                coverWasVisibleDuringLoad =
                    fixture.tab.websiteDataMutationPresentation != nil
                let lifetime = NSObject()
                let navigationID = ObjectIdentifier(lifetime)
                ownerReference.owner?.navigationWillStart(
                    on: webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    targetURL: URL(string: "about:blank")!,
                    semanticRevision: nil
                )
                wasSuppressedDuringLoad = ownerReference.owner?
                    .isSuppressingNavigation(
                        on: webView,
                        navigationID: navigationID,
                        navigationLifetime: lifetime
                    ) == true
                ownerReference.owner?.navigationDidTerminate(
                    on: webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    succeeded: true
                )
                return .init(id: navigationID, lifetime: lifetime)
            },
            restoreTab: { _, targetURL in
                let lifetime = NSObject()
                let navigationID = ObjectIdentifier(lifetime)
                ownerReference.owner?.navigationWillStart(
                    on: fixture.webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    targetURL: targetURL,
                    semanticRevision: 1
                )
                ownerReference.owner?.navigationDidTerminate(
                    on: fixture.webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    succeeded: true
                )
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            },
            blankAttemptTimeout: .milliseconds(10)
        )
        ownerReference.owner = owner

        let result = await owner.performDestructiveDataCleanup(
            profileIDs: [fixture.profileID]
        ) {
            didDelete = true
        }

        XCTAssertTrue(wasSuppressedDuringLoad)
        XCTAssertTrue(coverWasVisibleDuringLoad)
        XCTAssertTrue(result)
        XCTAssertTrue(didDelete)
        XCTAssertNil(fixture.tab.websiteDataMutationPresentation)
    }

    func testDeletionWaitsForExactBlankBarrierThenTransfersAtRestoreBinding()
        async throws {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        let blankSubmitted = CleanupTestSignal()
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?
        var events: [String] = []
        var canonicalRuntimeTabReadCount = 0

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: {
                canonicalRuntimeTabReadCount += 1
                return [fixture.tab]
            },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in
                events.append("unprotected")
                return true
            },
            loadBlankNavigation: { _ in
                events.append("blank-submitted")
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                events.append("restore-submitted:\(targetURL.absoluteString)")
                let lifetime = NSObject()
                let navigationID = ObjectIdentifier(lifetime)
                ownerReference.owner?.navigationWillStart(
                    on: fixture.webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    targetURL: targetURL,
                    semanticRevision: 1
                )
                ownerReference.owner?.navigationDidTerminate(
                    on: fixture.webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    succeeded: true
                )
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            },
            blankAttemptTimeout: .milliseconds(10)
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                events.append("deleted")
            }
        }
        await blankSubmitted.wait()
        XCTAssertFalse(events.contains("deleted"))

        let identity = try XCTUnwrap(blankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertTrue(didComplete)
        XCTAssertGreaterThan(canonicalRuntimeTabReadCount, 0)
        XCTAssertEqual(
            events,
            [
                "unprotected",
                "blank-submitted",
                "deleted",
                "restore-submitted:\(fixture.targetURL.absoluteString)",
            ]
        )
    }

    func testProtectedWebViewIsAwaitedInsteadOfSkipped() async throws {
        let fixture = makeFixture()
        let permissionRequested = CleanupTestSignal()
        let blankSubmitted = CleanupTestSignal()
        let deletionCompleted = CleanupTestSignal()
        var permissionContinuation: CheckedContinuation<Bool, Never>?
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?
        var didDelete = false
        let ownerReference = CleanupOwnerReference()

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in
                await withCheckedContinuation {
                    permissionContinuation = $0
                    permissionRequested.signal()
                }
            },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                let lifetime = NSObject()
                ownerReference.owner?.navigationWillStart(
                    on: fixture.webView,
                    navigationID: ObjectIdentifier(lifetime),
                    navigationLifetime: lifetime,
                    targetURL: targetURL,
                    semanticRevision: 1
                )
                ownerReference.owner?.navigationDidTerminate(
                    on: fixture.webView,
                    navigationID: ObjectIdentifier(lifetime),
                    navigationLifetime: lifetime,
                    succeeded: true
                )
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
                deletionCompleted.signal()
            }
        }
        await permissionRequested.wait()
        XCTAssertNil(blankIdentity)
        XCTAssertFalse(didDelete)

        permissionContinuation?.resume(returning: true)
        permissionContinuation = nil
        await blankSubmitted.wait()
        let identity = try XCTUnwrap(blankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )
        await deletionCompleted.wait()

        let didComplete = await transaction.value
        XCTAssertTrue(didComplete)
    }

    func testSameIdentifierWithDifferentLifetimeCannotCrossBlankBarrier() async throws {
        let fixture = makeFixture()
        let blankSubmitted = CleanupTestSignal()
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?
        var didDelete = false
        let ownerReference = CleanupOwnerReference()

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                let lifetime = NSObject()
                let navigationID = ObjectIdentifier(lifetime)
                ownerReference.owner?.navigationWillStart(
                    on: fixture.webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    targetURL: targetURL,
                    semanticRevision: 1
                )
                ownerReference.owner?.navigationDidTerminate(
                    on: fixture.webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    succeeded: true
                )
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await blankSubmitted.wait()
        let identity = try XCTUnwrap(blankIdentity)

        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: NSObject(),
            succeeded: true
        )
        XCTAssertFalse(didDelete)

        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )
        let didComplete = await transaction.value
        XCTAssertTrue(didComplete)
        XCTAssertTrue(didDelete)
    }

    func testSecondParticipantBlankFailureAbortsDeletionAndRestoresOwnedParticipants() async throws {
        let fixture = makeFixture()
        let secondWebView = WKWebView()
        fixture.tab.parkExistingWebView(secondWebView)
        let ownerReference = CleanupOwnerReference()
        let firstBlankSubmitted = CleanupTestSignal()
        var firstBlankIdentity: WebsiteDataCleanupTransaction
            .CleanupNavigationIdentity?
        var blankSubmissionCount = 0
        var restoreSubmissionCount = 0
        var didDelete = false

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView, secondWebView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { webView in
                blankSubmissionCount += 1
                guard webView === fixture.webView else { return nil }
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                firstBlankIdentity = identity
                firstBlankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                restoreSubmissionCount += 1
                for webView in [fixture.webView, secondWebView] {
                    let lifetime = NSObject()
                    let navigationID = ObjectIdentifier(lifetime)
                    ownerReference.owner?.navigationWillStart(
                        on: webView,
                        navigationID: navigationID,
                        navigationLifetime: lifetime,
                        targetURL: targetURL,
                        semanticRevision: 1
                    )
                    ownerReference.owner?.navigationDidTerminate(
                        on: webView,
                        navigationID: navigationID,
                        navigationLifetime: lifetime,
                        succeeded: true
                    )
                }
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView, secondWebView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await firstBlankSubmitted.wait()
        let identity = try XCTUnwrap(firstBlankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertFalse(didComplete)
        XCTAssertFalse(didDelete)
        XCTAssertEqual(blankSubmissionCount, 2)
        XCTAssertEqual(restoreSubmissionCount, 1)
    }

    func testMultipleReplicasUsePerWebViewBlankBarriersAndOneTabRestore() async throws {
        let fixture = makeFixture()
        let secondWebView = WKWebView()
        fixture.tab.parkExistingWebView(secondWebView)
        let webViews = [fixture.webView, secondWebView]
        let ownerReference = CleanupOwnerReference()
        let firstBlankSubmitted = CleanupTestSignal()
        let secondBlankSubmitted = CleanupTestSignal()
        var blankIdentities: [
            ObjectIdentifier: WebsiteDataCleanupTransaction.CleanupNavigationIdentity
        ] = [:]
        var mutationPermissionWebViewIDs: [ObjectIdentifier] = []
        var restoreSubmissionCount = 0
        var didDelete = false

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in webViews },
            waitForMutationPermission: { webView in
                mutationPermissionWebViewIDs.append(ObjectIdentifier(webView))
                return true
            },
            loadBlankNavigation: { webView in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentities[ObjectIdentifier(webView)] = identity
                if webView === fixture.webView {
                    firstBlankSubmitted.signal()
                } else if webView === secondWebView {
                    secondBlankSubmitted.signal()
                }
                return identity
            },
            restoreTab: { _, targetURL in
                restoreSubmissionCount += 1
                for webView in webViews {
                    let lifetime = NSObject()
                    let navigationID = ObjectIdentifier(lifetime)
                    ownerReference.owner?.navigationWillStart(
                        on: webView,
                        navigationID: navigationID,
                        navigationLifetime: lifetime,
                        targetURL: targetURL,
                        semanticRevision: 1
                    )
                    ownerReference.owner?.navigationDidTerminate(
                        on: webView,
                        navigationID: navigationID,
                        navigationLifetime: lifetime,
                        succeeded: true
                    )
                }
                return .init(
                    outcome: .accepted(
                        on: webViews,
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }

        await firstBlankSubmitted.wait()
        let firstIdentity = try XCTUnwrap(
            blankIdentities[ObjectIdentifier(fixture.webView)]
        )
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: firstIdentity.id,
            navigationLifetime: firstIdentity.lifetime,
            succeeded: true
        )
        await secondBlankSubmitted.wait()
        XCTAssertFalse(didDelete)
        let secondIdentity = try XCTUnwrap(
            blankIdentities[ObjectIdentifier(secondWebView)]
        )
        owner.navigationDidTerminate(
            on: secondWebView,
            navigationID: secondIdentity.id,
            navigationLifetime: secondIdentity.lifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertTrue(didComplete)
        XCTAssertTrue(didDelete)
        XCTAssertEqual(restoreSubmissionCount, 1)
        XCTAssertEqual(
            mutationPermissionWebViewIDs,
            webViews.map(ObjectIdentifier.init)
        )
    }

    func testPostDeletionRestoreFailureIsFiniteAndExplicit() async throws {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        let blankSubmitted = CleanupTestSignal()
        let restoreSubmitted = CleanupTestSignal()
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?
        var restoreSubmissionCount = 0
        var didDelete = false

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                restoreSubmissionCount += 1
                restoreSubmitted.signal()
                return .init(outcome: .testFailure, semanticRevision: nil)
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await blankSubmitted.wait()
        let identity = try XCTUnwrap(blankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )

        await restoreSubmitted.wait()
        let didComplete = await transaction.value
        XCTAssertFalse(didComplete)
        XCTAssertTrue(didDelete)
        XCTAssertEqual(restoreSubmissionCount, 1)
        XCTAssertTrue(
            fixture.tab.webContentRecoveryMarkers
                .recoveryState(on: fixture.webView)?.isFailure == true
        )
    }

    func testProcessTerminationDuringBlankAbortsDeletionAndRestoresOwnedParticipant() async throws {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        let blankSubmitted = CleanupTestSignal()
        var restoreSubmissionCount = 0
        var didDelete = false

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                restoreSubmissionCount += 1
                let lifetime = NSObject()
                let navigationID = ObjectIdentifier(lifetime)
                ownerReference.owner?.navigationWillStart(
                    on: fixture.webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    targetURL: targetURL,
                    semanticRevision: 1
                )
                ownerReference.owner?.navigationDidTerminate(
                    on: fixture.webView,
                    navigationID: navigationID,
                    navigationLifetime: lifetime,
                    succeeded: true
                )
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await blankSubmitted.wait()

        XCTAssertTrue(owner.webContentProcessDidTerminate(on: fixture.webView))

        let didComplete = await transaction.value
        XCTAssertFalse(didComplete)
        XCTAssertFalse(didDelete)
        XCTAssertEqual(restoreSubmissionCount, 1)
    }

    func testProcessTerminationAfterDeletionTerminatesRestoreAfterOneAttempt()
        async throws {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        let blankSubmitted = CleanupTestSignal()
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?
        var restoreSubmissionCount = 0
        var didDelete = false

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                restoreSubmissionCount += 1
                XCTAssertTrue(
                    ownerReference.owner?.webContentProcessDidTerminate(
                        on: fixture.webView
                    ) == true
                )
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await blankSubmitted.wait()
        let identity = try XCTUnwrap(blankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertFalse(didComplete)
        XCTAssertTrue(didDelete)
        XCTAssertEqual(restoreSubmissionCount, 1)
        XCTAssertTrue(
            fixture.tab.webContentRecoveryMarkers
                .recoveryState(on: fixture.webView)?.isFailure == true
        )
    }

    func testDepartureAfterDeletionTerminatesRestoreWithoutRetry()
        async throws {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        let blankSubmitted = CleanupTestSignal()
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?
        var liveWebViews = [fixture.webView]
        var restoreSubmissionCount = 0

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in liveWebViews },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, _ in
                restoreSubmissionCount += 1
                ownerReference.owner?.webViewDidLeaveRuntime(fixture.webView)
                liveWebViews = []
                return .init(outcome: .testFailure, semanticRevision: nil)
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {}
        }
        await blankSubmitted.wait()
        let identity = try XCTUnwrap(blankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertTrue(didComplete)
        XCTAssertEqual(restoreSubmissionCount, 1)
    }

    func testBlankDeadlineAbortsDeletionAndCompensatesOnce() async throws {
        let fixture = makeFixture()
        let blankSubmitted = CleanupTestSignal()
        var restoreSubmissionCount = 0
        var didDelete = false

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                blankSubmitted.signal()
                return .init(
                    id: ObjectIdentifier(lifetime),
                    lifetime: lifetime
                )
            },
            restoreTab: { _, targetURL in
                restoreSubmissionCount += 1
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            },
            blankAttemptTimeout: .milliseconds(10)
        )

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await blankSubmitted.wait()

        let didComplete = await transaction.value
        XCTAssertFalse(didComplete)
        XCTAssertFalse(didDelete)
        XCTAssertEqual(restoreSubmissionCount, 1)
    }

    func testNavigationAfterReplicaBlankInvalidatesDeletionBarrierAndCompensates() async throws {
        let fixture = makeFixture()
        let secondWebView = WKWebView()
        fixture.tab.parkExistingWebView(secondWebView)
        let webViews = [fixture.webView, secondWebView]
        let ownerReference = CleanupOwnerReference()
        let firstBlankSubmitted = CleanupTestSignal()
        let secondBlankSubmitted = CleanupTestSignal()
        var blankIdentities: [
            ObjectIdentifier: WebsiteDataCleanupTransaction.CleanupNavigationIdentity
        ] = [:]
        var didDelete = false
        var restoreCount = 0

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in webViews },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { webView in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentities[ObjectIdentifier(webView)] = identity
                if webView === fixture.webView {
                    firstBlankSubmitted.signal()
                } else if webView === secondWebView {
                    secondBlankSubmitted.signal()
                }
                return identity
            },
            restoreTab: { _, targetURL in
                restoreCount += 1
                for webView in webViews {
                    let lifetime = NSObject()
                    ownerReference.owner?.navigationWillStart(
                        on: webView,
                        navigationID: ObjectIdentifier(lifetime),
                        navigationLifetime: lifetime,
                        targetURL: targetURL,
                        semanticRevision: 1
                    )
                    ownerReference.owner?.navigationDidTerminate(
                        on: webView,
                        navigationID: ObjectIdentifier(lifetime),
                        navigationLifetime: lifetime,
                        succeeded: true
                    )
                }
                return .init(
                    outcome: .accepted(
                        on: webViews,
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await firstBlankSubmitted.wait()
        let firstBlank = try XCTUnwrap(
            blankIdentities[ObjectIdentifier(fixture.webView)]
        )
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: firstBlank.id,
            navigationLifetime: firstBlank.lifetime,
            succeeded: true
        )
        await secondBlankSubmitted.wait()

        let foreignLifetime = NSObject()
        owner.navigationWillStart(
            on: fixture.webView,
            navigationID: ObjectIdentifier(foreignLifetime),
            navigationLifetime: foreignLifetime,
            targetURL: URL(string: "https://cleanup.example/new-user-intent")!,
            semanticRevision: 99
        )
        let secondBlank = try XCTUnwrap(
            blankIdentities[ObjectIdentifier(secondWebView)]
        )
        owner.navigationDidTerminate(
            on: secondWebView,
            navigationID: secondBlank.id,
            navigationLifetime: secondBlank.lifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertFalse(didComplete)
        XCTAssertFalse(didDelete)
        XCTAssertEqual(restoreCount, 1)
    }

    func testReplicaAdmittedDuringFirstBarrierIsDiscoveredBeforeDeletion() async throws {
        let fixture = makeFixture()
        let secondWebView = WKWebView()
        var webViews = [fixture.webView]
        var residenceGeneration: UInt64 = 1
        let ownerReference = CleanupOwnerReference()
        let firstBlankSubmitted = CleanupTestSignal()
        let secondBlankSubmitted = CleanupTestSignal()
        var blankIdentities: [
            ObjectIdentifier: WebsiteDataCleanupTransaction.CleanupNavigationIdentity
        ] = [:]
        var didDelete = false

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in webViews },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { webView in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentities[ObjectIdentifier(webView)] = identity
                if webView === fixture.webView {
                    firstBlankSubmitted.signal()
                } else if webView === secondWebView {
                    secondBlankSubmitted.signal()
                }
                return identity
            },
            restoreTab: { _, targetURL in
                for webView in webViews {
                    let lifetime = NSObject()
                    ownerReference.owner?.navigationWillStart(
                        on: webView,
                        navigationID: ObjectIdentifier(lifetime),
                        navigationLifetime: lifetime,
                        targetURL: targetURL,
                        semanticRevision: 1
                    )
                    ownerReference.owner?.navigationDidTerminate(
                        on: webView,
                        navigationID: ObjectIdentifier(lifetime),
                        navigationLifetime: lifetime,
                        succeeded: true
                    )
                }
                return .init(
                    outcome: .accepted(
                        on: webViews,
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            },
            runtimeMutationGeneration: { residenceGeneration }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await firstBlankSubmitted.wait()
        let firstBlank = try XCTUnwrap(
            blankIdentities[ObjectIdentifier(fixture.webView)]
        )
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: firstBlank.id,
            navigationLifetime: firstBlank.lifetime,
            succeeded: true
        )
        fixture.tab.parkExistingWebView(secondWebView)
        webViews.append(secondWebView)
        residenceGeneration &+= 1

        await secondBlankSubmitted.wait()
        XCTAssertFalse(didDelete)
        let secondBlank = try XCTUnwrap(
            blankIdentities[ObjectIdentifier(secondWebView)]
        )
        owner.navigationDidTerminate(
            on: secondWebView,
            navigationID: secondBlank.id,
            navigationLifetime: secondBlank.lifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertTrue(didComplete)
        XCTAssertTrue(didDelete)
    }

    func testCallerCancellationAfterFirstBlankCannotDropCompensation() async throws {
        let fixture = makeFixture()
        let secondWebView = WKWebView()
        fixture.tab.parkExistingWebView(secondWebView)
        let webViews = [fixture.webView, secondWebView]
        let ownerReference = CleanupOwnerReference()
        let firstBlankSubmitted = CleanupTestSignal()
        let secondBlankSubmitted = CleanupTestSignal()
        var blankIdentities: [
            ObjectIdentifier: WebsiteDataCleanupTransaction.CleanupNavigationIdentity
        ] = [:]
        var didDelete = false
        var restoreCount = 0

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in webViews },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { webView in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentities[ObjectIdentifier(webView)] = identity
                if webView === fixture.webView {
                    firstBlankSubmitted.signal()
                } else if webView === secondWebView {
                    secondBlankSubmitted.signal()
                }
                return identity
            },
            restoreTab: { _, targetURL in
                restoreCount += 1
                for webView in webViews {
                    let lifetime = NSObject()
                    ownerReference.owner?.navigationWillStart(
                        on: webView,
                        navigationID: ObjectIdentifier(lifetime),
                        navigationLifetime: lifetime,
                        targetURL: targetURL,
                        semanticRevision: 1
                    )
                    ownerReference.owner?.navigationDidTerminate(
                        on: webView,
                        navigationID: ObjectIdentifier(lifetime),
                        navigationLifetime: lifetime,
                        succeeded: true
                    )
                }
                return .init(
                    outcome: .accepted(
                        on: webViews,
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            },
            blankAttemptTimeout: .milliseconds(10)
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await firstBlankSubmitted.wait()
        let firstBlank = try XCTUnwrap(
            blankIdentities[ObjectIdentifier(fixture.webView)]
        )
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: firstBlank.id,
            navigationLifetime: firstBlank.lifetime,
            succeeded: true
        )
        await secondBlankSubmitted.wait()
        transaction.cancel()

        let didComplete = await transaction.value
        XCTAssertFalse(didComplete)
        XCTAssertFalse(didDelete)
        XCTAssertEqual(restoreCount, 1)
    }

    func testCancellationDuringBlankSubmissionCompensatesOnce() async {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        var transaction: Task<Bool, Never>?
        var didDelete = false
        var restoreCount = 0

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                transaction?.cancel()
                return .init(
                    id: ObjectIdentifier(lifetime),
                    lifetime: lifetime
                )
            },
            restoreTab: { _, targetURL in
                restoreCount += 1
                let semanticRevision = UInt64(restoreCount)
                Task { @MainActor in
                    let lifetime = NSObject()
                    ownerReference.owner?.navigationWillStart(
                        on: fixture.webView,
                        navigationID: ObjectIdentifier(lifetime),
                        navigationLifetime: lifetime,
                        targetURL: targetURL,
                        semanticRevision: semanticRevision
                    )
                    ownerReference.owner?.navigationDidTerminate(
                        on: fixture.webView,
                        navigationID: ObjectIdentifier(lifetime),
                        navigationLifetime: lifetime,
                        succeeded: true
                    )
                }
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: semanticRevision
                    ),
                    semanticRevision: semanticRevision
                )
            },
            blankAttemptTimeout: .milliseconds(10)
        )
        ownerReference.owner = owner

        let cleanup = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        transaction = cleanup

        let didComplete = await cleanup.value
        XCTAssertFalse(didComplete)
        XCTAssertFalse(didDelete)
        XCTAssertEqual(restoreCount, 1)
    }

    func testCancellationBeforePhysicalMutationDoesNotRestoreUntouchedWebView() async {
        let fixture = makeFixture()
        let permissionRequested = CleanupTestSignal()
        var permissionContinuation: CheckedContinuation<Bool, Never>?
        var didDelete = false
        var restoreCount = 0
        var blankSubmissionCount = 0

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in
                await withCheckedContinuation { continuation in
                    permissionContinuation = continuation
                    permissionRequested.signal()
                }
            },
            loadBlankNavigation: { _ in
                blankSubmissionCount += 1
                return nil
            },
            restoreTab: { _, _ in
                restoreCount += 1
                return .init(outcome: .testFailure, semanticRevision: nil)
            }
        )

        let cleanup = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await permissionRequested.wait()
        cleanup.cancel()
        permissionContinuation?.resume(returning: true)
        permissionContinuation = nil

        let didComplete = await cleanup.value
        XCTAssertFalse(didComplete)
        XCTAssertFalse(didDelete)
        XCTAssertEqual(blankSubmissionCount, 0)
        XCTAssertEqual(restoreCount, 0)
    }

    func testNonConcreteRestoreDispositionFailsOnceWithoutWatchdog() async throws {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        let blankSubmitted = CleanupTestSignal()
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?
        var restoreCount = 0

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                restoreCount += 1
                return .init(
                    outcome: .waiting(
                        on: fixture.webView,
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {}
        }
        await blankSubmitted.wait()
        let identity = try XCTUnwrap(blankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertFalse(didComplete)
        XCTAssertEqual(restoreCount, 1)
    }

    func testSameURLForeignRevisionCannotClaimRestoreReceipt() async throws {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        let blankSubmitted = CleanupTestSignal()
        let restoreReceiptReturned = CleanupTestSignal()
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                let foreignLifetime = NSObject()
                ownerReference.owner?.navigationWillStart(
                    on: fixture.webView,
                    navigationID: ObjectIdentifier(foreignLifetime),
                    navigationLifetime: foreignLifetime,
                    targetURL: targetURL,
                    semanticRevision: 99
                )
                ownerReference.owner?.navigationDidTerminate(
                    on: fixture.webView,
                    navigationID: ObjectIdentifier(foreignLifetime),
                    navigationLifetime: foreignLifetime,
                    succeeded: true
                )
                restoreReceiptReturned.signal()
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {}
        }
        await blankSubmitted.wait()
        let identity = try XCTUnwrap(blankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )
        await restoreReceiptReturned.wait()

        let exactLifetime = NSObject()
        owner.navigationWillStart(
            on: fixture.webView,
            navigationID: ObjectIdentifier(exactLifetime),
            navigationLifetime: exactLifetime,
            targetURL: fixture.targetURL,
            semanticRevision: 1
        )
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: ObjectIdentifier(exactLifetime),
            navigationLifetime: exactLifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertTrue(didComplete)
    }

    func testRetiringResidenceBarrierCompletesBeforeLiveDiscoveryAndDeletion() async {
        let fixture = makeFixture()
        let barrierRequested = CleanupTestSignal()
        var barrierContinuation: CheckedContinuation<Bool, Never>?
        var barrierCallCount = 0
        var discoveryCount = 0
        var didDelete = false

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in
                discoveryCount += 1
                return []
            },
            waitForMutationPermission: { _ in true },
            restoreTab: { _, _ in
                XCTFail("No live participant should be restored")
                return .init(outcome: .testFailure, semanticRevision: nil)
            },
            waitForRetiringResidenceBarrier: {
                barrierCallCount += 1
                guard barrierCallCount == 1 else { return true }
                return await withCheckedContinuation {
                    barrierContinuation = $0
                    barrierRequested.signal()
                }
            }
        )

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await barrierRequested.wait()
        XCTAssertEqual(discoveryCount, 0)
        XCTAssertFalse(didDelete)

        barrierContinuation?.resume(returning: true)
        barrierContinuation = nil
        let didComplete = await transaction.value
        XCTAssertTrue(didComplete)
        XCTAssertGreaterThan(discoveryCount, 0)
        XCTAssertTrue(didDelete)
    }

    func testRestoreObligationTransfersToReplacementWebView() async throws {
        let fixture = makeFixture()
        let replacement = WKWebView()
        var liveWebViews = [fixture.webView]
        let ownerReference = CleanupOwnerReference()
        let blankSubmitted = CleanupTestSignal()
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?
        var restoreCount = 0

        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in liveWebViews },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction
                    .CleanupNavigationIdentity(
                        id: ObjectIdentifier(lifetime),
                        lifetime: lifetime
                    )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                restoreCount += 1
                fixture.tab.replaceUntrackedWebView(replacement)
                liveWebViews = [replacement]
                ownerReference.owner?.webViewDidLeaveRuntime(fixture.webView)
                return .init(
                    outcome: .accepted(
                        on: [replacement],
                        targetURL: targetURL,
                        revision: 2
                    ),
                    semanticRevision: 2
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {}
        }
        await blankSubmitted.wait()
        let identity = try XCTUnwrap(blankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )

        let didComplete = await transaction.value
        XCTAssertTrue(didComplete)
        XCTAssertEqual(restoreCount, 1)
    }

    func testExternalParticipantsQuiesceBeforeDeletion() async {
        let fixture = makeFixture()
        var quiescedProfileIDs: Set<UUID> = []
        var didDelete = false
        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [] },
            waitForMutationPermission: { _ in true },
            restoreTab: { _, _ in
                XCTFail("No live WebView should require restoration")
                return .init(outcome: .testFailure, semanticRevision: nil)
            },
            quiesceExternalParticipants: { profileIDs in
                quiescedProfileIDs = profileIDs
                return true
            }
        )

        let didComplete = await owner.performDestructiveDataCleanup(
            profileIDs: [fixture.profileID]
        ) {
            XCTAssertEqual(quiescedProfileIDs, [fixture.profileID])
            didDelete = true
        }

        XCTAssertTrue(didComplete)
        XCTAssertTrue(didDelete)
    }

    func testPartialDeletionFailureStillRestoresOnceAndReturnsFailure()
        async throws {
        let fixture = makeFixture()
        let ownerReference = CleanupOwnerReference()
        var blankIdentity: WebsiteDataCleanupTransaction.CleanupNavigationIdentity?
        let blankSubmitted = CleanupTestSignal()
        var restoreCount = 0
        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            loadBlankNavigation: { _ in
                let lifetime = NSObject()
                let identity = WebsiteDataCleanupTransaction.CleanupNavigationIdentity(
                    id: ObjectIdentifier(lifetime),
                    lifetime: lifetime
                )
                blankIdentity = identity
                blankSubmitted.signal()
                return identity
            },
            restoreTab: { _, targetURL in
                restoreCount += 1
                return .init(
                    outcome: .accepted(
                        on: [fixture.webView],
                        targetURL: targetURL,
                        revision: 1
                    ),
                    semanticRevision: 1
                )
            }
        )
        ownerReference.owner = owner

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanupReportingOutcome(
                profileIDs: [fixture.profileID],
                deletion: { false }
            )
        }
        await blankSubmitted.wait()
        let identity = try XCTUnwrap(blankIdentity)
        owner.navigationDidTerminate(
            on: fixture.webView,
            navigationID: identity.id,
            navigationLifetime: identity.lifetime,
            succeeded: true
        )

        let result = await transaction.value
        XCTAssertFalse(result)
        XCTAssertEqual(restoreCount, 1)
        XCTAssertNil(fixture.tab.websiteDataMutationPresentation)
    }

    func testUnresolvedCanonicalRuntimeTabFailsClosed() async {
        let fixture = makeFixture()
        var didDelete = false
        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { nil },
            liveWebViews: { _ in [fixture.webView] },
            waitForMutationPermission: { _ in true },
            restoreTab: { _, _ in
                XCTFail("Unresolved runtime participants must fail before restore")
                return .init(outcome: .testFailure, semanticRevision: nil)
            }
        )

        let didComplete = await owner.performDestructiveDataCleanup(
            profileIDs: [fixture.profileID]
        ) {
            didDelete = true
        }

        XCTAssertFalse(didComplete)
        XCTAssertFalse(didDelete)
    }

    func testResidenceBarrierTimeoutFailsClosedAndReleasesAdmissionGate() async {
        let fixture = makeFixture()
        let gate = WebsiteDataMutationGate()
        let barrierStarted = CleanupTestSignal()
        var didDelete = false
        let owner = WebsiteDataCleanupTransaction(
            runtimeTabs: { [fixture.tab] },
            liveWebViews: { _ in [] },
            waitForMutationPermission: { _ in true },
            restoreTab: { _, _ in
                XCTFail("No live WebView should require restoration")
                return .init(outcome: .testFailure, semanticRevision: nil)
            },
            mutationGate: gate,
            waitForRetiringResidenceBarrier: {
                barrierStarted.signal()
                // This sleep is a cancellation sentinel. The production
                // timeout must cancel it; elapsed time never makes it succeed.
                while Task.isCancelled == false {
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        return false
                    }
                }
                return false
            },
            residenceBarrierTimeout: .milliseconds(25)
        )

        let transaction = Task { @MainActor in
            await owner.performDestructiveDataCleanup(
                profileIDs: [fixture.profileID]
            ) {
                didDelete = true
            }
        }
        await barrierStarted.wait()
        let admission = Task { @MainActor in
            await gate.waitForOrdinaryRuntimeAdmission(for: fixture.profileID)
        }

        let transactionResult = await transaction.value
        let admissionResult = await admission.value
        XCTAssertFalse(transactionResult)
        XCTAssertTrue(admissionResult)
        XCTAssertFalse(didDelete)
    }

    private func makeFixture() -> CleanupFixture {
        let profileID = UUID()
        let targetURL = URL(string: "https://cleanup.example/document")!
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        tab.profileId = profileID
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        return CleanupFixture(
            profileID: profileID,
            targetURL: targetURL,
            tab: tab,
            webView: webView
        )
    }
}

@MainActor
private struct CleanupFixture {
    let profileID: UUID
    let targetURL: URL
    let tab: Tab
    let webView: WKWebView
}

@MainActor
private final class CleanupOwnerReference {
    weak var owner: WebsiteDataCleanupTransaction?
}

@MainActor
private final class CleanupTestSignal {
    private var count = 0
    private var waiters: [(
        targetCount: Int,
        continuation: CheckedContinuation<Void, Never>
    )] = []

    func signal() {
        count += 1
        let ready = waiters.filter { $0.targetCount <= count }
        waiters.removeAll { $0.targetCount <= count }
        ready.forEach { $0.continuation.resume() }
    }

    func wait(for targetCount: Int = 1) async {
        guard count < targetCount else { return }
        await withCheckedContinuation { continuation in
            waiters.append((targetCount, continuation))
        }
    }
}

private extension PageReloadCommandOutcome {
    static func accepted(
        on webViews: [WKWebView],
        targetURL: URL,
        revision: UInt64
    ) -> Self {
        let intent = TabMainFrameNavigationIntent(
            revision: revision,
            targetURL: targetURL
        )
        return Self(dispositions: webViews.map { webView in
            .submittedFallbackNavigation(PageReloadSubmission(
                owner: TabMainFramePendingAttemptOwner(
                    intent: intent,
                    documentGeneration: 0,
                    participantID: UUID(),
                    webViewID: ObjectIdentifier(webView),
                    phase: .submitted
                ),
                navigationID: ObjectIdentifier(webView)
            ))
        })
    }

    static func waiting(
        on webView: WKWebView,
        targetURL: URL,
        revision: UInt64
    ) -> Self {
        Self(.waiting(TabMainFramePendingAttemptOwner(
            intent: TabMainFrameNavigationIntent(
                revision: revision,
                targetURL: targetURL
            ),
            documentGeneration: 0,
            participantID: UUID(),
            webViewID: ObjectIdentifier(webView),
            phase: .deferred
        )))
    }

    static var testFailure: Self {
        .failed(intent: nil, reason: .submissionFailed)
    }
}
