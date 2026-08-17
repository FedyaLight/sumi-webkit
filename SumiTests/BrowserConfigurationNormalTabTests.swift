import Combine
import CryptoKit
import Foundation
import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserConfigurationNormalTabTests: XCTestCase {
    var temporaryDirectories: [URL] = []

    func makeUnloadedNormalTabWebView(
        for tab: Tab,
        reason: String
    ) throws -> FocusableWKWebView {
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: reason)
                as? FocusableWKWebView
        )
        let admission = try XCTUnwrap(
            tab.configurationPolicyTransaction.preparePlacementAdmission(
                [webView],
                as: .canonicalGeneration
            )
        )
        tab.replaceUntrackedWebView(webView)
        XCTAssertIdentical(tab.resolvedCurrentWebView(), webView)
        XCTAssertTrue(
            tab.configurationPolicyTransaction.commit(admission)
        )
        return webView
    }

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testNormalTabUserContentCleanupTerminatesPendingAssetWait() async {
        let assets = PassthroughSubject<SumiNormalTabUserContent, Never>()
        let source = SumiNormalTabContentBlockingAssetSource(
            assetsPublisher: assets.eraseToAnyPublisher(),
            initialContent: nil,
            privacyConfigurationManager:
                SumiContentBlockingPrivacyConfigurationManager(
                    isContentBlockingEnabled: true
                ),
            retainedContentBlockingServices: []
        )
        let controller = SumiNormalTabUserContentController(
            assetSource: source
        )
        let waitFinished = expectation(description: "asset wait terminated")
        var result: PageNavigationPrerequisiteResult?
        let wait = Task { @MainActor in
            result = await controller.waitForContentBlockingAssetsInstalled()
            waitFinished.fulfill()
        }

        await Task.yield()
        controller.cleanUpBeforeClosing()
        await fulfillment(of: [waitFinished], timeout: 0.1)
        wait.cancel()
        await wait.value
        XCTAssertEqual(result, .cancelled)
    }

    func testContentBlockingAssetWaitReportsFailedAndDegradedSnapshots() async {
        let failed = makePendingAssetController()
        let failedWait = Task { @MainActor in
            await failed.controller.waitForContentBlockingAssetsInstalled()
        }
        await Task.yield()
        failed.assets.send(SumiNormalTabUserContent(
            contentBlockingUpdate: SumiNormalTabContentBlockingUpdate(
                globalRuleLists: [:],
                updateRuleCount: 1,
                lookupSucceededIdentifiers: [],
                lookupFailedIdentifiers: ["required"],
                ruleListLookupDuration: nil
            ),
            sourceProvider: SumiNormalTabUserScripts()
        ))
        let failedResult = await failedWait.value
        XCTAssertEqual(failedResult, .failed)

        let degraded = makePendingAssetController()
        let degradedWait = Task { @MainActor in
            await degraded.controller.waitForContentBlockingAssetsInstalled()
        }
        await Task.yield()
        degraded.assets.send(SumiNormalTabUserContent(
            contentBlockingUpdate: SumiNormalTabContentBlockingUpdate(
                globalRuleLists: [:],
                updateRuleCount: 2,
                lookupSucceededIdentifiers: ["usable"],
                lookupFailedIdentifiers: ["rejected"],
                ruleListLookupDuration: nil
            ),
            sourceProvider: SumiNormalTabUserScripts()
        ))
        let degradedResult = await degradedWait.value
        XCTAssertEqual(degradedResult, .degraded)
    }

    private func makePendingAssetController() -> (
        controller: SumiNormalTabUserContentController,
        assets: PassthroughSubject<SumiNormalTabUserContent, Never>
    ) {
        let assets = PassthroughSubject<SumiNormalTabUserContent, Never>()
        let source = SumiNormalTabContentBlockingAssetSource(
            assetsPublisher: assets.eraseToAnyPublisher(),
            initialContent: nil,
            privacyConfigurationManager:
                SumiContentBlockingPrivacyConfigurationManager(
                    isContentBlockingEnabled: true
                ),
            retainedContentBlockingServices: []
        )
        return (
            SumiNormalTabUserContentController(assetSource: source),
            assets
        )
    }

    func testNormalTabConfigurationUsesSumiNormalTabControllerAndProfileStore() async throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )

        let controller = try XCTUnwrap(configuration.userContentController.sumiNormalTabUserContentController)
        XCTAssertTrue(configuration.sumiIsNormalTabWebViewConfiguration)
        XCTAssertIdentical(configuration.websiteDataStore, profile.dataStore)
        XCTAssertIdentical(controller.wkUserContentController, configuration.userContentController)
        XCTAssertNotNil(controller.normalTabUserScriptsProvider)
        XCTAssertTrue(controller.hasInstalledInitialUserContent)
        XCTAssertFalse(configuration.userContentController.userScripts.isEmpty)
        let appName = configuration.applicationNameForUserAgent
        XCTAssertNotNil(appName)
        XCTAssertTrue(appName?.hasPrefix("Version/") ?? false)
        XCTAssertTrue(appName?.contains(" Safari/") ?? false)
        XCTAssertEqual(
            configuration.preferences.value(forKey: "developerExtrasEnabled") as? Bool,
            RuntimeDiagnostics.isDeveloperInspectionEnabled
        )

        await controller.waitForContentBlockingAssetsInstalled()

        let contentBlockingSummary = controller.contentBlockingAssetSummary
        XCTAssertTrue(contentBlockingSummary.isInstalled)
        XCTAssertFalse(controller.wkUserContentController.userScripts.isEmpty)
        XCTAssertEqual(contentBlockingSummary.globalRuleListCount, 0)
    }

    func testTabWebViewConfigurationContextSuppliesSafariContentBlockerAttachment() throws {
        let owner = TabWebViewConfigurationOwner()
        let profile = Profile(name: "Default")
        let url = try XCTUnwrap(URL(string: "https://example.com/context"))
        let attachmentState = SumiSafariContentBlockerAttachmentState(
            siteHost: "example.com",
            isEnabledForSite: true,
            enabledContentBlockerIds: ["safari-blocker"],
            enabledContentBlockerRuleIdentities: ["safari-blocker:fingerprint"]
        )
        var requestedAttachmentURL: URL?
        var requestedServiceLookup: (url: URL, profileId: UUID)?
        let context = TabWebViewConfigurationContext(
            browserConfiguration: BrowserConfiguration(),
            adBlockingNormalTabUserScripts: { _ in [] },
            extensionNormalTabUserScripts: { [] },
            boostsNormalTabUserScripts: { _, _, _ in [] },
            protectionDecision: { _, _ in nil },
            protectionDesiredAttachmentState: { _ in .disabled(siteHost: nil) },
            safariContentBlockerAttachmentState: { requestedURL in
                requestedAttachmentURL = requestedURL
                return attachmentState
            },
            safariBlockerDesiredAttachmentState: { _ in attachmentState },
            enabledSafariContentBlockingServices: { requestedURL, requestedProfileId in
                requestedServiceLookup = (requestedURL, requestedProfileId)
                return [SumiContentBlockingService(policy: .disabled)]
            },
            prepareWebViewConfigForExtensionRuntime: { _, _, _ in /* No-op. */ }
        )
        let preparedConfiguration = owner.normalTabWebViewConfiguration(
            for: url,
            profile: profile,
            userScriptsProvider: SumiNormalTabUserScripts(),
            context: context
        )

        XCTAssertEqual(requestedAttachmentURL, url)
        XCTAssertEqual(requestedServiceLookup?.url, url)
        XCTAssertEqual(requestedServiceLookup?.profileId, profile.id)
        XCTAssertEqual(
            preparedConfiguration.policyState
                .safariContentBlockerAttachment,
            attachmentState
        )
        XCTAssertNotNil(
            preparedConfiguration.configuration.userContentController
                .sumiNormalTabUserContentController
        )
    }

    func testAdblockPageScriptIsPlannedPerNavigationURL() throws {
        let owner = TabWebViewConfigurationOwner()
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/page"))
        let adblockScript = TestNormalTabUserScript(source: "adblock")
        let extensionScript = TestNormalTabUserScript(source: "extension")
        var requestedURL: URL?
        let context = TabWebViewConfigurationContext(
            browserConfiguration: BrowserConfiguration(),
            adBlockingNormalTabUserScripts: { url in
                requestedURL = url
                return [adblockScript]
            },
            extensionNormalTabUserScripts: { [extensionScript] in
                [extensionScript]
            },
            boostsNormalTabUserScripts: { _, _, _ in [] },
            protectionDecision: { _, _ in nil },
            protectionDesiredAttachmentState: { _ in .disabled(siteHost: nil) },
            safariContentBlockerAttachmentState: { _ in nil },
            safariBlockerDesiredAttachmentState: { _ in .disabled(siteHost: nil) },
            enabledSafariContentBlockingServices: { _, _ in [] },
            prepareWebViewConfigForExtensionRuntime: { _, _, _ in }
        )

        let staticScripts = owner.normalTabStaticManagedUserScripts(
            coreUserScripts: [],
            context: context
        )
        let navigationScripts = owner.normalTabNavigationUserScripts(
            for: targetURL,
            profileIdProvider: { nil },
            context: context,
            isEphemeral: false
        )

        XCTAssertEqual(staticScripts.map(\.source), ["extension"])
        XCTAssertEqual(navigationScripts.map(\.source), ["adblock"])
        XCTAssertEqual(requestedURL, targetURL)
    }

    func testSafariContentBlockerSiteOverrideRebuildsNormalWebViewOnReload() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/safari-content-blocker-toggle",
            activate: false
        )
        let originalWebView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerInitial"
        )
        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await originalController.waitForContentBlockingAssetsInstalled()
        XCTAssertTrue(
            harness.ruleListIdentifiers.isSubset(
                of: Set(originalController.contentBlockingAssetSummary.globalRuleListIdentifiers)
            )
        )

        harness.extensionsModule.setSafariContentBlockerSiteOverride(.disabled, for: tab.url)

        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)
        XCTAssertTrue(tab.safariContentBlockerAttachmentRequiresNormalWebViewRebuild(for: tab.url))

        XCTAssertTrue(
            tab.rebuildNormalWebViewForContentBlockingPolicyIfNeeded(
                targetURL: tab.url,
                reason: "BrowserConfigurationNormalTabTests.safariContentBlockerOverride"
            )
        )
        let replacementWebView = try XCTUnwrap(tab.resolvedCurrentWebView())
        XCTAssertNotIdentical(replacementWebView, originalWebView)
        let replacementController = try XCTUnwrap(
            replacementWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await replacementController.waitForContentBlockingAssetsInstalled()
        let replacementSummary = replacementController.contentBlockingAssetSummary

        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)
        XCTAssertEqual(tab.safariContentBlockerAppliedAttachmentState?.isEnabledForSite, false)
        XCTAssertEqual(
            tab.safariContentBlockerAppliedAttachmentState?.enabledContentBlockerIds,
            [harness.installedContentBlocker.id]
        )
        XCTAssertTrue(
            harness.ruleListIdentifiers.isDisjoint(
                with: Set(replacementSummary.globalRuleListIdentifiers)
            )
        )
    }

    func testReusableExistingNormalWebViewRejectsStaleSafariContentBlockerAttachment() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/reuse-safari-content-blocker",
            activate: false
        )
        let originalWebView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerReuseInitial"
        )
        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await originalController.waitForContentBlockingAssetsInstalled()
        XCTAssertTrue(
            harness.ruleListIdentifiers.isSubset(
                of: Set(originalController.contentBlockingAssetSummary.globalRuleListIdentifiers)
            )
        )

        harness.extensionsModule.setSafariContentBlockerSiteOverride(.disabled, for: tab.url)
        tab.clearCurrentWebViewOwnership()
        tab.parkExistingWebView(originalWebView)
        tab.setupWebView()

        let replacementWebView = try XCTUnwrap(tab.resolvedCurrentWebView())
        XCTAssertNotIdentical(replacementWebView, originalWebView)
        let replacementController = try XCTUnwrap(
            replacementWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await replacementController.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(tab.safariContentBlockerAppliedAttachmentState?.isEnabledForSite, false)
        XCTAssertTrue(
            harness.ruleListIdentifiers.isDisjoint(
                with: Set(replacementController.contentBlockingAssetSummary.globalRuleListIdentifiers)
            )
        )
    }

    func testWebViewRuntimeReloadPreservesGenerationForSafariContentBlockerPolicyDrift() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/runtime-safari-content-blocker",
            activate: false
        )
        let originalWebView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerRuntimeInitial"
        )
        let windowRegistry = harness.windowRegistry
        let currentSpace = try XCTUnwrap(harness.browserManager.spaceStateOwner.currentSpace)
        let windowState = BrowserWindowState()
        windowState.currentProfileId = harness.browserManager.currentProfile?.id
        windowState.currentSpaceId = currentSpace.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        harness.browserManager.webViewRuntime.trackedWebViewAdmission.attemptAssignment(
            originalWebView,
            to: tab,
            in: windowState.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )

        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await originalController.waitForContentBlockingAssetsInstalled()

        harness.extensionsModule.setSafariContentBlockerSiteOverride(.disabled, for: tab.url)
        tab.refresh()

        let retainedWebView = try XCTUnwrap(tab.resolvedCurrentWebView())
        XCTAssertIdentical(retainedWebView, originalWebView)
        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)
        XCTAssertFalse(
            harness.ruleListIdentifiers.isDisjoint(
                with: Set(originalController.contentBlockingAssetSummary.globalRuleListIdentifiers)
            )
        )
    }

    func testPrivacyHardReloadPreservesGenerationForSafariContentBlockerPolicyDrift() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/privacy-hard-reload-safari-content-blocker",
            activate: false
        )
        let originalWebView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerPrivacyInitial"
        )
        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await originalController.waitForContentBlockingAssetsInstalled()

        harness.extensionsModule.setSafariContentBlockerSiteOverride(.disabled, for: tab.url)
        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)

        let cleanupService = BrowserConfigurationWebsiteDataCleanupServiceStub()
        let privacyService = BrowserPrivacyService(
            cleanupService: cleanupService,
            faviconInvalidator: { _, _ in /* No-op. */ }
        )
        let activeWindowId = UUID()
        var reloadRequests: [BrowserConfigurationReloadRequest] = []
        privacyService.hardReloadCurrentPage(
            using: BrowserPrivacyService.Context(
                currentDataStore: {
                    harness.browserManager.currentProfile?.dataStore ?? WKWebsiteDataStore.default()
                },
                currentTab: { tab },
                activeWindowId: { activeWindowId },
                reloadWindowScopedPage: { requestTab, windowId, reason, policy in
                    XCTAssertEqual(policy, .fromOrigin)
                    reloadRequests.append(BrowserConfigurationReloadRequest(
                        tab: requestTab,
                        windowId: windowId,
                        reason: reason
                    ))
                    requestTab.refresh()
                }
            )
        )

        for _ in 0..<100 where reloadRequests.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(reloadRequests.count, 1)
        let reloadRequest = try XCTUnwrap(reloadRequests.first)
        XCTAssertIdentical(reloadRequest.tab, tab)
        XCTAssertEqual(reloadRequest.windowId, activeWindowId)
        XCTAssertEqual(reloadRequest.reason, "BrowserPrivacyService.hardReload")

        let retainedWebView = try XCTUnwrap(tab.resolvedCurrentWebView())
        XCTAssertIdentical(retainedWebView, originalWebView)
        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)
        XCTAssertFalse(
            harness.ruleListIdentifiers.isDisjoint(
                with: Set(originalController.contentBlockingAssetSummary.globalRuleListIdentifiers)
            )
        )
    }

    func testPrivacyHardReloadBypassesOriginWithoutDeletingSiteStorage() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://example.com/original"))
        let tab = Tab(url: originalURL, loadsCachedFaviconOnInit: false)
        let cleanupService = BrowserConfigurationWebsiteDataCleanupServiceStub()
        var reloadCount = 0
        var invalidationCount = 0
        let privacyService = BrowserPrivacyService(
            cleanupService: cleanupService,
            faviconInvalidator: { _, _ in invalidationCount += 1 }
        )
        let windowID = UUID()

        privacyService.hardReloadCurrentPage(
            using: BrowserPrivacyService.Context(
                currentDataStore: { WKWebsiteDataStore.default() },
                currentTab: { tab },
                activeWindowId: { windowID },
                reloadWindowScopedPage: { _, _, _, _ in reloadCount += 1 }
            )
        )

        XCTAssertEqual(reloadCount, 1)
        XCTAssertEqual(invalidationCount, 1)
        XCTAssertTrue(cleanupService.domainRemovalCalls.isEmpty)
    }

    func testSafariContentBlockerGlobalDisableMarksLiveTabsReloadRequired() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/global-disable-safari-content-blocker",
            activate: false
        )
        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerGlobalDisableInitial"
        )
        let controller = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()
        XCTAssertTrue(
            harness.browserManager.tabCollectionMembershipOwner.allTabs().contains { $0.id == tab.id }
        )
        XCTAssertEqual(tab.safariContentBlockerAppliedAttachmentState?.isEnabled, true)
        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)

        let disabledRecord = try await harness.extensionsModule.setSafariContentBlockerEnabled(
            false,
            bundleIdentifier: harness.installedContentBlocker.extensionBundleIdentifier
        )
        let desiredState = tab.safariBlockerDesiredAttachmentState(for: tab.url)

        XCTAssertEqual(disabledRecord?.isEnabled, false)
        XCTAssertFalse(desiredState.isEnabled)
        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)
    }

    func testSafariContentBlockerRuleUpdateMarksLiveTabsReloadRequired() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/updated-safari-content-blocker",
            activate: false
        )
        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerRuleUpdateInitial"
        )
        let controller = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()
        let initialAppliedState = try XCTUnwrap(tab.safariContentBlockerAppliedAttachmentState)
        XCTAssertTrue(initialAppliedState.isEnabled)
        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)

        let updatedContentBlocker = try makeSafariContentBlockerCandidate(
            blockedHost: "updated-safari-content-blocked.example"
        )
        XCTAssertNotEqual(
            updatedContentBlocker.locatedRules.resourceFingerprint,
            harness.installedContentBlocker.resourceFingerprint
        )

        let updatedRecord = try await harness.extensionsModule.enableSafariContentBlocker(
            from: updatedContentBlocker.candidate
        )
        let desiredState = tab.safariBlockerDesiredAttachmentState(for: tab.url)

        XCTAssertEqual(
            updatedRecord.resourceFingerprint,
            updatedContentBlocker.locatedRules.resourceFingerprint
        )
        XCTAssertFalse(initialAppliedState.hasSameEffectiveWebViewAttachment(as: desiredState))
        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)
        XCTAssertTrue(tab.safariContentBlockerAttachmentRequiresNormalWebViewRebuild(for: tab.url))
    }

    func testExtensionsModuleDisableMarksSafariContentBlockerTabsReloadRequired() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/module-disable-safari-content-blocker",
            activate: false
        )
        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerModuleDisableInitial"
        )
        let controller = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(tab.safariContentBlockerAppliedAttachmentState?.isEnabled, true)
        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)

        harness.extensionsModule.setEnabled(false)
        let desiredState = tab.safariBlockerDesiredAttachmentState(for: tab.url)

        XCTAssertFalse(harness.extensionsModule.isEnabled)
        XCTAssertFalse(desiredState.isEnabled)
        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)
    }

    func testExtensionsModuleEnableMarksSafariContentBlockerTabsReloadRequired() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        harness.extensionsModule.setEnabled(false)
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/module-enable-safari-content-blocker",
            activate: false
        )
        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerModuleEnableInitial"
        )
        let controller = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(tab.safariContentBlockerAppliedAttachmentState?.isEnabled, false)
        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)

        harness.extensionsModule.setEnabled(true)
        let desiredState = tab.safariBlockerDesiredAttachmentState(for: tab.url)

        XCTAssertTrue(harness.extensionsModule.isEnabled)
        XCTAssertTrue(desiredState.isEnabled)
        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)
        XCTAssertTrue(tab.safariContentBlockerAttachmentRequiresNormalWebViewRebuild(for: tab.url))
    }

    func testSafariContentBlockerSiteOverrideInheritMarksReloadAfterDisabledRebuild() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/inherit-safari-content-blocker",
            activate: false
        )
        let originalWebView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerInheritInitial"
        )
        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await originalController.waitForContentBlockingAssetsInstalled()

        harness.extensionsModule.setSafariContentBlockerSiteOverride(.disabled, for: tab.url)
        XCTAssertTrue(
            tab.rebuildNormalWebViewForContentBlockingPolicyIfNeeded(
                targetURL: tab.url,
                reason: "BrowserConfigurationNormalTabTests.safariContentBlockerInheritDisabled"
            )
        )
        let disabledWebView = try XCTUnwrap(tab.resolvedCurrentWebView())
        XCTAssertNotIdentical(disabledWebView, originalWebView)
        let disabledController = try XCTUnwrap(
            disabledWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await disabledController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(tab.safariContentBlockerAppliedAttachmentState?.isEnabled, false)
        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)

        harness.extensionsModule.setSafariContentBlockerSiteOverride(.inherit, for: tab.url)
        let desiredState = tab.safariBlockerDesiredAttachmentState(for: tab.url)

        XCTAssertTrue(desiredState.isEnabled)
        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)
        XCTAssertTrue(tab.safariContentBlockerAttachmentRequiresNormalWebViewRebuild(for: tab.url))
    }

    func testSafariContentBlockerEffectiveAttachmentIgnoresHostWhenRuleListsMatch() {
        let firstHost = SumiSafariContentBlockerAttachmentState(
            siteHost: "first.example",
            isEnabledForSite: true,
            enabledContentBlockerIds: ["blocker-b", "blocker-a"],
            enabledContentBlockerRuleIdentities: ["blocker-b:fingerprint-b", "blocker-a:fingerprint-a"]
        )
        let secondHost = SumiSafariContentBlockerAttachmentState(
            siteHost: "second.example",
            isEnabledForSite: true,
            enabledContentBlockerIds: ["blocker-a", "blocker-b"],
            enabledContentBlockerRuleIdentities: ["blocker-a:fingerprint-a", "blocker-b:fingerprint-b"]
        )
        let disabledHost = SumiSafariContentBlockerAttachmentState(
            siteHost: "second.example",
            isEnabledForSite: false,
            enabledContentBlockerIds: ["blocker-a", "blocker-b"],
            enabledContentBlockerRuleIdentities: ["blocker-a:fingerprint-a", "blocker-b:fingerprint-b"]
        )
        let updatedRules = SumiSafariContentBlockerAttachmentState(
            siteHost: "first.example",
            isEnabledForSite: true,
            enabledContentBlockerIds: ["blocker-b", "blocker-a"],
            enabledContentBlockerRuleIdentities: ["blocker-b:fingerprint-b", "blocker-a:fingerprint-c"]
        )

        XCTAssertTrue(firstHost.hasSameEffectiveWebViewAttachment(as: secondHost))
        XCTAssertFalse(firstHost.hasSameEffectiveWebViewAttachment(as: disabledHost))
        XCTAssertFalse(firstHost.hasSameEffectiveWebViewAttachment(as: updatedRules))
        XCTAssertTrue(disabledHost.effectiveWebViewRuleIdentities.isEmpty)
    }

    func assertNoTabSuspensionBridge(
        in configuration: WKWebViewConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = configuration.userContentController.userScripts
            .map(\.source)
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("__sumiTabSuspension"), file: file, line: line)
        XCTAssertFalse(
            source.contains("__sumiDocumentSuspensionSensor"),
            file: file,
            line: line
        )
        XCTAssertFalse(
            source.contains("__sumiSubframePictureInPicture"),
            file: file,
            line: line
        )
        XCTAssertFalse(source.contains("sumiTabSuspension"), file: file, line: line)
        XCTAssertFalse(source.contains("tabSuspension"), file: file, line: line)
    }

    func makeProbeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: NormalTabExtensionsRuntimeProbe,
        context: SumiDatabase
    ) -> SumiExtensionsModule {
        SumiExtensionsModule(
            moduleRegistry: registry,
            database: context,
            managerFactory: { context, initialProfile, browserConfiguration, moduleRegistry in
                probe.managerCount += 1
                return ExtensionManager(
            database: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration,
                    moduleRegistry: moduleRegistry
                )
            }
        )
    }

    func makeProbeBoostsModule(
        registry: SumiModuleRegistry,
        probe: NormalTabBoostsRuntimeProbe
    ) -> SumiBoostsModule {
        SumiBoostsModule(
            moduleRegistry: registry,
            storeFactory: {
                probe.storeCount += 1
                return SumiBoostStore(
                    rootDirectory: self.temporaryDirectory(prefix: "SumiNormalTabBoosts")
                )
            }
        )
    }

    func waitForWebViewURL(
        _ webView: WKWebView,
        toEqual expectedURL: URL,
        timeout: TimeInterval = 5
    ) async {
        let didPublishExpectedURL = expectation(
            description: "WebView publishes expected URL"
        )
        let observation = webView.publisher(
            for: \.url,
            options: [.initial, .new]
        ).sink { url in
            if url == expectedURL {
                didPublishExpectedURL.fulfill()
            }
        }
        await fulfillment(of: [didPublishExpectedURL], timeout: timeout)
        withExtendedLifetime(observation) {}
    }

    func temporaryDirectory(prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    struct SafariContentBlockerBrowserHarness {
        let defaults: TestDefaultsHarness
        let extensionsModule: SumiExtensionsModule
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let installedContentBlocker: InstalledSafariContentBlockerRecord
        let ruleListIdentifiers: Set<String>
    }

    func makeSafariContentBlockerBrowserHarness(
        blockedHost: String
    ) async throws -> SafariContentBlockerBrowserHarness {
        let safariContentBlocker = try makeSafariContentBlockerCandidate(
            blockedHost: blockedHost
        )
        let ruleListIdentifiers = Set(
            safariContentBlocker.locatedRules.definitions.map(\.webKitStoreIdentifier)
        )
        let defaults = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults.defaults)
        )
        registry.setEnabled(true, for: .extensions)
        let startupContainer = try Self.makeInMemoryStartupContainer()
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: startupContainer
        )
        let installedContentBlocker = try await extensionsModule.enableSafariContentBlocker(
            from: safariContentBlocker.candidate
        )
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            moduleRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: startupContainer),
            extensionsModule: extensionsModule
        )
        await startAndWaitForStartupProtectionRestore(on: browserManager)
        markIsolatedTabManagerReady(browserManager)
        return SafariContentBlockerBrowserHarness(
            defaults: defaults,
            extensionsModule: extensionsModule,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            installedContentBlocker: installedContentBlocker,
            ruleListIdentifiers: ruleListIdentifiers
        )
    }

    func makeAttachedNormalTab(
        in harness: SafariContentBlockerBrowserHarness,
        url: String,
        activate: Bool
    ) -> Tab {
        let tabManager = harness.browserManager
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: url,
            in: tabManager.spaceStateOwner.currentSpace,
            activate: activate
        )
        XCTAssertTrue(tabManager.tabCollectionMembershipOwner.allTabs().contains { $0.id == tab.id })
        return tab
    }

    func makeSafariContentBlockerCandidate(
        blockedHost: String
    ) throws -> (
        candidate: DiscoveredSafariExtensionCandidate,
        locatedRules: SafariContentBlockerLocatedRules
    ) {
        let appURL = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: temporaryDirectory(prefix: "SumiNormalTabSafariContentBlocker"),
            appName: "SafariContentBlocker",
            appBundleIdentifier: "com.example.sumi.normal-tab-content-blocker.app",
            extensions: [
                .init(
                    name: "Content Blocker",
                    bundleIdentifier: "com.example.sumi.normal-tab-content-blocker",
                    displayName: "Content Blocker",
                    extensionPointIdentifier: SafariExtensionScanner.safariContentBlockerExtensionPointIdentifier,
                    includeManifest: false,
                    includeExtensionAttributes: false,
                    resourceFiles: [
                        .init(
                            relativePath: "blockerList.json",
                            data: Self.validSafariContentBlockerRuleListData(blockedHost: blockedHost)
                        ),
                    ]
                ),
            ]
        )
        var issues: [SafariExtensionScannerIssue] = []
        let candidate = try XCTUnwrap(
            SafariExtensionScanner()
                .inspectContainingAppBundle(at: appURL, issues: &issues)
                .first
        )
        XCTAssertTrue(issues.isEmpty)
        return (
            candidate: candidate,
            locatedRules: try SafariContentBlockerRuleLocator.locateRules(in: candidate)
        )
    }

    func startAndWaitForStartupProtectionRestore(
        on browserManager: BrowserManager
    ) async {
        browserManager.startRuntimeAfterStartupRecovery()
        await browserManager.startupProtectionRuntime
            .drainProtectionRestoreTaskForTests()
    }

    func markIsolatedTabManagerReady(_ browserManager: BrowserManager) {
        XCTAssertFalse(
            browserManager.startupRestoreLifecycle.didStartPersistedStateLoad,
            "Isolated configuration tests must not race a real restore task"
        )
        browserManager.startupRestoreLifecycle.markLoadFinished()
    }

    static func makeInMemoryExtensionContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }

    static func makeInMemoryStartupContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }

    static func validSafariContentBlockerRuleListData(blockedHost: String) -> Data {
        Data(
            """
            [
              {
                "action": { "type": "block" },
                "trigger": { "url-filter": ".*", "if-domain": ["\(blockedHost)"] }
              }
            ]
            """.utf8
        )
    }
}

