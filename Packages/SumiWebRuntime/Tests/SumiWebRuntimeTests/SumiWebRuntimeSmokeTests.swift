import AppKit
import XCTest
import WebKit
import SumiWebRuntime

final class SumiWebRuntimeSmokeTests: XCTestCase {
    @MainActor
    func testRegistryStartsEmpty() {
        let registry = WebViewSessionRepository()
        XCTAssertTrue(registry.isTrackingEmpty)
        XCTAssertEqual(registry.totalTrackedWebViewCount, 0)
    }

    func testVisibleTabPreparationPlanOrdersSplitTabs() {
        let tabA = UUID()
        let tabB = UUID()
        let ordered = VisibleTabPreparationPlan.visibleTabIDs(
            currentTabId: tabA,
            splitTabIds: [tabB, tabA]
        )
        XCTAssertEqual(ordered, [tabB, tabA])
    }

    @MainActor
    func testWebRuntimeBoundaryProtocolsExposeSessionAccessors() {
        final class StubTab: WebRuntimeTabHandle {
            let id: UUID
            let webViewSession: WebViewSessionHandle
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil

            init(repository: WebViewSessionRepository) {
                let id = UUID()
                self.id = id
                self.webViewSession = WebViewSessionHandle(
                    tabID: id,
                    repository: repository
                )
            }
        }

        final class StubWindow: WebRuntimeWindowHandle {
            let id = UUID()
            var ephemeralTabHandles: [any WebRuntimeTabHandle] = []
        }

        struct StubResolver: WebRuntimeTabResolving {
            let tab: any WebRuntimeTabHandle
            func resolveWebRuntimeTab(_ id: UUID) -> (any WebRuntimeTabHandle)? {
                tab.id == id ? tab : nil
            }
        }

        let tab = StubTab(repository: WebViewSessionRepository())
        let window = StubWindow()
        window.ephemeralTabHandles = [tab]
        let resolver = StubResolver(tab: tab)

        XCTAssertEqual(tab.webViewSession.tabID, tab.id)
        XCTAssertEqual(window.ephemeralTabHandles.first?.id, tab.id)
        XCTAssertIdentical(resolver.resolveWebRuntimeTab(tab.id) as AnyObject?, tab)
        XCTAssertNil(resolver.resolveWebRuntimeTab(UUID()))
    }

    @MainActor
    func testWebRuntimeTabMaterializingSurface() {
        final class StubMaterializingTab: WebRuntimeTabMaterializing {
            private(set) var makeCallCount = 0

            func makeNormalTabWebView(reason: String) -> WKWebView? {
                makeCallCount += 1
                XCTAssertEqual(reason, "smoke")
                let configuration = WKWebViewConfiguration()
                let webView = WKWebView(frame: .zero, configuration: configuration)
                return webView
            }
        }

        let stub = StubMaterializingTab()
        let materializing: any WebRuntimeTabMaterializing = stub

        guard let webView = materializing.makeNormalTabWebView(reason: "smoke") else {
            return XCTFail("Expected materializing stub to return a WebView")
        }
        XCTAssertEqual(stub.makeCallCount, 1)
        XCTAssertNotNil(webView)
    }

    @MainActor
    func testWebRuntimeTabTeardownLifecycleSurface() {
        final class StubTeardownTab: WebRuntimeTabHandle, WebRuntimeTabTeardownLifecycle {
            let id: UUID
            let webViewSession: WebViewSessionHandle
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil
            private(set) var cleanedWebViews: [ObjectIdentifier] = []
            private(set) var cancelledNavigation = false

            init(repository: WebViewSessionRepository) {
                let id = UUID()
                self.id = id
                self.webViewSession = WebViewSessionHandle(
                    tabID: id,
                    repository: repository
                )
            }

            func cleanupCloneWebView(_ webView: WKWebView) {
                cleanedWebViews.append(ObjectIdentifier(webView))
            }

            func cancelPendingMainFrameNavigation() {
                cancelledNavigation = true
            }

        }

        let stub = StubTeardownTab(repository: WebViewSessionRepository())
        let lifecycle: any WebRuntimeTabTeardownLifecycle = stub
        let webView = WKWebView()

        lifecycle.cleanupCloneWebView(webView)
        lifecycle.cancelPendingMainFrameNavigation()

        XCTAssertEqual(stub.cleanedWebViews, [ObjectIdentifier(webView)])
        XCTAssertTrue(stub.cancelledNavigation)
    }

