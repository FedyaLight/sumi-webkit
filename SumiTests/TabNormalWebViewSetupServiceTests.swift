import Foundation
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabNormalWebViewSetupServiceTests: XCTestCase {
    func testEnsureUntrackedNormalWebViewAdoptsCompatibleParkedWebView() {
        let graph = makeTestWebViewRuntimeGraph()
        let tab = Tab(
            webViewSessions: graph.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let setup = TabNormalWebViewSetupService()
        setup.attach(
            to: tab,
            installation: graph.untrackedWebViewInstallationService
        )
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        let parkedWebView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        tab.webViewSession.park(parkedWebView)
        var didMakeNormal = false
        let profile = Profile(name: "Ensure Parked Profile")

        let context = TabNormalWebViewRuntimeContext(
            tabId: tab.id,
            currentURL: { URL(string: "https://example.com/parked")! },
            isPopupHost: { false },
            currentWebView: { tab.webViewSession.currentWebView },
            parkedWebView: { tab.webViewSession.parkedWebView },
            profileId: { profile.id },
            resolveProfile: { profile },
            deferWebViewUntilProfileAvailable: { false },
            beginSuspendedRestoreIfNeeded: { /* No-op. */ },
            finishSuspendedRestoreIfNeeded: { /* No-op. */ },
            setupWebView: { _ in /* No-op. */ },
            deferWebsiteDataMutationWebViewMaterialization: { _ in false },
            clearParkedExistingWebView: { /* No-op. */ },
            retireParkedWebView: { _, _ in false },
            cleanupCloneWebView: { _ in /* No-op. */ },
            configurationContext: { .empty },
            configurationRuntime: TabNormalWebViewConfigurationRuntime(
                normalTabWebViewConfiguration: { _, _, _, _ in
                    didMakeNormal = true
                    return Self.preparedConfiguration(for: profile)
                },
                auxiliaryOverrideConfiguration: { _, _ in nil },
                applyWebViewConfigurationOverride: { _, _, _ in /* No-op. */ },
                canReuseAsNormalTabWebView: { webView, _, _, _ in
                    webView === parkedWebView
                }
            ),
            preparationRuntime: TabNormalWebViewPreparationRuntime(
                prepareCreatedFocusableWebView: { _, _, _, _ in /* No-op. */ },
                prepareAssignedWebView: { _ in /* No-op. */ },
                prepareReusedOrExternallyCreatedWebView: { _ in /* No-op. */ },
                applyOwnedWebViewNavPreferences: { _ in /* No-op. */ }
            ),
            normalTabUserScriptsProvider: { _, _ in SumiNormalTabUserScripts() },
            replaceNormalTabUserScripts: { _, _ in /* No-op. */ },
            loadMainFrameRequest: { _, _ in /* No-op. */ },
            applyCachedFaviconOrPlaceholder: { _ in /* No-op. */ },
            registerTabWithExtensionRuntimeIfNeeded: { _ in /* No-op. */ },
            scheduleInitialDocumentRuntimeHandoff: { _, _, _, _ in /* No-op. */ }
        )

        let ensured = setup.ensureUntrackedNormalWebView(
            context: context,
            policyTransaction: tab.configurationPolicyTransaction,
            provisioningOwner: TabWebViewProvisioningOwner(),
            reason: "TabNormalWebViewSetupServiceTests.parkedReuse"
        )

        XCTAssertIdentical(ensured.webView, parkedWebView)
        XCTAssertIdentical(tab.webViewSession.untrackedWebView, parkedWebView)
        XCTAssertNil(tab.webViewSession.parkedWebView)
        XCTAssertEqual(
            graph.webViewSessions.residence(of: parkedWebView),
            .untracked(tabID: tab.id)
        )
        XCTAssertIdentical(graph.runtimeTabs.boundTab(tab.id), tab)
        XCTAssertFalse(didMakeNormal)
    }

    func testRegistrationReentrancyCannotHandoffReplacementWebView() {
        let setup = TabNormalWebViewSetupService()
        let tab = Tab()
        let parkedWebView = WKWebView()
        let replacementWebView = WKWebView()
        let profile = Profile(name: "Registration Reentrancy")
        let policyTransaction = TabConfigurationPolicyTransaction(
            policyLedger: TabConfigurationPolicyLedger(),
            webViewSession: WebViewSessionHandle(tabID: UUID())
        )
        var currentWebView: WKWebView?
        var handoffCount = 0
        var beginRestoreCount = 0
        var finishRestoreCount = 0
        setup.attach(
            to: tab,
            installation: TabNormalWebViewTestInstaller { webView, installedTab in
                XCTAssertIdentical(installedTab, tab)
                currentWebView = webView
                return .committed
            }
        )
        let context = TabNormalWebViewRuntimeContext(
            tabId: tab.id,
            currentURL: { URL(string: "file:///tmp/reentrant.html")! },
            isPopupHost: { false },
            currentWebView: { currentWebView },
            parkedWebView: { parkedWebView },
            profileId: { profile.id },
            resolveProfile: { profile },
            deferWebViewUntilProfileAvailable: { false },
            beginSuspendedRestoreIfNeeded: { beginRestoreCount += 1 },
            finishSuspendedRestoreIfNeeded: { finishRestoreCount += 1 },
            setupWebView: { _ in },
            deferWebsiteDataMutationWebViewMaterialization: { _ in false },
            clearParkedExistingWebView: {},
            retireParkedWebView: { _, _ in false },
            cleanupCloneWebView: { _ in },
            configurationContext: { .empty },
            configurationRuntime: TabNormalWebViewConfigurationRuntime(
                normalTabWebViewConfiguration: { _, _, _, _ in
                    Self.preparedConfiguration(for: profile)
                },
                auxiliaryOverrideConfiguration: { _, _ in nil },
                applyWebViewConfigurationOverride: { _, _, _ in },
                canReuseAsNormalTabWebView: { webView, _, _, _ in
                    webView === parkedWebView
                }
            ),
            preparationRuntime: TabNormalWebViewPreparationRuntime(
                prepareCreatedFocusableWebView: { _, _, _, _ in },
                prepareAssignedWebView: { _ in },
                prepareReusedOrExternallyCreatedWebView: { _ in },
                applyOwnedWebViewNavPreferences: { _ in }
            ),
            normalTabUserScriptsProvider: { _, _ in SumiNormalTabUserScripts() },
            replaceNormalTabUserScripts: { _, _ in },
            loadMainFrameRequest: { _, _ in
                XCTFail("Stale setup must not load a replacement WebView")
            },
            applyCachedFaviconOrPlaceholder: { _ in },
            registerTabWithExtensionRuntimeIfNeeded: { _ in
                currentWebView = replacementWebView
            },
            scheduleInitialDocumentRuntimeHandoff: { _, _, _, _ in
                handoffCount += 1
            }
        )

        let outcome = setup.ensureUntrackedNormalWebView(
            context: context,
            policyTransaction: policyTransaction,
            provisioningOwner: TabWebViewProvisioningOwner(),
            reason: "test.registration-reentrancy"
        )

        guard case .superseded(let current) = outcome else {
            return XCTFail("Reentrant replacement must supersede stale setup")
        }
        XCTAssertIdentical(current, replacementWebView)
        XCTAssertIdentical(currentWebView, replacementWebView)
        XCTAssertEqual(handoffCount, 0)
        XCTAssertEqual(beginRestoreCount, 1)
        XCTAssertEqual(finishRestoreCount, 1)
    }

    func testWebsiteDataMutationDefersPhysicalMaterializationAndRetainsReplay() {
        let setup = TabNormalWebViewSetupService()
        let tab = Tab()
        let profile = Profile(name: "Deferred Materialization")
        var currentWebView: WKWebView?
        var shouldDefer = true
        var retainedReplay: (@MainActor @Sendable () -> Void)?
        let setupReplay = TabNormalWebViewSetupReplayBox()
        var creationCount = 0
        var registrationCount = 0
        let webViewSession = tab.webViewSession
        let policyTransaction = tab.configurationPolicyTransaction
        setup.attach(
            to: tab,
            installation: TabNormalWebViewTestInstaller { webView, installedTab in
                XCTAssertIdentical(installedTab, tab)
                currentWebView = webView
                webViewSession.replaceUntracked(with: webView)
                return .committed
            }
        )
        let context = TabNormalWebViewRuntimeContext(
            tabId: tab.id,
            currentURL: { URL(string: "https://example.com/deferred-materialization")! },
            isPopupHost: { false },
            currentWebView: { webViewSession.currentWebView },
            parkedWebView: { nil },
            profileId: { profile.id },
            resolveProfile: { profile },
            deferWebViewUntilProfileAvailable: { false },
            beginSuspendedRestoreIfNeeded: {},
            finishSuspendedRestoreIfNeeded: {},
            setupWebView: { registerTabWithExtensionRuntime in
                setupReplay.run(registerTabWithExtensionRuntime)
            },
            deferWebsiteDataMutationWebViewMaterialization: { replay in
                guard shouldDefer else { return false }
                retainedReplay = replay
                return true
            },
            clearParkedExistingWebView: {},
            retireParkedWebView: { _, _ in false },
            cleanupCloneWebView: { _ in },
            configurationContext: { .empty },
            configurationRuntime: TabNormalWebViewConfigurationRuntime(
                normalTabWebViewConfiguration: { _, _, _, _ in
                    creationCount += 1
                    return Self.preparedConfiguration(for: profile)
                },
                auxiliaryOverrideConfiguration: { _, _ in nil },
                applyWebViewConfigurationOverride: { _, _, _ in },
                canReuseAsNormalTabWebView: { _, _, _, _ in false }
            ),
            preparationRuntime: TabNormalWebViewPreparationRuntime(
                prepareCreatedFocusableWebView: { _, _, _, _ in },
                prepareAssignedWebView: { _ in },
                prepareReusedOrExternallyCreatedWebView: { _ in },
                applyOwnedWebViewNavPreferences: { _ in }
            ),
            normalTabUserScriptsProvider: { _, _ in SumiNormalTabUserScripts() },
            replaceNormalTabUserScripts: { _, _ in },
            loadMainFrameRequest: { _, _ in },
            applyCachedFaviconOrPlaceholder: { _ in },
            registerTabWithExtensionRuntimeIfNeeded: { _ in
                registrationCount += 1
            },
            scheduleInitialDocumentRuntimeHandoff: { _, _, _, _ in }
        )
        setupReplay.action = { registerTabWithExtensionRuntime in
            _ = setup.ensureUntrackedNormalWebView(
                context: context,
                policyTransaction: policyTransaction,
                provisioningOwner: TabWebViewProvisioningOwner(),
                reason: "TabNormalWebViewSetupServiceTests.replayedMaterialization",
                registerTabWithExtensionRuntime:
                    registerTabWithExtensionRuntime
            )
        }

        let outcome = setup.ensureUntrackedNormalWebView(
            context: context,
            policyTransaction: policyTransaction,
            provisioningOwner: TabWebViewProvisioningOwner(),
            reason: "TabNormalWebViewSetupServiceTests.deferredMaterialization",
            registerTabWithExtensionRuntime: false
        )
        guard case .deferred = outcome else {
            return XCTFail("Expected website-data admission deferral")
        }
        XCTAssertEqual(creationCount, 0)
        XCTAssertNil(currentWebView)

        shouldDefer = false
        retainedReplay?()
        XCTAssertEqual(creationCount, 1)
        XCTAssertEqual(registrationCount, 0)
        XCTAssertNotNil(currentWebView)
    }

    func testInitialNormalTabRuntimeRegistrationDelaysForInitialHTTPDocuments() throws {
        let setup = TabNormalWebViewSetupService()

        XCTAssertTrue(
            setup.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "https://example.com/start"))
            )
        )

        XCTAssertTrue(
            setup.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "http://example.com/start"))
            )
        )
    }

    func testInitialNormalTabRuntimeRegistrationDoesNotDelayForNonInitialNormalDocuments() throws {
        let setup = TabNormalWebViewSetupService()
        let url = try XCTUnwrap(URL(string: "https://example.com/start"))

        XCTAssertFalse(
            setup.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: true,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: url
            )
        )
        XCTAssertFalse(
            setup.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: true,
                didCreateAuxiliaryOverrideWebView: false,
                url: url
            )
        )
        XCTAssertFalse(
            setup.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: true,
                url: url
            )
        )
    }

    func testInitialNormalTabRuntimeRegistrationDoesNotDelayForNonWebURLs() throws {
        let setup = TabNormalWebViewSetupService()

        XCTAssertFalse(
            setup.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: URL(fileURLWithPath: "/tmp/index.html")
            )
        )
        XCTAssertFalse(
            setup.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "webkit-extension://extension-id/options.html"))
            )
        )
    }

    private static func preparedConfiguration(
        for profile: Profile
    ) -> PreparedNormalTabWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile.dataStore
        return PreparedNormalTabWebViewConfiguration(
            configuration: configuration,
            policyState: TabConfigurationPolicyState(
                profileID: profile.id,
                websiteDataStoreIdentity: ObjectIdentifier(
                    configuration.websiteDataStore
                ),
                protectionAttachment: nil,
                safariContentBlockerAttachment: nil,
                autoplayState: .allowAll
            )
        )
    }
}

@MainActor
private final class TabNormalWebViewSetupReplayBox {
    var action: (@MainActor @Sendable (Bool) -> Void)?

    func run(_ registerTabWithExtensionRuntime: Bool) {
        action?(registerTabWithExtensionRuntime)
    }
}

@MainActor
private final class TabNormalWebViewTestInstaller: UntrackedWebViewInstalling {
    private let install: (WKWebView, Tab) -> UntrackedWebViewInstallationOutcome

    init(
        install: @escaping (WKWebView, Tab) -> UntrackedWebViewInstallationOutcome
    ) {
        self.install = install
    }

    func installUntracked(
        _ webView: WKWebView,
        for tab: Tab
    ) -> UntrackedWebViewInstallationOutcome {
        install(webView, tab)
    }
}
