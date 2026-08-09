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

        let request = makeRequest(
            tabID: tab.id,
            url: URL(string: "https://example.com/parked")!,
            profile: profile
        )
        let residence = TabNormalWebViewResidenceStage(
            currentWebView: { tab.webViewSession.currentWebView },
            parkedWebView: { tab.webViewSession.parkedWebView },
            clearParkedWebView: { /* No-op. */ },
            retireParkedWebView: { _, _ in false },
            cleanupRejectedWebView: { _ in /* No-op. */ }
        )
        let configurationStage = makeConfigurationStage(
                prepareNormalConfiguration: { _, _, _ in
                    didMakeNormal = true
                    return Self.preparedConfiguration(for: profile)
                },
                canReuse: { webView, _, _ in
                    webView === parkedWebView
                }
        )

        let ensured = setup.ensureUntrackedNormalWebView(
            request: request,
            admission: makeAdmissionStage(),
            residence: residence,
            configuration: configurationStage,
            preparation: makePreparationStage(),
            initialDocument: makeInitialDocumentStage(),
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
        setup.attach(
            to: tab,
            installation: TabNormalWebViewTestInstaller { webView, installedTab in
                XCTAssertIdentical(installedTab, tab)
                currentWebView = webView
                return .committed
            }
        )
        let request = makeRequest(
            tabID: tab.id,
            url: URL(string: "file:///tmp/reentrant.html")!,
            profile: profile
        )
        let residence = TabNormalWebViewResidenceStage(
            currentWebView: { currentWebView },
            parkedWebView: { parkedWebView },
            clearParkedWebView: {},
            retireParkedWebView: { _, _ in false },
            cleanupRejectedWebView: { _ in }
        )
        let configurationStage = makeConfigurationStage(
                prepareNormalConfiguration: { _, _, _ in
                    Self.preparedConfiguration(for: profile)
                },
                canReuse: { webView, _, _ in
                    webView === parkedWebView
                }
        )
        let admission = makeAdmissionStage(
            begin: { beginRestoreCount += 1 }
        )
        let initialDocument = makeInitialDocumentStage(
            loadExtensionOwnedInitialURL: { _, _ in
                XCTFail("Stale setup must not load a replacement WebView")
            },
            registerExtensionRuntime: { _ in
                currentWebView = replacementWebView
            },
            scheduleRuntimeHandoff: { _, _, _, _ in
                handoffCount += 1
            }
        )

        let outcome = setup.ensureUntrackedNormalWebView(
            request: request,
            admission: admission,
            residence: residence,
            configuration: configurationStage,
            preparation: makePreparationStage(),
            initialDocument: initialDocument,
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
        let request = makeRequest(
            tabID: tab.id,
            url: URL(string: "https://example.com/deferred-materialization")!,
            profile: profile
        )
        let residence = TabNormalWebViewResidenceStage(
            currentWebView: { webViewSession.currentWebView },
            parkedWebView: { nil },
            clearParkedWebView: {},
            retireParkedWebView: { _, _ in false },
            cleanupRejectedWebView: { _ in }
        )
        let admission = makeAdmissionStage(
            deferMaterialization: { replay in
                guard shouldDefer else { return false }
                retainedReplay = replay
                return true
            },
            replaySetup: { registerTabWithExtensionRuntime in
                setupReplay.run(registerTabWithExtensionRuntime)
            }
        )
        let configurationStage = makeConfigurationStage(
                prepareNormalConfiguration: { _, _, _ in
                    creationCount += 1
                    return Self.preparedConfiguration(for: profile)
                }
        )
        let initialDocument = makeInitialDocumentStage(
            registerExtensionRuntime: { _ in
                registrationCount += 1
            }
        )
        let preparationStage = makePreparationStage()
        setupReplay.action = { registerTabWithExtensionRuntime in
            _ = setup.ensureUntrackedNormalWebView(
                request: request,
                admission: admission,
                residence: residence,
                configuration: configurationStage,
                preparation: preparationStage,
                initialDocument: initialDocument,
                policyTransaction: policyTransaction,
                provisioningOwner: TabWebViewProvisioningOwner(),
                reason: "TabNormalWebViewSetupServiceTests.replayedMaterialization",
                registerTabWithExtensionRuntime:
                    registerTabWithExtensionRuntime
            )
        }

        let outcome = setup.ensureUntrackedNormalWebView(
            request: request,
            admission: admission,
            residence: residence,
            configuration: configurationStage,
            preparation: preparationStage,
            initialDocument: initialDocument,
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

    func testDeferredInitialLoadCreatesCandidateWithoutNavigationHandoff() {
        let setup = TabNormalWebViewSetupService()
        let tab = Tab()
        let profile = Profile(name: "Process Prewarming")
        var currentWebView: WKWebView?
        var handoffCount = 0
        setup.attach(
            to: tab,
            installation: TabNormalWebViewTestInstaller { webView, installedTab in
                XCTAssertIdentical(installedTab, tab)
                currentWebView = webView
                return .committed
            }
        )

        let outcome = setup.ensureUntrackedNormalWebView(
            request: makeRequest(
                tabID: tab.id,
                url: URL(string: "https://example.com/prewarm")!,
                profile: profile
            ),
            admission: makeAdmissionStage(),
            residence: TabNormalWebViewResidenceStage(
                currentWebView: { currentWebView },
                parkedWebView: { nil },
                clearParkedWebView: {},
                retireParkedWebView: { _, _ in false },
                cleanupRejectedWebView: { _ in }
            ),
            configuration: makeConfigurationStage(
                prepareNormalConfiguration: { _, _, _ in
                    Self.preparedConfiguration(for: profile)
                }
            ),
            preparation: makePreparationStage(),
            initialDocument: makeInitialDocumentStage(
                scheduleRuntimeHandoff: { _, _, _, _ in
                    handoffCount += 1
                }
            ),
            policyTransaction: tab.configurationPolicyTransaction,
            provisioningOwner: TabWebViewProvisioningOwner(),
            reason: "test.process-prewarming",
            initialLoadPolicy: .deferUntilTracked
        )

        XCTAssertNotNil(outcome.webView)
        XCTAssertIdentical(outcome.webView, currentWebView)
        XCTAssertEqual(handoffCount, 0)
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

    private func makeRequest(
        tabID: UUID,
        url: URL,
        profile: Profile
    ) -> TabNormalWebViewSetupRequest {
        TabNormalWebViewSetupRequest(
            tabID: tabID,
            targetURL: url,
            isPopupHost: false,
            resolvedProfile: profile
        )
    }

    private func makeAdmissionStage(
        begin: @escaping () -> Void = {},
        deferMaterialization: @escaping (
            @MainActor @Sendable @escaping () -> Void
        ) -> Bool = { _ in false },
        replaySetup: @MainActor @Sendable @escaping (Bool) -> Void = { _ in }
    ) -> TabNormalWebViewCreationAdmissionStage {
        TabNormalWebViewCreationAdmissionStage(
            deferUntilProfileAvailable: { false },
            beginSuspendedRestore: begin,
            deferMaterialization: deferMaterialization,
            replaySetup: replaySetup
        )
    }

    private func makeConfigurationStage(
        prepareNormalConfiguration: @escaping (
            URL,
            Profile,
            SumiNormalTabUserScripts
        ) -> PreparedNormalTabWebViewConfiguration,
        canReuse: @escaping (WKWebView, URL, Profile?) -> Bool = { _, _, _ in false }
    ) -> TabNormalWebViewConfigurationStage {
        TabNormalWebViewConfigurationStage(
            normalTabUserScripts: { _, _ in SumiNormalTabUserScripts() },
            prepareNormalConfiguration: prepareNormalConfiguration,
            auxiliaryOverrideConfiguration: { _ in nil },
            prepareForExtensionRuntime: { _, _, _ in },
            applyConfigurationOverride: { _, _ in },
            canReuse: canReuse
        )
    }

    private func makePreparationStage() -> TabNormalWebViewPreparationStage {
        TabNormalWebViewPreparationStage(
            prepareCreatedWebView: { _, _, _, _ in },
            prepareAssignedWebView: { _ in },
            prepareReusedWebView: { _ in },
            applyNavigationPreferences: { _ in }
        )
    }

    private func makeInitialDocumentStage(
        loadExtensionOwnedInitialURL: @escaping (WKWebView, URL) -> Void = { _, _ in },
        registerExtensionRuntime: @escaping (String) -> Void = { _ in },
        scheduleRuntimeHandoff: @escaping (WKWebView?, URL, UUID?, String) -> Void = { _, _, _, _ in }
    ) -> TabNormalWebViewInitialDocumentStage {
        TabNormalWebViewInitialDocumentStage(
            replaceNormalTabUserScripts: { _, _ in },
            loadExtensionOwnedInitialURL: loadExtensionOwnedInitialURL,
            registerExtensionRuntime: registerExtensionRuntime,
            scheduleRuntimeHandoff: scheduleRuntimeHandoff
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