    @MainActor
    func testTabTeardownOwnerSuspendsViaLifecycleProtocol() {
        final class StubTeardownTab: WebRuntimeTabHandle, WebRuntimeTabTeardownLifecycle {
            let id: UUID
            let webViewSession: WebViewSessionHandle
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil
            private(set) var cleanedCount = 0
            private(set) var cancelledNavigation = false

            init(repository: WebViewSessionRepository) {
                let id = UUID()
                self.id = id
                self.webViewSession = WebViewSessionHandle(
                    tabID: id,
                    repository: repository
                )
            }

            func cleanupCloneWebView(_ webView: WKWebView) {
                cleanedCount += 1
            }

            func cancelPendingMainFrameNavigation() {
                cancelledNavigation = true
            }

        }

        let registry = WebViewSessionRepository()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let tab = StubTeardownTab(repository: registry)
        let webView = WKWebView()
        tab.webViewSession.replaceUntracked(with: webView)

        let owner = WebViewTabTeardownOwner(
            webViewSessions: registry,
            mediaProtectionOwner: mediaProtectionOwner,
            isWebViewProtectedFromCompositorMutation: { _ in false },
            enqueueDeferredProtectedCommand: { _, _, _ in false },
            cleanupUnprotectedTrackedWebView: { _, _, _ in },
            cleanupUnprotectedDetachedWebView: { _, _, _ in },
            refreshPrimaryTrackedWebView: { _ in },
            removeWebViewFromContainers: { _ in },
            unregisterTrackedWebViewSlot: { _, _ in nil }
        )

        XCTAssertTrue(owner.suspendWebViews(for: tab, reason: "smoke"))
        XCTAssertEqual(tab.cleanedCount, 1)
        XCTAssertTrue(tab.cancelledNavigation)
        XCTAssertTrue(owner.allKnownWebViews(for: tab).isEmpty)
    }

    @MainActor
    func testWebRuntimeTabSiteReloadAndMuteSurfaces() {
        final class StubTab:
            WebRuntimeTabHandle,
            WebRuntimeTabSiteReloadPolicyNotifying,
            WebRuntimeTabAudioMuteSnapshotting
        {
            let id: UUID
            let webViewSession: WebViewSessionHandle
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil
            var isAudioMuted = true
            private(set) var safariReloadCount = 0
            private(set) var protectionReloadCount = 0
            private(set) var autoplayReloadCount = 0

            init() {
                let id = UUID()
                self.id = id
                self.webViewSession = WebViewSessionHandle(tabID: id)
            }

            func updateSafariContentBlockerReloadRequirementForCurrentSite() {
                safariReloadCount += 1
            }

            func updateProtectionReloadRequirementForCurrentSite() {
                protectionReloadCount += 1
            }

            func updateAutoplayReloadRequirementForCurrentSite() {
                autoplayReloadCount += 1
            }

        }

        let stub = StubTab()
        let handle: any WebRuntimeTabHandle = stub
        handle.url = URL(string: "https://example.com/updated")!
        XCTAssertEqual(stub.url.absoluteString, "https://example.com/updated")

        let reload: any WebRuntimeTabSiteReloadPolicyNotifying = stub
        reload.updateSafariContentBlockerReloadRequirementForCurrentSite()
        reload.updateProtectionReloadRequirementForCurrentSite()
        reload.updateAutoplayReloadRequirementForCurrentSite()
        XCTAssertEqual(stub.safariReloadCount, 1)
        XCTAssertEqual(stub.protectionReloadCount, 1)
        XCTAssertEqual(stub.autoplayReloadCount, 1)

        let mute: any WebRuntimeTabAudioMuteSnapshotting = stub
        XCTAssertTrue(mute.isAudioMuted)
    }