struct BrowserConfigurationReloadRequest {
    let tab: Tab
    let windowId: UUID
    let reason: String
}

final class NormalTabExtensionsRuntimeProbe {
    var managerCount = 0
}

final class NormalTabBoostsRuntimeProbe {
    var storeCount = 0
}

final class BrowserConfigurationWebsiteDataCleanupServiceStub: SumiWebsiteDataCleanupServicing {
    let domainRemovalDelayNanoseconds: UInt64
    private(set) var domainRemovalCalls: [(domain: String, includingCookies: Bool)] = []

    init(domainRemovalDelayNanoseconds: UInt64 = 0) {
        self.domainRemovalDelayNanoseconds = domainRemovalDelayNanoseconds
    }

    func fetchCookies(in _: WKWebsiteDataStore) async -> [HTTPCookie] {
        []
    }

    func fetchWebsiteDataRecords(
        ofTypes _: Set<String>,
        in _: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        []
    }

    func fetchSiteDataEntries(
        forDomain _: String,
        ofTypes _: Set<String>,
        in _: WKWebsiteDataStore
    ) async -> [SumiSiteDataEntry] {
        []
    }

    func removeCookies(
        _ _: SumiCookieRemovalSelection,
        in _: WKWebsiteDataStore
    ) async { /* No-op. */ }

