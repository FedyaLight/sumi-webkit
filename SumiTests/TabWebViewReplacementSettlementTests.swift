import Combine
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
extension TabWebViewMaterializationAndRebuildTests {
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

    func testDuplicateTabReplacementBatchRejectsBeforeRepositoryAdmission()
        throws {
        let fixture = try makePreparedPolicyReplacementFixture(
            path: "duplicate-tab-batch"
        )
        var modelStageCount = 0
        let pipeline = replacementPipeline(
            repository: fixture.repository,
            tab: fixture.tab,
            departureBatches: { _ in
                XCTFail("Invalid batch cannot retire a generation")
            },
            destroy: { _ in
                XCTFail("Invalid batch cannot destroy a WebView")
            }
        )

        guard case .invalid = pipeline.begin(
            [fixture.prepared, fixture.prepared],
            profileIDs: [],
            model: .transaction(TestWebViewReplacementModelTransaction(
                stage: { modelStageCount += 1 }
            )),
            completion: { _ in
                XCTFail("Invalid batch cannot start settlement")
            }
        ) else {
            return XCTFail("Expected duplicate Tab rejection")
        }

        XCTAssertEqual(modelStageCount, 0)
        XCTAssertEqual(fixture.originalReceipt.phase, .cancelled)
        assertPlacementWasNotReplaced(fixture)
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

    func testFreshRepairCommitPreservesHealthyCrossWindowResidence() throws {
        let repository = WebViewSessionRepository()
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/fresh-repair")
        )
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let healthyWindowID = UUID()
        let failedWindowID = UUID()
        let healthy = WKWebView()
        let failed = WKWebView()
        register(
            healthy,
            tabID: tab.id,
            windowID: healthyWindowID,
            in: repository
        )
        register(
            failed,
            tabID: tab.id,
            windowID: failedWindowID,
            in: repository
        )
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        configuration.userContentController =
            SumiNormalTabUserContentControllerFactory.makeController()
        let candidate = WKWebView(frame: .zero, configuration: configuration)
        let snapshot = repository.snapshot(for: tab.id)
        candidate.sumiPreparedConfigurationPolicyChange =
            tab.configurationPolicyLedger.prepare(
                TabConfigurationPolicyState(
                    profileID: nil,
                    websiteDataStoreIdentity: ObjectIdentifier(
                        candidate.configuration.websiteDataStore
                    ),
                    protectionAttachment: nil,
                    safariContentBlockerAttachment: nil,
                    autoplayState: .blockAll
                ),
                expectedSessionGeneration: snapshot.generation
            )
        let changeSet = try XCTUnwrap(
            tab.preparedConfigurationPolicyChangeSet(for: [candidate])
        )
        let retired = WebViewSessionSnapshot(
            generation: snapshot.generation,
            parkedWebView: nil,
            untrackedWebView: nil,
            primaryWindowID: nil,
            windowWebViews: [failedWindowID: failed]
        )
        let prepared = try XCTUnwrap(PreparedWebViewReplacement(
            tab: tab,
            snapshot: snapshot,
            placement: .windowSubset(
                webViewsByWindowID: [failedWindowID: candidate]
            ),
            replacements: [candidate],
            trackedReplacements: [candidate],
            bindingReplacements: [],
            targetURL: targetURL,
            semanticRevision: tab.mainFrameLoads.currentIntent.revision,
            profileID: nil,
            requiresExtensionRuntimePreparation: false,
            configurationPolicyChangeSet: changeSet,
            retiredSnapshot: retired
        ))
        var retiredIDs: [ObjectIdentifier] = []
        let pipeline = replacementPipeline(
            repository: repository,
            tab: tab,
            departureBatches: { webViews in
                retiredIDs = webViews.map(ObjectIdentifier.init)
            },
            destroy: { _ in }
        )

        guard case .committed = pipeline.begin(
            [prepared],
            profileIDs: [],
            model: .noExternalModel,
            completion: { _ in }
        ) else {
            return XCTFail("Expected exact-residence repair to commit")
        }

        XCTAssertEqual(retiredIDs, [ObjectIdentifier(failed)])
        XCTAssertIdentical(
            repository.webView(for: tab.id, in: healthyWindowID),
            healthy
        )
        XCTAssertIdentical(
            repository.webView(for: tab.id, in: failedWindowID),
            candidate
        )
    }

}