    @MainActor
    func testCompositorHandoffStateStoresPromotedHostAsProtocol() {
        final class StubHost: WebRuntimePromotedHost {
            let tabID = UUID()
            let webView = WKWebView()
            private(set) var prepareCount = 0

            func prepareForSuperviewTransferPreservingDisplayedContent() {
                prepareCount += 1
            }
        }

        let handoffState = WebViewCompositorHandoffState()
        let host = StubHost()
        let windowID = UUID()
        let container = NSView()
        var outcomes: [PromotedHostAttachmentOutcome] = []
        let registration = handoffState.registerContainerView(container, for: windowID)

        XCTAssertTrue(handoffState.registerPromotedHost(
            host,
            for: host.tabID,
            in: windowID,
            attachmentCompletion: { outcomes.append($0) }
        ))

        handoffState.completePromotedHostAttachment(
            for: host.tabID,
            in: windowID,
            containerRegistration: registration
        )
        XCTAssertTrue(outcomes.isEmpty)

        let taken = handoffState.takePromotedHost(
            for: host.tabID,
            in: windowID,
            containerRegistration: registration,
            expectedWebView: host.webView
        )
        XCTAssertIdentical(taken as AnyObject?, host)
        XCTAssertEqual(host.prepareCount, 1)
        XCTAssertNil(
            handoffState.takePromotedHost(
                for: host.tabID,
                in: windowID,
                containerRegistration: registration,
                expectedWebView: host.webView
            )
        )
        handoffState.completePromotedHostAttachment(
            for: host.tabID,
            in: windowID,
            containerRegistration: registration
        )
        handoffState.completePromotedHostAttachment(
            for: host.tabID,
            in: windowID,
            containerRegistration: registration
        )
        XCTAssertEqual(outcomes, [.attached])
        withExtendedLifetime(container) {}
    }

    @MainActor
    func testStaleContainerRegistrationCannotTakeOrCompleteReplacementPromotion() {
        final class StubHost: WebRuntimePromotedHost {
            let tabID = UUID()
            let webView = WKWebView()
            func prepareForSuperviewTransferPreservingDisplayedContent() {}
        }

        let state = WebViewCompositorHandoffState()
        let windowID = UUID()
        let staleContainer = NSView()
        let currentContainer = NSView()
        let staleRegistration = state.registerContainerView(staleContainer, for: windowID)
        let currentRegistration = state.registerContainerView(currentContainer, for: windowID)
        let host = StubHost()
        var outcomes: [PromotedHostAttachmentOutcome] = []
        XCTAssertTrue(state.registerPromotedHost(
            host,
            for: host.tabID,
            in: windowID,
            attachmentCompletion: { outcomes.append($0) }
        ))

        XCTAssertNil(state.takePromotedHost(
            for: host.tabID,
            in: windowID,
            containerRegistration: staleRegistration,
            expectedWebView: host.webView
        ))
        state.completePromotedHostAttachment(
            for: host.tabID,
            in: windowID,
            containerRegistration: staleRegistration
        )
        XCTAssertTrue(outcomes.isEmpty)

        XCTAssertIdentical(
            state.takePromotedHost(
                for: host.tabID,
                in: windowID,
                containerRegistration: currentRegistration,
                expectedWebView: host.webView
            ) as AnyObject?,
            host
        )
        state.completePromotedHostAttachment(
            for: host.tabID,
            in: windowID,
            containerRegistration: currentRegistration
        )
        XCTAssertEqual(outcomes, [.attached])
        withExtendedLifetime((staleContainer, currentContainer)) {}
    }

    @MainActor
    func testRemovingWindowReleasesPromotedHostAndCancelsAttachmentOnce() {
        final class StubHost: WebRuntimePromotedHost {
            let tabID = UUID()
            let webView = WKWebView()
            func prepareForSuperviewTransferPreservingDisplayedContent() {}
        }

        let state = WebViewCompositorHandoffState()
        let windowID = UUID()
        let container = NSView()
        var host: StubHost? = StubHost()
        weak let weakHost = host
        var outcomes: [PromotedHostAttachmentOutcome] = []
        state.registerContainerView(container, for: windowID)
        XCTAssertTrue(state.registerPromotedHost(
            host!,
            for: host!.tabID,
            in: windowID,
            attachmentCompletion: { outcomes.append($0) }
        ))
        host = nil

        XCTAssertNotNil(weakHost)
        state.removeContainerView(for: windowID)

        XCTAssertNil(weakHost)
        XCTAssertEqual(outcomes, [.cancelled])
        state.removeContainerView(for: windowID)
        XCTAssertEqual(outcomes, [.cancelled])
        withExtendedLifetime(container) {}
    }

