import CryptoKit
import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserConfigurationNormalTabTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    private func makeUnloadedNormalTabWebView(
        for tab: Tab,
        reason: String
    ) throws -> WKWebView {
        let webView = try XCTUnwrap(tab.makeNormalTabWebView(reason: reason))
        tab._webView = webView
        return webView
    }

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
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

    func testTabNormalWebViewCreationInstallsProtectionCoordinatorPreparedBundleRules() async throws {
        let fixture = try makePreparedProtectionBundleFixture()
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let settings = SumiProtectionSettings(userDefaults: harness.defaults)
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: fixture.manifestStoreRoot)
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            preparedBundleResourceURL: fixture.resourceRoot,
            preparedBundleRemoteRootURL: fixture.remoteRoot,
            preparedBundleGeneratedRootURL: nil,
            ruleListStoreFactory: { isEnabled in
                AdblockWebKitRuleListStore(
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    embeddedBundleURLProvider: { fixture.bundleURL }
                )
            }
        )
        let protectionCoordinator = SumiProtectionCoordinator(
            settings: settings,
            adBlockingModule: adBlockingModule,
            bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore(userDefaults: harness.defaults)
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(container: try Self.makeInMemoryStartupContainer()),
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator
        )
        await waitForStartupProtectionRestore(on: browserManager)
        await waitForInitialTabManagerDataLoad(on: browserManager)

        settings.setLevel(.protection)
        settings.setAppliedLevel(.protection)
        _ = try await protectionCoordinator.restoreAppliedLevelForStartup()

        let profile = try XCTUnwrap(browserManager.currentProfile)
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/protection",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let decision = protectionCoordinator.normalTabDecision(for: tab.url, profileId: profile.id)
        let expectedIdentifiers = Set(fixture.ruleListIdentifiers)

        XCTAssertEqual(Set(decision.plan.expectedRuleListIdentifiers), expectedIdentifiers)
        XCTAssertNotNil(decision.contentBlockingService)

        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.protectionPreparedBundleRules"
        )
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let summary = controller.contentBlockingAssetSummary

        XCTAssertTrue(summary.isInstalled)
        XCTAssertTrue(summary.isContentBlockingFeatureEnabled)
        XCTAssertEqual(summary.globalRuleListCount, expectedIdentifiers.count)
        XCTAssertEqual(summary.updateRuleCount, expectedIdentifiers.count)
        XCTAssertEqual(Set(summary.globalRuleListIdentifiers), expectedIdentifiers)
        XCTAssertEqual(Set(summary.lookupSucceededIdentifiers), expectedIdentifiers)
        XCTAssertEqual(Set(summary.addedToUserContentControllerIdentifiers), expectedIdentifiers)
    }

    func testTabNormalWebViewCreationInstallsProtectionAndSafariContentBlockerRules() async throws {
        let fixture = try makePreparedProtectionBundleFixture()
        let safariContentBlocker = try makeSafariContentBlockerCandidate(
            blockedHost: "safari-content-blocked.example"
        )
        let safariRuleListIdentifiers = Set(
            safariContentBlocker.locatedRules.definitions.map(\.webKitStoreIdentifier)
        )
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(true, for: .extensions)
        let startupContainer = try Self.makeInMemoryStartupContainer()
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: startupContainer.mainContext
        )
        let installedSafariContentBlocker = try await extensionsModule.enableSafariContentBlocker(
            from: safariContentBlocker.candidate
        )
        let settings = SumiProtectionSettings(userDefaults: harness.defaults)
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: fixture.manifestStoreRoot)
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            preparedBundleResourceURL: fixture.resourceRoot,
            preparedBundleRemoteRootURL: fixture.remoteRoot,
            preparedBundleGeneratedRootURL: nil,
            ruleListStoreFactory: { isEnabled in
                AdblockWebKitRuleListStore(
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    embeddedBundleURLProvider: { fixture.bundleURL }
                )
            }
        )
        let protectionCoordinator = SumiProtectionCoordinator(
            settings: settings,
            adBlockingModule: adBlockingModule,
            bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore(userDefaults: harness.defaults)
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(container: startupContainer),
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            extensionsModule: extensionsModule
        )
        await waitForStartupProtectionRestore(on: browserManager)
        await waitForInitialTabManagerDataLoad(on: browserManager)

        settings.setLevel(.protection)
        settings.setAppliedLevel(.protection)
        _ = try await protectionCoordinator.restoreAppliedLevelForStartup()

        let profile = try XCTUnwrap(browserManager.currentProfile)
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/protection-and-safari-content-blocker",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let protectionDecision = protectionCoordinator.normalTabDecision(
            for: tab.url,
            profileId: profile.id
        )
        let protectionRuleListIdentifiers = Set(protectionDecision.plan.expectedRuleListIdentifiers)
        XCTAssertNotNil(protectionDecision.contentBlockingService)

        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.protectionAndSafariContentBlockerRules"
        )
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let summary = controller.contentBlockingAssetSummary
        let expectedIdentifiers = protectionRuleListIdentifiers.union(safariRuleListIdentifiers)

        XCTAssertTrue(summary.isInstalled)
        XCTAssertTrue(summary.isContentBlockingFeatureEnabled)
        XCTAssertEqual(summary.globalRuleListCount, expectedIdentifiers.count)
        XCTAssertEqual(summary.updateRuleCount, expectedIdentifiers.count)
        XCTAssertEqual(Set(summary.globalRuleListIdentifiers), expectedIdentifiers)
        XCTAssertTrue(protectionRuleListIdentifiers.isSubset(of: Set(summary.globalRuleListIdentifiers)))
        XCTAssertTrue(safariRuleListIdentifiers.isSubset(of: Set(summary.globalRuleListIdentifiers)))
        XCTAssertEqual(tab.safariContentBlockerAppliedAttachmentState?.isEnabled, true)
        XCTAssertEqual(
            tab.safariContentBlockerAppliedAttachmentState?.enabledContentBlockerIds,
            [installedSafariContentBlocker.id]
        )
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
        let replacementWebView = try XCTUnwrap(tab.existingWebView)
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
        tab._webView = nil
        tab._existingWebView = originalWebView
        tab.setupWebView()

        let replacementWebView = try XCTUnwrap(tab.existingWebView)
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

    func testWebViewCoordinatorReloadRebuildsForSafariContentBlockerPolicyDrift() async throws {
        let harness = try await makeSafariContentBlockerBrowserHarness(
            blockedHost: "safari-content-blocked.example"
        )
        defer { harness.defaults.reset() }
        let tab = makeAttachedNormalTab(
            in: harness,
            url: "https://example.com/coordinator-safari-content-blocker",
            activate: false
        )
        let originalWebView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.safariContentBlockerCoordinatorInitial"
        )
        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await originalController.waitForContentBlockingAssetsInstalled()

        harness.extensionsModule.setSafariContentBlockerSiteOverride(.disabled, for: tab.url)
        try XCTUnwrap(harness.browserManager.webViewCoordinator).reloadTab(tab)

        let replacementWebView = try XCTUnwrap(tab.existingWebView)
        XCTAssertNotIdentical(replacementWebView, originalWebView)
        let replacementController = try XCTUnwrap(
            replacementWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await replacementController.waitForContentBlockingAssetsInstalled()

        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)
        XCTAssertTrue(
            harness.ruleListIdentifiers.isDisjoint(
                with: Set(replacementController.contentBlockingAssetSummary.globalRuleListIdentifiers)
            )
        )
    }

    func testPrivacyHardReloadRebuildsForSafariContentBlockerPolicyDrift() async throws {
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

        let cleanupService = BrowserConfigurationFakeWebsiteDataCleanupService()
        let privacyService = BrowserPrivacyService(
            cleanupService: cleanupService,
            faviconInvalidator: { _, _ in }
        )
        let activeWindowId = UUID()
        privacyService.hardReloadCurrentPage(
            using: BrowserPrivacyService.Context(
                currentDataStore: {
                    harness.browserManager.currentProfile?.dataStore ?? WKWebsiteDataStore.default()
                },
                currentTab: { tab },
                activeWindowId: { activeWindowId },
                webViewLookup: { tabId, windowId in
                    tabId == tab.id && windowId == activeWindowId ? originalWebView : nil
                }
            )
        )

        let replacementWebView = try XCTUnwrap(tab.existingWebView)
        XCTAssertNotIdentical(replacementWebView, originalWebView)
        let replacementController = try XCTUnwrap(
            replacementWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await replacementController.waitForContentBlockingAssetsInstalled()
        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)
        XCTAssertTrue(
            harness.ruleListIdentifiers.isDisjoint(
                with: Set(replacementController.contentBlockingAssetSummary.globalRuleListIdentifiers)
            )
        )
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
            harness.browserManager.tabManager.allTabs().contains { $0.id == tab.id }
        )
        XCTAssertEqual(tab.safariContentBlockerAppliedAttachmentState?.isEnabled, true)
        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)

        let disabledRecord = try await harness.extensionsModule.setSafariContentBlockerEnabled(
            false,
            bundleIdentifier: harness.installedContentBlocker.extensionBundleIdentifier
        )
        let desiredState = tab.safariContentBlockerDesiredAttachmentState(for: tab.url)

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
        let desiredState = tab.safariContentBlockerDesiredAttachmentState(for: tab.url)

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
        let desiredState = tab.safariContentBlockerDesiredAttachmentState(for: tab.url)

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
        let desiredState = tab.safariContentBlockerDesiredAttachmentState(for: tab.url)

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
        let disabledWebView = try XCTUnwrap(tab.existingWebView)
        XCTAssertNotIdentical(disabledWebView, originalWebView)
        let disabledController = try XCTUnwrap(
            disabledWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await disabledController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(tab.safariContentBlockerAppliedAttachmentState?.isEnabled, false)
        XCTAssertFalse(tab.isSafariContentBlockerReloadRequired)

        harness.extensionsModule.setSafariContentBlockerSiteOverride(.inherit, for: tab.url)
        let desiredState = tab.safariContentBlockerDesiredAttachmentState(for: tab.url)

        XCTAssertTrue(desiredState.isEnabled)
        XCTAssertTrue(tab.isSafariContentBlockerReloadRequired)
        XCTAssertTrue(tab.safariContentBlockerAttachmentRequiresNormalWebViewRebuild(for: tab.url))
    }

    func testSafariContentBlockerEffectiveAttachmentIgnoresHostWhenRuleListsMatch() throws {
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
        XCTAssertTrue(disabledHost.effectiveWebViewContentBlockerRuleIdentities.isEmpty)
    }

    func testBrowserManagerStartupWithUserscriptsDisabledDoesNotInitializeUserscriptsRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabUserscriptsRuntimeProbe()
        let module = makeProbeUserscriptsModule(
            registry: registry,
            probe: probe
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            userscriptsModule: module
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(registry.isEnabled(.userScripts))
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertEqual(probe.injectorCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testBrowserManagerStartupWithExtensionsDisabledDoesNotInitializeExtensionsRuntime() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabExtensionsRuntimeProbe()
        let container = try Self.makeInMemoryExtensionContainer()
        let module = makeProbeExtensionsModule(
            registry: registry,
            probe: probe,
            context: container.mainContext
        )

        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: module
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(registry.isEnabled(.extensions))
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertTrue(browserManager.extensionSurfaceStore.installedExtensions.isEmpty)
    }

    func testTabNormalWebViewCreationWithUserscriptsDisabledDoesNotInitializeUserscriptsRuntime() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabUserscriptsRuntimeProbe()
        let module = makeProbeUserscriptsModule(
            registry: registry,
            probe: probe
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            userscriptsModule: module
        )
        await waitForInitialTabManagerDataLoad(on: browserManager)
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/userscripts-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.userscriptsDisabled"
        )
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(controller.normalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertFalse(sources.contains(UserScriptInjector.userScriptMarker))
        XCTAssertFalse(sources.contains("sumiGM_"))
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertEqual(probe.injectorCount, 0)
    }

    func testTabNormalWebViewCreationWithExtensionsDisabledDoesNotInitializeExtensionsRuntime() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = NormalTabExtensionsRuntimeProbe()
        let container = try Self.makeInMemoryExtensionContainer()
        let module = makeProbeExtensionsModule(
            registry: registry,
            probe: probe,
            context: container.mainContext
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: module
        )
        await waitForInitialTabManagerDataLoad(on: browserManager)
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/extensions-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        let webView = try makeUnloadedNormalTabWebView(
            for: tab,
            reason: "BrowserConfigurationNormalTabTests.extensionsDisabled"
        )
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()
        let provider = try XCTUnwrap(controller.normalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testNormalTabConfigurationCreatesDistinctMarkedControllers() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let first = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://first.example")
        )
        let second = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://second.example")
        )

        XCTAssertNotIdentical(first.userContentController, second.userContentController)
        XCTAssertTrue(first.sumiIsNormalTabWebViewConfiguration)
        XCTAssertTrue(second.sumiIsNormalTabWebViewConfiguration)
    }

    func testNormalTabConfigurationDoesNotCopyTemplateScripts() async throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let templateMarker = "window.__sumiTemplateScriptShouldNotCopy = true;"
        browserConfiguration.webViewConfiguration.userContentController.addUserScript(
            WKUserScript(
                source: templateMarker,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let seedMarker = "window.__sumiManagedProviderScript = true;"
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: [TestNormalTabUserScript(source: seedMarker)]
        )
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com"),
            userScriptsProvider: scriptsProvider
        )

        let controller = try XCTUnwrap(configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()

        let sources = configuration.userContentController.userScripts.map(\.source)
        XCTAssertFalse(sources.contains { $0.contains(templateMarker) })
        XCTAssertEqual(sources.filter { $0.contains(seedMarker) }.count, 1)
    }

    func testEphemeralProfileUsesNonPersistentDataStore() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile.createEphemeral()
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://private.example")
        )

        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertIdentical(configuration.websiteDataStore, profile.dataStore)
    }

    func testNormalTabConfigurationsShareVisitedLinkStoreWithinProfile() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let profile = Profile(name: "Shared Links")

        let first = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://first.example")
        )
        let second = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://second.example")
        )

        let firstStore = try XCTUnwrap(first.sumiVisitedLinkStoreObject)
        let secondStore = try XCTUnwrap(second.sumiVisitedLinkStoreObject)
        XCTAssertIdentical(firstStore, secondStore)
    }

    func testNormalTabConfigurationsSeparateVisitedLinkStoresAcrossProfiles() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let firstProfile = Profile(name: "First")
        let secondProfile = Profile(name: "Second")

        let first = browserConfiguration.normalTabWebViewConfiguration(
            for: firstProfile,
            url: URL(string: "https://first.example")
        )
        let second = browserConfiguration.normalTabWebViewConfiguration(
            for: secondProfile,
            url: URL(string: "https://second.example")
        )

        let firstStore = try XCTUnwrap(first.sumiVisitedLinkStoreObject)
        let secondStore = try XCTUnwrap(second.sumiVisitedLinkStoreObject)
        XCTAssertNotIdentical(firstStore, secondStore)
    }

    func testEphemeralProfilesUseIsolatedVisitedLinkStores() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let persistentProfile = Profile(name: "Persistent")
        let firstEphemeralProfile = Profile.createEphemeral()
        let secondEphemeralProfile = Profile.createEphemeral()

        let persistent = browserConfiguration.normalTabWebViewConfiguration(
            for: persistentProfile,
            url: URL(string: "https://persistent.example")
        )
        let firstEphemeral = browserConfiguration.normalTabWebViewConfiguration(
            for: firstEphemeralProfile,
            url: URL(string: "https://private-a.example")
        )
        let secondEphemeral = browserConfiguration.normalTabWebViewConfiguration(
            for: secondEphemeralProfile,
            url: URL(string: "https://private-b.example")
        )

        let persistentStore = try XCTUnwrap(persistent.sumiVisitedLinkStoreObject)
        let firstEphemeralStore = try XCTUnwrap(firstEphemeral.sumiVisitedLinkStoreObject)
        let secondEphemeralStore = try XCTUnwrap(secondEphemeral.sumiVisitedLinkStoreObject)
        XCTAssertNotIdentical(persistentStore, firstEphemeralStore)
        XCTAssertNotIdentical(firstEphemeralStore, secondEphemeralStore)
    }

    func testProfileAwareAuxiliaryConfigurationCarriesStoreWithoutEnablingRecording() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let profile = Profile(name: "Auxiliary")
        let normal = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://normal.example")
        )
        let auxiliary = browserConfiguration.auxiliaryWebViewConfiguration(
            for: profile,
            surface: .glance
        )

        let normalStore = try XCTUnwrap(normal.sumiVisitedLinkStoreObject)
        let auxiliaryStore = try XCTUnwrap(auxiliary.sumiVisitedLinkStoreObject)
        XCTAssertIdentical(normalStore, auxiliaryStore)

        _ = WKWebView(frame: .zero, configuration: auxiliary)
    }

    func testProfilelessAuxiliaryConfigurationDoesNotReceiveDefaultProfileVisitedLinkStore() throws {
        let provider = SharedVisitedLinkStoreProvider()
        let browserConfiguration = BrowserConfiguration(
            visitedLinkStoreProvider: provider
        )
        let profile = Profile(name: "Default")
        let normal = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://normal.example")
        )
        let auxiliary = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .glance
        )

        XCTAssertFalse(auxiliary.websiteDataStore.isPersistent)
        let normalStore = try XCTUnwrap(normal.sumiVisitedLinkStoreObject)
        let auxiliaryStore = try XCTUnwrap(auxiliary.sumiVisitedLinkStoreObject)
        XCTAssertNotIdentical(normalStore, auxiliaryStore)

        _ = WKWebView(frame: .zero, configuration: auxiliary)
    }

    func testAuxiliaryConfigurationsDoNotInstallTabSuspensionBridge() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        configurations.forEach { configuration in
            assertNoTabSuspensionBridge(in: configuration)
        }
    }

    func testAuxiliaryConfigurationsUsePlainLightweightControllers() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        for configuration in configurations {
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserContentController)
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserScriptsProvider)
            XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
            XCTAssertNil(configuration.webExtensionController)
        }
    }

    func testProfileAwareAuxiliaryConfigurationsPreserveProfileDataStore() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Auxiliary Profile")
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(
                for: profile,
                surface: .glance
            ),
            browserConfiguration.auxiliaryWebViewConfiguration(
                for: profile,
                surface: .extensionOptions
            ),
        ]

        for configuration in configurations {
            XCTAssertIdentical(configuration.websiteDataStore, profile.dataStore)
        }
    }

    func testAuxiliaryExtensionOptionsConfigurationUsesNoContentBlockingInfrastructure() {
        let browserConfiguration = BrowserConfiguration()
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )

        XCTAssertNil(configuration.userContentController.sumiNormalTabUserContentController)
        XCTAssertNil(configuration.userContentController.sumiNormalTabUserScriptsProvider)
        XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
    }

    func testAuxiliaryConfigurationsInstallNoUserscriptRuntimeContributions() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        for configuration in configurations {
            let sources = configuration.userContentController.userScripts
                .map(\.source)
                .joined(separator: "\n")
            XCTAssertFalse(sources.contains(UserScriptInjector.userScriptMarker))
            XCTAssertFalse(sources.contains("SUMI_USER_SCRIPT_RUNTIME"))
            XCTAssertFalse(sources.contains("sumiGM_"))
            XCTAssertFalse(sources.contains("data-sumi-userscript"))
            XCTAssertFalse(sources.contains("sumiLinkInteraction_"))
        }
    }

    func testAuxiliaryConfigurationFiltersNormalTabAndOptionalRuntimeScripts() {
        let browserConfiguration = BrowserConfiguration()
        let sourceConfiguration = WKWebViewConfiguration()
        let allowedScript = WKUserScript(
            source: "window.__sumiExtensionOptionsAllowedScript = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let blockedScripts = [
            "__sumiFaviconTransportInstalled",
            "__sumiTabSuspension",
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
            "SUMI_USER_SCRIPT_RUNTIME",
            UserScriptInjector.userScriptMarker,
            "sumiFavicons",
            "sumiGM_",
            "sumiLinkInteraction_",
            "sumiTabSuspension_",
        ].map { marker in
            WKUserScript(
                source: "/* \(marker) */",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        }

        ([allowedScript] + blockedScripts).forEach {
            sourceConfiguration.userContentController.addUserScript($0)
        }

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            from: sourceConfiguration,
            surface: .extensionOptions,
            additionalUserScripts: sourceConfiguration.userContentController.userScripts
        )
        let sources = configuration.userContentController.userScripts
            .map(\.source)
            .joined(separator: "\n")

        XCTAssertTrue(sources.contains("__sumiExtensionOptionsAllowedScript"))
        XCTAssertEqual(configuration.userContentController.userScripts.count, 1)
        for blockedMarker in [
            "__sumiFaviconTransportInstalled",
            "__sumiTabSuspension",
            SumiTransientChromeInteractionShieldUserScript.sourceMarker,
            "SUMI_USER_SCRIPT_RUNTIME",
            UserScriptInjector.userScriptMarker,
            "sumiFavicons",
            "sumiGM_",
            "sumiLinkInteraction_",
            "sumiTabSuspension_",
        ] {
            XCTAssertFalse(sources.contains(blockedMarker), blockedMarker)
        }
    }

    func testNormalTabConfigurationInstallsCoreScriptProvider() throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let tab = Tab(url: URL(string: "https://example.com/core")!)
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: tab.url,
            userScriptsProvider: tab.normalTabUserScriptsProvider(for: tab.url)
        )

        let provider = try XCTUnwrap(configuration.userContentController.sumiNormalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("__sumiTabSuspension"))

        let linkInteractionScript = try XCTUnwrap(
            provider.userScripts.first { $0.source.contains("sumiLinkInteraction_\(tab.id.uuidString)") }
        )
        let contextMenuScript = try XCTUnwrap(
            provider.userScripts.first { $0.source.contains("sumiWebPageContextMenu_\(tab.id.uuidString)") }
        )
        let notificationScript = try XCTUnwrap(
            provider.userScripts.first { $0.source.contains("sumiWebNotifications_\(tab.id.uuidString)") }
        )

        XCTAssertFalse(linkInteractionScript.requiresRunInPageContentWorld)
        XCTAssertFalse(contextMenuScript.requiresRunInPageContentWorld)
        XCTAssertEqual(linkInteractionScript.injectionTime, .atDocumentEnd)
        XCTAssertEqual(contextMenuScript.injectionTime, .atDocumentEnd)
        XCTAssertTrue(notificationScript.requiresRunInPageContentWorld)
        XCTAssertFalse(
            notificationScript.source.contains("\n            refreshPermission();\n        })();")
        )
        XCTAssertFalse(configuration.userContentController.userScripts.contains { script in
            script.source.contains("_duckduckgoloader_")
        })
    }

    func testTabSuspensionBridgeScriptIsMainFrameOnly() throws {
        let tab = Tab(name: "Bridge")
        let bridgeScript = try XCTUnwrap(
            tab.normalTabCoreUserScripts().first { script in
                script.source.contains("__sumiTabSuspension")
            }
        )

        XCTAssertTrue(bridgeScript.source.contains("sumiTabSuspension_"))
        XCTAssertTrue(bridgeScript.source.contains("tabSuspension"))
        XCTAssertTrue(bridgeScript.forMainFrameOnly)
    }

    private func assertNoTabSuspensionBridge(
        in configuration: WKWebViewConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = configuration.userContentController.userScripts
            .map(\.source)
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("__sumiTabSuspension"), file: file, line: line)
        XCTAssertFalse(source.contains("sumiTabSuspension_"), file: file, line: line)
        XCTAssertFalse(source.contains("tabSuspension"), file: file, line: line)
    }

    private func makeProbeUserscriptsModule(
        registry: SumiModuleRegistry,
        probe: NormalTabUserscriptsRuntimeProbe
    ) -> SumiUserscriptsModule {
        SumiUserscriptsModule(
            moduleRegistry: registry,
            managerFactory: { context in
                probe.managerCount += 1
                return SumiScriptsManager(
                    context: context,
                    storeFactory: { context in
                        probe.storeCount += 1
                        return UserScriptStore(
                            directory: FileManager.default.temporaryDirectory
                                .appendingPathComponent(
                                    "SumiNormalTabUserscripts-\(UUID().uuidString)",
                                    isDirectory: true
                                ),
                            context: context
                        )
                    },
                    injectorFactory: {
                        probe.injectorCount += 1
                        return UserScriptInjector()
                    }
                )
            }
        )
    }

    private func makeProbeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: NormalTabExtensionsRuntimeProbe,
        context: ModelContext
    ) -> SumiExtensionsModule {
        SumiExtensionsModule(
            moduleRegistry: registry,
            context: context,
            managerFactory: { context, initialProfile, browserConfiguration, moduleRegistry in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration,
                    moduleRegistry: moduleRegistry
                )
            }
        )
    }

    @discardableResult
    private func waitForAssets(
        on controller: SumiNormalTabUserContentControlling,
        timeout: TimeInterval = 5,
        where predicate: (SumiNormalTabContentBlockingAssetSummary) -> Bool
    ) async throws -> SumiNormalTabContentBlockingAssetSummary {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let summary = controller.contentBlockingAssetSummary
            if summary.isInstalled, predicate(summary) {
                return summary
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for normal-tab content-blocking assets: \(controller.contentBlockingAssetSummary)")
        return controller.contentBlockingAssetSummary
    }

    @discardableResult
    private func waitForAssets(
        on tab: Tab,
        timeout: TimeInterval = 5,
        where predicate: (SumiNormalTabContentBlockingAssetSummary) -> Bool
    ) async throws -> SumiNormalTabContentBlockingAssetSummary {
        let deadline = Date().addingTimeInterval(timeout)
        var latestSummary: SumiNormalTabContentBlockingAssetSummary?
        while Date() < deadline {
            guard let controller = tab.existingWebView?
                .configuration
                .userContentController
                .sumiNormalTabUserContentController
            else {
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            let summary = controller.contentBlockingAssetSummary
            latestSummary = summary
            if summary.isInstalled, predicate(summary) {
                return summary
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for current-tab content-blocking assets: \(latestSummary.map { String(describing: $0) } ?? "nil")")
        return latestSummary ?? SumiNormalTabContentBlockingAssetSummary(
            isInstalled: false,
            globalRuleListCount: 0,
            updateRuleCount: 0,
            isContentBlockingFeatureEnabled: false,
            globalRuleListIdentifiers: [],
            lookupSucceededIdentifiers: [],
            lookupFailedIdentifiers: [],
            addedToUserContentControllerIdentifiers: [],
            ruleListLookupDuration: nil,
            tabAttachmentDuration: nil
        )
    }

    private func temporaryDirectory(prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makePreparedProtectionBundleFixture() throws -> (
        resourceRoot: URL,
        remoteRoot: URL,
        bundleURL: URL,
        manifestStoreRoot: URL,
        ruleListIdentifiers: [String]
    ) {
        let root = temporaryDirectory(prefix: "SumiNormalTabProtectionBundle")
        let resourceRoot = root.appendingPathComponent("Resources", isDirectory: true)
        let remoteRoot = root.appendingPathComponent("Remote", isDirectory: true)
        let manifestStoreRoot = root.appendingPathComponent("ManifestStore", isDirectory: true)
        let bundleURL = resourceRoot
            .appendingPathComponent("SumiAdblockBundles", isDirectory: true)
            .appendingPathComponent(SumiProtectionBundleProfile.adblock, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifestStoreRoot, withIntermediateDirectories: true)

        let shard = try writePreparedBundleShard(
            bundleURL: bundleURL,
            group: .trackingNetwork,
            relativePath: "tracking/tracking-0001.json"
        )
        let manifest = makePreparedBundleManifest(shards: [shard.shard])
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(
            to: bundleURL.appendingPathComponent(SumiAdblockNativeRuleBundle.manifestFileName),
            options: [.atomic]
        )

        return (
            resourceRoot: resourceRoot,
            remoteRoot: remoteRoot,
            bundleURL: bundleURL,
            manifestStoreRoot: manifestStoreRoot,
            ruleListIdentifiers: [shard.identifier]
        )
    }

    private struct SafariContentBlockerBrowserHarness {
        let defaults: TestDefaultsHarness
        let extensionsModule: SumiExtensionsModule
        let browserManager: BrowserManager
        let installedContentBlocker: InstalledSafariContentBlockerRecord
        let ruleListIdentifiers: Set<String>
    }

    private func makeSafariContentBlockerBrowserHarness(
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
            context: startupContainer.mainContext
        )
        let installedContentBlocker = try await extensionsModule.enableSafariContentBlocker(
            from: safariContentBlocker.candidate
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(container: startupContainer),
            extensionsModule: extensionsModule
        )
        browserManager.webViewCoordinator = WebViewCoordinator()
        await waitForStartupProtectionRestore(on: browserManager)
        await waitForInitialTabManagerDataLoad(on: browserManager)
        return SafariContentBlockerBrowserHarness(
            defaults: defaults,
            extensionsModule: extensionsModule,
            browserManager: browserManager,
            installedContentBlocker: installedContentBlocker,
            ruleListIdentifiers: ruleListIdentifiers
        )
    }

    private func makeAttachedNormalTab(
        in harness: SafariContentBlockerBrowserHarness,
        url: String,
        activate: Bool
    ) -> Tab {
        let tabManager = harness.browserManager.tabManager
        let tab = tabManager.createNewTab(
            url: url,
            in: tabManager.currentSpace,
            activate: activate
        )
        XCTAssertTrue(tabManager.allTabs().contains { $0.id == tab.id })
        return tab
    }

    private func makeSafariContentBlockerCandidate(
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

    private func writePreparedBundleShard(
        bundleURL: URL,
        group: SumiProtectionGroupKind,
        relativePath: String
    ) throws -> (identifier: String, shard: SumiAdblockNativeRuleBundleManifest.Shard) {
        let shardURL = bundleURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: shardURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Self.validPreparedBundleRuleListData(group: group)
        try data.write(to: shardURL, options: [.atomic])
        let identifier = "SumiTestProtection\(group.rawValue)\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        return (
            identifier: identifier,
            shard: SumiAdblockNativeRuleBundleManifest.Shard(
                kind: "network",
                group: group.rawValue,
                logicalGroup: group.rawValue,
                relativePath: relativePath,
                hash: Self.sha256Hex(data),
                byteSize: data.count,
                ruleCount: 1,
                webKitIdentifier: identifier
            )
        )
    }

    private func makePreparedBundleManifest(
        shards: [SumiAdblockNativeRuleBundleManifest.Shard]
    ) -> SumiAdblockNativeRuleBundleManifest {
        SumiAdblockNativeRuleBundleManifest(
            schemaVersion: 1,
            bundleId: "sumi-test-protection-\(UUID().uuidString)",
            generationId: "generation-\(UUID().uuidString)",
            profileId: SumiProtectionBundleProfile.adblock,
            compiler: .init(name: "SumiTests", version: "1"),
            nativeCSSSafetyPolicyVersion: SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion,
            generatedDate: "2026-06-26T00:00:00Z",
            lists: [],
            profileLevelMapping: nil,
            groups: nil,
            shards: shards,
            diagnosticsSummary: .init(
                inputRuleCount: shards.count,
                finalRuleCount: shards.count,
                finalShardCount: shards.count,
                networkRuleCount: shards.count,
                nativeCSSRuleCount: 0,
                unsafeCSSFilteredCount: 0,
                warnings: []
            ),
            unsafeCSSFilteredCount: 0,
            deduplication: .init(
                inputRawRuleCount: shards.count,
                rawDuplicateCountRemoved: 0,
                nativeJSONDuplicateCountRemoved: 0,
                skippedDedupeCount: 0,
                skippedDedupeReasons: [:],
                finalRuleCount: shards.count,
                finalShardCount: shards.count
            )
        )
    }

    private func waitForStartupProtectionRestore(on browserManager: BrowserManager) async {
        for _ in 0..<100 {
            if browserManager.hasFinishedStartupProtectionRestore { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for initial startup protection restore")
    }

    private func waitForInitialTabManagerDataLoad(on browserManager: BrowserManager) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if browserManager.tabManager.hasLoadedInitialData { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for initial tab manager data load")
    }

    private static func makeInMemoryExtensionContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private static func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private static func validPreparedBundleRuleListData(group: SumiProtectionGroupKind) -> Data {
        Data(
            """
            [
              {
                "trigger": {
                  "url-filter": ".*sumi-\(group.rawValue)-blocked\\\\.example/.*"
                },
                "action": {
                  "type": "block"
                }
              }
            ]
            """.utf8
        )
    }

    private static func validSafariContentBlockerRuleListData(blockedHost: String) -> Data {
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

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private final class NormalTabUserscriptsRuntimeProbe {
    var managerCount = 0
    var storeCount = 0
    var injectorCount = 0
}

private final class NormalTabExtensionsRuntimeProbe {
    var managerCount = 0
}

private final class BrowserConfigurationFakeWebsiteDataCleanupService: SumiWebsiteDataCleanupServicing {
    func fetchCookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie] {
        []
    }

    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        []
    }

    func fetchSiteDataEntries(
        forDomain domain: String,
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [SumiSiteDataEntry] {
        []
    }

    func removeCookies(
        _ selection: SumiCookieRemovalSelection,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteData(
        ofTypes dataTypes: Set<String>,
        modifiedSince date: Date,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteDataForDomain(
        _ domain: String,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteDataForExactHost(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteDataForDomains(
        _ domains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func clearAllProfileWebsiteData(in dataStore: WKWebsiteDataStore) async {}

    @discardableResult
    func removePersistentDataStore(forIdentifier identifier: UUID) async -> Bool {
        false
    }

    @discardableResult
    func prunePersistentDataStores(keeping identifiersToKeep: Set<UUID>) async -> [UUID] {
        []
    }
}

private final class TestNormalTabUserScript: NSObject, SumiUserScript {
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
