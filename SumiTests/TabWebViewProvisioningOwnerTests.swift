import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewProvisioningOwnerTests: XCTestCase {
    func testOwnedWebViewPreparationUsesInjectedExtensionRuntimeCapability() {
        let targetURL = URL(string: "https://example.com/runtime")!
        let webView = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var capturedWebView: WKWebView?
        var capturedURL: URL?
        var capturedReason: String?
        let owner = TabOwnedWebViewPreparationOwner(
            dependencies: makeOwnedWebViewPreparationDependencies(
                prepareWebViewForExtensionRuntime: { webView, currentURL, reason in
                    capturedWebView = webView
                    capturedURL = currentURL
                    capturedReason = reason
                }
            )
        )

        owner.prepareCreatedFocusableWebView(
            webView,
            currentURL: targetURL,
            reason: "test.extension-runtime"
        )

        XCTAssertIdentical(capturedWebView, webView)
        XCTAssertEqual(capturedURL, targetURL)
        XCTAssertEqual(capturedReason, "test.extension-runtime")
    }

    func testOwnedWebViewPreparationCanSkipExtensionRuntimeCapability() {
        let webView = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var didPrepareExtensionRuntime = false
        let owner = TabOwnedWebViewPreparationOwner(
            dependencies: makeOwnedWebViewPreparationDependencies(
                prepareWebViewForExtensionRuntime: { _, _, _ in
                    didPrepareExtensionRuntime = true
                }
            )
        )

        owner.prepareCreatedFocusableWebView(
            webView,
            currentURL: URL(string: "https://example.com/runtime"),
            reason: "test.extension-runtime",
            prepareExtensionRuntime: false
        )

        XCTAssertFalse(didPrepareExtensionRuntime)
    }

    func testApplyWebViewConfigurationOverrideUsesProfileIdFallbackWhenProfileIsUnresolved() {
        let fallbackProfileId = UUID()
        var preparedProfileId: UUID?
        let owner = TabWebViewProvisioningOwner()

        let stage = makeConfigurationStage(
            applyConfigurationOverride: { _, profileId in
                    preparedProfileId = profileId
            }
        )

        owner.applyWebViewConfigurationOverride(
            WKWebViewConfiguration(),
            profileID: fallbackProfileId,
            stage: stage
        )

        XCTAssertEqual(preparedProfileId, fallbackProfileId)
    }

    func testCreatePopupWebViewUsesAuxiliaryPreparationRuntimeWithoutInstallingOwnership() {
        let owner = TabWebViewProvisioningOwner()
        var capturedOptions: CreatedWebViewPreparationOptions?
        var capturedReason: String?
        let preparation = makePreparationStage(
                prepareCreatedFocusableWebView: { _, _, reason, options in
                    capturedReason = reason
                    capturedOptions = options
                }
        )

        _ = owner.createPopupWebViewFromWebKitConfiguration(
            WKWebViewConfiguration(),
            preparation: preparation,
            currentURL: URL(string: "https://example.com/popup"),
            isExtensionOriginated: true,
            reason: "test.popup"
        )

        XCTAssertEqual(capturedReason, "test.popup")
        XCTAssertEqual(capturedOptions?.installFaviconRuntime, false)
        XCTAssertEqual(capturedOptions?.prepareExtensionRuntime, true)
        XCTAssertEqual(capturedOptions?.enableVisitedLinkRecording, true)
        XCTAssertEqual(capturedOptions?.applyNavigationPreferences, true)
    }

    func testExplicitProfileOwnsConfigurationAndManagedScriptIdentityBeforeCommit() throws {
        let owner = TabWebViewProvisioningOwner()
        let oldProfile = Profile(name: "Old")
        let targetProfile = Profile(name: "Target")
        var configuredProfileID: UUID?
        var managedScriptProfileID: UUID?
        let policyTransaction = makePolicyTransaction()
        let configuration = makeConfigurationStage(
            normalTabUserScriptsProvider: { _, profileID in
                managedScriptProfileID = profileID
                return SumiNormalTabUserScripts()
            },
            prepareNormalConfiguration: { _, profile, _ in
                configuredProfileID = profile.id
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = profile.dataStore
                return configuration
            }
        )

        _ = try XCTUnwrap(
            owner.makeNormalTabWebView(
                request: makeRequest(profile: oldProfile),
                profile: targetProfile,
                configuration: configuration,
                preparation: makePreparationStage(),
                policyTransaction: policyTransaction,
                reason: "test.explicit-profile",
                prepareExtensionRuntime: false
            )
        )

        XCTAssertEqual(configuredProfileID, targetProfile.id)
        XCTAssertEqual(managedScriptProfileID, targetProfile.id)
        XCTAssertNotEqual(managedScriptProfileID, oldProfile.id)
    }

    func testNormalWebViewKeepsExactResolvedProfileDataStore() throws {
        let owner = TabWebViewProvisioningOwner()
        let profile = Profile(name: "Expected")
        let policyLedger = TabConfigurationPolicyLedger()
        let policyTransaction = makePolicyTransaction(
            policyLedger: policyLedger
        )
        let result = try XCTUnwrap(owner.makeNormalTabWebView(
            request: makeRequest(profile: profile),
            profile: profile,
            configuration: makeConfigurationStage(),
            preparation: makePreparationStage(),
            policyTransaction: policyTransaction,
            reason: "test.wrong-data-store",
            prepareExtensionRuntime: false
        ))

        XCTAssertIdentical(
            result.configuration.websiteDataStore,
            profile.dataStore
        )
        XCTAssertNotNil(result.sumiPreparedConfigurationPolicyChange)
        XCTAssertEqual(policyLedger.committedState, .unknown)
        XCTAssertEqual(policyLedger.revision, 0)
    }

    private func makeRequest(profile: Profile?) -> TabNormalWebViewSetupRequest {
        TabNormalWebViewSetupRequest(
            tabID: UUID(),
            targetURL: URL(string: "https://example.com")!,
            isPopupHost: false,
            resolvedProfile: profile
        )
    }

    private func makePolicyTransaction(
        policyLedger: TabConfigurationPolicyLedger =
            TabConfigurationPolicyLedger()
    ) -> TabConfigurationPolicyTransaction {
        TabConfigurationPolicyTransaction(
            policyLedger: policyLedger,
            webViewSession: WebViewSessionHandle(tabID: UUID())
        )
    }

    private func makeConfigurationStage(
        normalTabUserScriptsProvider: @escaping (
            URL?,
            UUID?
        ) -> SumiNormalTabUserScripts = { _, _ in SumiNormalTabUserScripts() },
        prepareNormalConfiguration: @escaping (
            URL,
            Profile,
            SumiNormalTabUserScripts
        ) -> WKWebViewConfiguration = { _, profile, _ in
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = profile.dataStore
            return configuration
        },
        auxiliaryOverrideConfiguration: @escaping (Profile) -> WKWebViewConfiguration? = { _ in nil },
        applyConfigurationOverride: @escaping (
            WKWebViewConfiguration,
            UUID?
        ) -> Void = { _, _ in /* No-op. */ },
        canReuse: @escaping (
            WKWebView,
            URL,
            Profile?
        ) -> Bool = { _, _, _ in false }
    ) -> TabNormalWebViewConfigurationStage {
        TabNormalWebViewConfigurationStage(
            normalTabUserScripts: normalTabUserScriptsProvider,
            prepareNormalConfiguration: { url, profile, scripts in
                let configuration = prepareNormalConfiguration(
                    url,
                    profile,
                    scripts
                )
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
            },
            auxiliaryOverrideConfiguration: auxiliaryOverrideConfiguration,
            prepareForExtensionRuntime: { _, _, _ in /* No-op. */ },
            applyConfigurationOverride: applyConfigurationOverride,
            canReuse: canReuse
        )
    }

    private func makePreparationStage(
        prepareCreatedFocusableWebView: @escaping (
            FocusableWKWebView,
            URL?,
            String,
            CreatedWebViewPreparationOptions
        ) -> Void = { _, _, _, _ in /* No-op. */ },
        prepareAssignedWebView: @escaping (WKWebView) -> Void = { _ in /* No-op. */ },
        prepareReusedOrExternallyCreatedWebView: @escaping (WKWebView) -> Void = { _ in /* No-op. */ },
        applyOwnedWebViewNavPreferences: @escaping (WKWebView) -> Void = { _ in /* No-op. */ }
    ) -> TabNormalWebViewPreparationStage {
        TabNormalWebViewPreparationStage(
            prepareCreatedWebView: prepareCreatedFocusableWebView,
            prepareAssignedWebView: prepareAssignedWebView,
            prepareReusedWebView: prepareReusedOrExternallyCreatedWebView,
            applyNavigationPreferences: applyOwnedWebViewNavPreferences
        )
    }

    private func makeOwnedWebViewPreparationDependencies(
        prepareWebViewForExtensionRuntime: @MainActor @escaping (WKWebView, URL?, String) -> Void = { _, _, _ in /* No-op. */ }
    ) -> TabOwnedWebViewPreparationOwner.Dependencies {
        TabOwnedWebViewPreparationOwner.Dependencies(
            tab: { nil },
            uiDelegate: { nil },
            visitedLinkStore: { nil },
            prepareWebViewForExtensionRuntime: prepareWebViewForExtensionRuntime,
            installNavigationDelegate: { _ in /* No-op. */ },
            setupNavigationStateObservers: { _ in /* No-op. */ },
            bindAudioState: { _ in /* No-op. */ },
            applyRestoredNavigationState: { /* No-op. */ },
            ensureFaviconsTabExtension: { _ in /* No-op. */ }
        )
    }
}