    @MainActor
    func testRemovingAllRegistrationsFinishesEveryPendingPromotionOnce() {
        final class StubHost: WebRuntimePromotedHost {
            let tabID = UUID()
            let webView = WKWebView()
            func prepareForSuperviewTransferPreservingDisplayedContent() {}
        }

        let state = WebViewCompositorHandoffState()
        let first = StubHost()
        let second = StubHost()
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let firstContainer = NSView()
        let secondContainer = NSView()
        var outcomesByTabID: [UUID: [PromotedHostAttachmentOutcome]] = [:]
        state.registerContainerView(firstContainer, for: firstWindowID)
        state.registerContainerView(secondContainer, for: secondWindowID)
        XCTAssertTrue(state.registerPromotedHost(
            first,
            for: first.tabID,
            in: firstWindowID,
            attachmentCompletion: { outcomesByTabID[first.tabID, default: []].append($0) }
        ))
        XCTAssertTrue(state.registerPromotedHost(
            second,
            for: second.tabID,
            in: secondWindowID,
            attachmentCompletion: { outcomesByTabID[second.tabID, default: []].append($0) }
        ))

        state.removeAllWindowRegistrations()
        state.removeAllWindowRegistrations()

        XCTAssertEqual(outcomesByTabID[first.tabID], [.cancelled])
        XCTAssertEqual(outcomesByTabID[second.tabID], [.cancelled])
        XCTAssertEqual(outcomesByTabID.count, 2)
        withExtendedLifetime((firstContainer, secondContainer)) {}
    }

    @MainActor
    func testReplacingPendingPromotionCancelsOldAndResolvesNewExactlyOnce() {
        final class StubHost: WebRuntimePromotedHost {
            let tabID: UUID
            let webView = WKWebView()

            init(tabID: UUID) {
                self.tabID = tabID
            }

            func prepareForSuperviewTransferPreservingDisplayedContent() {}
        }

        let state = WebViewCompositorHandoffState()
        let tabID = UUID()
        let windowID = UUID()
        let container = NSView()
        let first = StubHost(tabID: tabID)
        let second = StubHost(tabID: tabID)
        var firstOutcomes: [PromotedHostAttachmentOutcome] = []
        var secondOutcomes: [PromotedHostAttachmentOutcome] = []
        let registration = state.registerContainerView(container, for: windowID)

        XCTAssertTrue(state.registerPromotedHost(
            first,
            for: tabID,
            in: windowID,
            attachmentCompletion: { firstOutcomes.append($0) }
        ))
        XCTAssertTrue(state.registerPromotedHost(
            second,
            for: tabID,
            in: windowID,
            attachmentCompletion: { secondOutcomes.append($0) }
        ))

        XCTAssertEqual(firstOutcomes, [.cancelled])
        XCTAssertTrue(secondOutcomes.isEmpty)
        XCTAssertIdentical(
            state.takePromotedHost(
                for: tabID,
                in: windowID,
                containerRegistration: registration,
                expectedWebView: second.webView
            ) as AnyObject?,
            second
        )
        state.completePromotedHostAttachment(
            for: tabID,
            in: windowID,
            containerRegistration: registration
        )
        state.removeContainerView(for: windowID)

        XCTAssertEqual(firstOutcomes, [.cancelled])
        XCTAssertEqual(secondOutcomes, [.attached])
        withExtendedLifetime(container) {}
    }

    @MainActor
    func testStaleContainerCancelsPendingPromotionExactlyOnce() {
        final class StubHost: WebRuntimePromotedHost {
            let tabID = UUID()
            let webView = WKWebView()
            func prepareForSuperviewTransferPreservingDisplayedContent() {}
        }

        let state = WebViewCompositorHandoffState()
        let windowID = UUID()
        let host = StubHost()
        var container: NSView? = NSView()
        var outcomes: [PromotedHostAttachmentOutcome] = []
        state.registerContainerView(container!, for: windowID)
        XCTAssertTrue(state.registerPromotedHost(
            host,
            for: host.tabID,
            in: windowID,
            attachmentCompletion: { outcomes.append($0) }
        ))

        container = nil
        XCTAssertNil(state.containerView(for: windowID))
        XCTAssertNil(state.containerView(for: windowID))

        XCTAssertEqual(outcomes, [.cancelled])
    }