    func removeWebsiteData(
        ofTypes _: Set<String>,
        modifiedSince _: Date,
        in _: WKWebsiteDataStore
    ) async { /* No-op. */ }

    func removeWebsiteDataForDomain(
        _ domain: String,
        includingCookies: Bool,
        in _: WKWebsiteDataStore
    ) async {
        domainRemovalCalls.append((domain, includingCookies))
        guard domainRemovalDelayNanoseconds > 0 else { return }
        do {
            try await Task.sleep(nanoseconds: domainRemovalDelayNanoseconds)
        } catch {
            return
        }
    }

    func removeWebsiteDataForExactHost(
        _ _: String,
        ofTypes _: Set<String>,
        includingCookies _: Bool,
        in _: WKWebsiteDataStore
    ) async { /* No-op. */ }

    func removeWebsiteDataForDomains(
        _ _: Set<String>,
        ofTypes _: Set<String>,
        includingCookies _: Bool,
        in _: WKWebsiteDataStore
    ) async { /* No-op. */ }

    func clearAllProfileWebsiteData(in _: WKWebsiteDataStore) async { /* No-op. */ }

    @discardableResult
    func removePersistentDataStore(forIdentifier _: UUID) async -> Bool {
        false
    }

    @discardableResult
    func prunePersistentDataStores(keeping _: Set<UUID>) async -> [UUID] {
        []
    }
}

final class TestNormalTabUserScript: NSObject, SumiPageScript {
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = false
    let messageNames: [String] = []

    init(source: String) {
        self.source = source
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}