    @MainActor
    func testRegistrationAfterContainerRemovalIsRejectedWithoutRetentionOrCompletion() {
        final class StubHost: WebRuntimePromotedHost {
            let tabID = UUID()
            let webView = WKWebView()
            func prepareForSuperviewTransferPreservingDisplayedContent() {}
        }

        let state = WebViewCompositorHandoffState()
        let windowID = UUID()
        let container = NSView()
        var host: StubHost? = StubHost()
        weak let weakHost = host
        var outcomes: [PromotedHostAttachmentOutcome] = []
        let registration = state.registerContainerView(container, for: windowID)
        XCTAssertTrue(state.removeContainerView(registration))

        XCTAssertFalse(state.registerPromotedHost(
            host!,
            for: host!.tabID,
            in: windowID,
            attachmentCompletion: { outcomes.append($0) }
        ))
        host = nil

        XCTAssertNil(weakHost)
        XCTAssertTrue(outcomes.isEmpty)
        state.removeAllWindowRegistrations()
        XCTAssertTrue(outcomes.isEmpty)
        withExtendedLifetime(container) {}
    }

    @MainActor
    func testStaleContainerRegistrationCannotRemoveReplacement() {
        let state = WebViewCompositorHandoffState()
        let windowID = UUID()
        let firstContainer = NSView()
        let replacementContainer = NSView()
        var firstHandoffCount = 0
        var replacementHandoffCount = 0
        let firstRegistration = state.registerContainerView(
            firstContainer,
            for: windowID,
            immediateVisualHandoffHandler: {
                firstHandoffCount += 1
                return true
            }
        )
        let replacementRegistration = state.registerContainerView(
            replacementContainer,
            for: windowID,
            immediateVisualHandoffHandler: {
                replacementHandoffCount += 1
                return true
            }
        )

        XCTAssertFalse(state.removeContainerView(firstRegistration))
        XCTAssertIdentical(state.containerView(for: windowID), replacementContainer)
        XCTAssertTrue(state.performImmediateVisualHandoffIfPossible(in: windowID))
        XCTAssertEqual(firstHandoffCount, 0)
        XCTAssertEqual(replacementHandoffCount, 1)
        XCTAssertTrue(state.removeContainerView(replacementRegistration))
        XCTAssertNil(state.containerView(for: windowID))
        withExtendedLifetime((firstContainer, replacementContainer)) {}
    }

    @MainActor
    func testVisibleWebViewRuntimeOwnerConformsToPreparationControlling() {
        final class StubWindow: WebRuntimeWindowHandle {
            let id = UUID()
            var ephemeralTabHandles: [any WebRuntimeTabHandle] = []
        }

        final class StubTab: WebRuntimeTabHandle {
            let id: UUID
            let webViewSession: WebViewSessionHandle
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil

            init() {
                let id = UUID()
                self.id = id
                self.webViewSession = WebViewSessionHandle(tabID: id)
            }
        }

        let owner = VisibleWebViewRuntimeOwner()
        let controlling: any WebRuntimeVisiblePreparationControlling = owner
        let window = StubWindow()
        let tab = StubTab()
        let registry = WebViewSessionRepository()
        var marked: [UUID] = []
        var created = 0

        let runtime = VisibleWebViewPreparationRuntime(
            windowState: { $0 == window.id ? window : nil },
            currentTabId: { $0.id == window.id ? tab.id : nil },
            splitVisibleTabIds: { _ in [] },
            resolveTab: { tabId, _ in tabId == tab.id ? tab : nil },
            canMaterializeWebViewDuringStartup: { _ in true },
            markTabAccessed: { marked.append($0) },
            evictHiddenWebViews: { _, _ in },
            scheduleTabSuspensionReconcile: { _ in },
            scheduleBackgroundMediaReconcile: { _ in },
            refreshCompositor: { _ in }
        )

        let didCreate = owner.prepareVisibleWebViews(
            for: window,
            runtime: runtime,
            webViewSessions: registry,
            existingWebView: { _, _ in nil },
            createWebView: { _, _ in
                created += 1
                return WKWebView()
            }
        )

        XCTAssertTrue(didCreate)
        XCTAssertEqual(created, 1)
        XCTAssertEqual(marked, [tab.id])

        controlling.cancelScheduledPreparation(for: window.id)
        controlling.resetWindowRegistrations()
    }

    @MainActor
    func testDeferredCommandExecutionKeepsCommandWhenSourceIsReprotected() {
        let media = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let webViewID = ObjectIdentifier(webView)
        let command = DeferredWebViewCommand.removeWebViewFromContainers(
            webViewID: webViewID
        )

        let firstProtectionLease = media.beginVisualHandoffProtection(for: webView)
        XCTAssertEqual(media.enqueueDeferredCommandIfNeeded(
            command,
            for: webView,
            reason: "test.reprotected-dequeue",
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in }
        ), .scheduled)

        _ = media.finishVisualHandoffProtection(firstProtectionLease)
        let secondProtectionLease = media.beginVisualHandoffProtection(for: webView)
        var executedCommands: [DeferredWebViewCommand] = []
        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: {
                executedCommands.append($0)
                return .executed
            }
        ), 0)
        XCTAssertTrue(executedCommands.isEmpty)
        XCTAssertTrue(media.hasDeferredProtectedCommands(for: webViewID))

        _ = media.finishVisualHandoffProtection(secondProtectionLease)
        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: {
                executedCommands.append($0)
                return .executed
            }
        ), 1)
        guard executedCommands.count == 1,
              case .removeWebViewFromContainers(let executedWebViewID) = executedCommands[0]
        else {
            return XCTFail("Expected retained command after the second protection release")
        }
        XCTAssertEqual(executedWebViewID, webViewID)
        XCTAssertFalse(media.hasDeferredProtectedCommands(for: webViewID))
    }

    @MainActor
    func testStaleVisualHandoffLeaseCannotReleaseNewerProtection() {
        let media = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let staleLease = media.beginVisualHandoffProtection(for: webView)
        let currentLease = media.beginVisualHandoffProtection(for: webView)

        XCTAssertTrue(media.isProtected(webView))
        XCTAssertEqual(
            media.finishVisualHandoffProtection(staleLease),
            ObjectIdentifier(webView)
        )
        XCTAssertTrue(media.isProtected(webView))
        XCTAssertNil(media.finishVisualHandoffProtection(staleLease))

        XCTAssertEqual(
            media.finishVisualHandoffProtection(currentLease),
            ObjectIdentifier(webView)
        )
        XCTAssertFalse(media.isProtected(webView))
    }

    @MainActor
    func testHistorySwipeFinishRequiresTheExactActiveSource() {
        let media = WebViewMediaProtectionOwner()
        let protectedWebView = WKWebView()
        let unrelatedWebView = WKWebView()
        _ = media.beginHistorySwipeProtection(
            on: protectedWebView,
            windowID: UUID(),
            originURL: nil,
            originHistoryItem: nil
        )

        XCTAssertNil(media.finishHistorySwipeProtection(
            on: unrelatedWebView,
            currentURL: nil,
            currentHistoryItem: nil
        ))
        XCTAssertTrue(media.isProtected(protectedWebView))
        XCTAssertNotNil(media.finishHistorySwipeProtection(
            on: protectedWebView,
            currentURL: nil,
            currentHistoryItem: nil
        ))
        XCTAssertFalse(media.isProtected(protectedWebView))
    }

    @MainActor
    func testFailedDeferredExecutionRetainsGuaranteedCommandForRetry() {
        let media = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let webViewID = ObjectIdentifier(webView)
        let lease = media.beginVisualHandoffProtection(for: webView)
        XCTAssertEqual(media.enqueueDeferredCommandIfNeeded(
            .removeWebViewFromContainers(webViewID: webViewID),
            for: webView,
            reason: "test.retry-guaranteed-command",
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in }
        ), .scheduled)
        _ = media.finishVisualHandoffProtection(lease)

        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: { _ in .retry }
        ), 0)
        XCTAssertTrue(media.hasDeferredProtectedCommands(for: webViewID))

        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: { _ in .executed }
        ), 1)
        XCTAssertFalse(media.hasDeferredProtectedCommands(for: webViewID))
    }

    @MainActor
    func testInvalidTargetExecutionDropsCommandAndContinuesFlushing() {
        let media = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let webViewID = ObjectIdentifier(webView)
        let windowID = UUID()
        let lease = media.beginVisualHandoffProtection(for: webView)
        var droppedReasons: [String] = []

        for command in [
            DeferredWebViewCommand.removeWebViewFromContainers(webViewID: webViewID),
            .cleanupWindow(windowID: windowID),
        ] {
            XCTAssertEqual(media.enqueueDeferredCommandIfNeeded(
                command,
                for: webView,
                reason: "test.execution-outcome",
                resolveWebView: { $0 == webViewID ? webView : nil },
                isCommandValid: { _ in true },
                dropCommand: { _, _, reason in droppedReasons.append(reason) },
                didPruneStaleWebViewIDs: { _ in }
            ), .scheduled)
        }
        _ = media.finishVisualHandoffProtection(lease)

        var executionCount = 0
        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, reason in droppedReasons.append(reason) },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: { _ in
                executionCount += 1
                return executionCount == 1 ? .invalidTarget : .executed
            }
        ), 1)

        XCTAssertEqual(executionCount, 2)
        XCTAssertEqual(droppedReasons, ["flush.execution.invalidTarget"])
        XCTAssertFalse(media.hasDeferredProtectedCommands(for: webViewID))
    }

    @MainActor
    func testRetryRestorationPreservesQueuedDominator() {
        let media = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let webViewID = ObjectIdentifier(webView)
        let tabID = UUID()
        let windowID = UUID()
        let navigation = DeferredWebViewCommand.synchronizeTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: DeferredWebViewNavigationIntent(
                revision: 1,
                targetURL: URL(string: "https://example.com/retry")!
            )
        )
        let initialLease = media.beginVisualHandoffProtection(for: webView)
        var droppedCommands: [(DeferredWebViewCommand, String)] = []
        XCTAssertEqual(media.enqueueDeferredCommandIfNeeded(
            navigation,
            for: webView,
            reason: "test.retry-dominance",
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { droppedCommands.append(($0, $2)) },
            didPruneStaleWebViewIDs: { _ in }
        ), .scheduled)
        _ = media.finishVisualHandoffProtection(initialLease)

        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { droppedCommands.append(($0, $2)) },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: { _ in
                let retryLease = media.beginVisualHandoffProtection(for: webView)
                XCTAssertEqual(media.enqueueDeferredCommandIfNeeded(
                    .cleanupWindow(windowID: windowID),
                    for: webView,
                    reason: "test.retry-dominator",
                    resolveWebView: { $0 == webViewID ? webView : nil },
                    isCommandValid: { _ in true },
                    dropCommand: { droppedCommands.append(($0, $2)) },
                    didPruneStaleWebViewIDs: { _ in }
                ), .scheduled)
                _ = media.finishVisualHandoffProtection(retryLease)
                return .retry
            }
        ), 0)

        XCTAssertEqual(droppedCommands.count, 1)
        XCTAssertEqual(droppedCommands[0].1, "flush.restore.superseded")
        guard case .synchronizeTrackedNavigation = droppedCommands[0].0 else {
            return XCTFail("Expected the retried narrow command to be superseded")
        }
        XCTAssertTrue(media.hasDeferredProtectedCommands(for: webViewID))

        var executedCommands: [DeferredWebViewCommand] = []
        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: {
                executedCommands.append($0)
                return .executed
            }
        ), 1)
        guard executedCommands.count == 1,
              case .cleanupWindow(let executedWindowID) = executedCommands[0]
        else {
            return XCTFail("Expected the queued dominator to execute")
        }
        XCTAssertEqual(executedWindowID, windowID)
        XCTAssertFalse(media.hasDeferredProtectedCommands(for: webViewID))
    }

    @MainActor
    func testRetryDoesNotPromoteReplaceableMaintenanceToGuaranteedWork() {
        let media = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let webViewID = ObjectIdentifier(webView)
        let lease = media.beginVisualHandoffProtection(for: webView)
        let command = DeferredWebViewCommand.rebuildLiveWebViews(
            tabID: UUID(),
            preferredPrimaryWindowID: nil,
            intent: DeferredWebViewRebuildIntent(
                revision: 1,
                targetURL: URL(string: "https://example.com/maintenance")!,
                configuration: .normal,
                kind: .maintenance
            )
        )
        XCTAssertEqual(media.enqueueDeferredCommandIfNeeded(
            command,
            for: webView,
            reason: "test.retry-replaceable",
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in }
        ), .scheduled)
        _ = media.finishVisualHandoffProtection(lease)

        var droppedReasons: [String] = []
        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, reason in droppedReasons.append(reason) },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: { _ in .retry }
        ), 0)

        XCTAssertEqual(droppedReasons, ["flush.retry.replaceable"])
        XCTAssertFalse(media.hasDeferredProtectedCommands(for: webViewID))
    }

    @MainActor
    func testDeferredCommandExecutionRechecksProtectionAfterValidation() {
        let media = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let webViewID = ObjectIdentifier(webView)
        let command = DeferredWebViewCommand.removeWebViewFromContainers(
            webViewID: webViewID
        )
        var executedCommands: [DeferredWebViewCommand] = []

        let initialProtectionLease = media.beginVisualHandoffProtection(for: webView)
        XCTAssertEqual(media.enqueueDeferredCommandIfNeeded(
            command,
            for: webView,
            reason: "test.validation-reprotected",
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in }
        ), .scheduled)
        _ = media.finishVisualHandoffProtection(initialProtectionLease)

        var validationCount = 0
        var reProtectionLease: WebViewVisualHandoffProtectionLease?
        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in
                validationCount += 1
                if validationCount == 2 {
                    reProtectionLease = media.beginVisualHandoffProtection(for: webView)
                }
                return true
            },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: {
                executedCommands.append($0)
                return .executed
            }
        ), 0)
        XCTAssertEqual(validationCount, 2)
        XCTAssertTrue(executedCommands.isEmpty)
        XCTAssertTrue(media.hasDeferredProtectedCommands(for: webViewID))

        guard let reProtectionLease else {
            return XCTFail("Expected validation to re-protect the source")
        }
        _ = media.finishVisualHandoffProtection(reProtectionLease)
        XCTAssertEqual(media.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: { $0 == webViewID ? webView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in },
            didPruneStaleWebViewIDs: { _ in },
            executeCommand: {
                executedCommands.append($0)
                return .executed
            }
        ), 1)
        XCTAssertEqual(executedCommands.count, 1)
        XCTAssertFalse(media.hasDeferredProtectedCommands(for: webViewID))
    }

    @MainActor
    func testWindowCleanupOwnerResetsVisibleStateAndFlushesCommandsUnblockedByGlobalReset() {
        final class StubVisiblePreparation: WebRuntimeVisiblePreparationControlling {
            var cancelledWindowIDs: [UUID] = []
            var didReset = false

            func cancelScheduledPreparation(for windowId: UUID) {
                cancelledWindowIDs.append(windowId)
            }

            func resetWindowRegistrations() {
                didReset = true
            }
        }

        let registry = WebViewSessionRepository()
        let visible = StubVisiblePreparation()
        let media = WebViewMediaProtectionOwner()
        let scope = WebViewCleanupScopeOwner()
        var removedContainers: [UUID] = []
        var flushedSourceIDs: [ObjectIdentifier] = []
        var finishedSuppression = false
        let pendingCleanupWebView = WKWebView()
        guard let pendingCleanupLease = registry.beginPendingCleanup(
            of: pendingCleanupWebView,
            for: UUID()
        ) else {
            return XCTFail("Expected pending cleanup ownership")
        }
        let pendingCleanupWebViewID = ObjectIdentifier(pendingCleanupWebView)
        _ = media.beginVisualHandoffProtection(for: pendingCleanupWebView)
        XCTAssertEqual(
            media.enqueueDeferredCommandIfNeeded(
                .performFallbackWebViewCleanup(
                    webViewID: pendingCleanupWebViewID,
                    lease: pendingCleanupLease
                ),
                for: pendingCleanupWebView,
                reason: "test.global-reset",
                resolveWebView: { registry.webView(with: $0) },
                isCommandValid: { _ in true },
                dropCommand: { _, _, _ in },
                didPruneStaleWebViewIDs: { _ in }
            ),
            .scheduled
        )

        let owner = WebViewWindowCleanupOwner(
            cleanupScopeOwner: scope,
            webViewSessions: registry,
            visibleWebViewRuntimeOwner: visible,
            mediaProtectionOwner: media,
            tabForID: { _ in nil },
            isWebViewProtectedFromCompositorMutation: { _ in false },
            enqueueDeferredProtectedCommand: { _, _, _ in false },
            cleanupUnprotectedTrackedWebView: { _, _, _ in },
            refreshPrimaryTrackedWebView: { _ in },
            removeCompositorContainerView: { removedContainers.append($0) },
            flushDeferredProtectedCommands: { flushedSourceIDs.append($0) },
            finishCleanupSuppression: { _ in finishedSuppression = true }
        )

        let windowID = UUID()
        owner.cleanupWindow(windowID)
        XCTAssertEqual(visible.cancelledWindowIDs, [windowID])
        XCTAssertEqual(removedContainers, [windowID])

        owner.cleanupAllWebViews()
        XCTAssertTrue(visible.didReset)
        XCTAssertEqual(flushedSourceIDs, [pendingCleanupWebViewID])
        XCTAssertFalse(media.isProtected(pendingCleanupWebView))
        XCTAssertTrue(finishedSuppression)
    }
}
