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

        let context = makeContext(
            profileId: { fallbackProfileId },
            resolveProfile: { nil },
            configurationRuntime: makeConfigurationRuntime(
                applyWebViewConfigurationOverride: { _, profileId, _ in
                    preparedProfileId = profileId
                }
            )
        )

        owner.applyWebViewConfigurationOverride(WKWebViewConfiguration(), context: context)

        XCTAssertEqual(preparedProfileId, fallbackProfileId)
    }

    func testCreatePopupWebViewUsesAuxiliaryPreparationRuntimeWithoutInstallingOwnership() {
        let owner = TabWebViewProvisioningOwner()
        var capturedOptions: CreatedWebViewPreparationOptions?
        var capturedReason: String?
        var didReplaceWebView = false
        let context = makeContext(
            replaceUntrackedWebView: { _ in didReplaceWebView = true },
            preparationRuntime: makePreparationRuntime(
                prepareCreatedFocusableWebView: { _, _, reason, options in
                    capturedReason = reason
                    capturedOptions = options
                }
            )
        )

        _ = owner.createPopupWebViewFromWebKitConfiguration(
            WKWebViewConfiguration(),
            context: context,
            currentURL: URL(string: "https://example.com/popup"),
            isExtensionOriginated: true,
            reason: "test.popup"
        )

        XCTAssertFalse(
            didReplaceWebView,
            "Phase 6: popup construction must not silently install Tab ownership"
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
        let context = makeContext(
            profileId: { oldProfile.id },
            resolveProfile: { oldProfile },
            configurationRuntime: makeConfigurationRuntime(
                normalTabWebViewConfiguration: { _, profile, _, _ in
                    configuredProfileID = profile.id
                    let configuration = WKWebViewConfiguration()
                    configuration.websiteDataStore = profile.dataStore
                    return configuration
                }
            ),
            normalTabUserScriptsProvider: { _, profileID in
                managedScriptProfileID = profileID
                return SumiNormalTabUserScripts()
            }
        )

        _ = try XCTUnwrap(
            owner.makeNormalTabWebView(
                context: context,
                policyTransaction: policyTransaction,
                reason: "test.explicit-profile",
                explicitProfile: targetProfile,
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
        let context = makeContext(
            resolveProfile: { profile }
        )

        let result = try XCTUnwrap(owner.makeNormalTabWebView(
            context: context,
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

    private func makeContext(
        profileId: @escaping () -> UUID? = { nil },
        resolveProfile: @escaping () -> Profile? = { nil },
        replaceUntrackedWebView: @escaping (WKWebView) -> Void = { _ in /* No-op. */ },
        configurationContext: @escaping () -> TabWebViewConfigurationContext = { .empty },
        configurationRuntime: TabNormalWebViewConfigurationRuntime? = nil,
        preparationRuntime: TabNormalWebViewPreparationRuntime? = nil,
        normalTabUserScriptsProvider: @escaping (
            URL?,
            UUID?
        ) -> SumiNormalTabUserScripts = { _, _ in SumiNormalTabUserScripts() }
    ) -> TabNormalWebViewRuntimeContext {
        return TabNormalWebViewRuntimeContext(
            tabId: UUID(),
            currentURL: { URL(string: "https://example.com")! },
            isPopupHost: { false },
            currentWebView: { nil },
            parkedWebView: { nil },
            profileId: profileId,
            resolveProfile: resolveProfile,
            deferWebViewUntilProfileAvailable: { false },
            beginSuspendedRestoreIfNeeded: { /* No-op. */ },
            finishSuspendedRestoreIfNeeded: { /* No-op. */ },
            setupWebView: { /* No-op. */ },
            deferWebsiteDataMutationWebViewMaterialization: { _ in false },
            adoptParkedWebViewAsCurrent: { _ in /* No-op. */ },
            clearParkedExistingWebView: { /* No-op. */ },
            retireParkedWebView: { _, _ in false },
            replaceUntrackedWebView: replaceUntrackedWebView,
            cleanupCloneWebView: { _ in /* No-op. */ },
            configurationContext: configurationContext,
            configurationRuntime: configurationRuntime ?? makeConfigurationRuntime(),
            preparationRuntime: preparationRuntime ?? makePreparationRuntime(),
            normalTabUserScriptsProvider: normalTabUserScriptsProvider,
            replaceNormalTabUserScripts: { _, _ in /* No-op. */ },
            loadMainFrameRequest: { _, _ in /* No-op. */ },
            applyCachedFaviconOrPlaceholder: { _ in /* No-op. */ },
            registerTabWithExtensionRuntimeIfNeeded: { _ in /* No-op. */ },
            scheduleInitialDocumentRuntimeHandoff: { _, _, _, _ in /* No-op. */ }
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

    private func makeConfigurationRuntime(
        normalTabWebViewConfiguration: @escaping (
            URL,
            Profile,
            SumiNormalTabUserScripts,
            TabWebViewConfigurationContext
        ) -> WKWebViewConfiguration = { _, profile, _, _ in
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = profile.dataStore
            return configuration
        },
        auxiliaryOverrideConfiguration: @escaping (
            Profile,
            TabWebViewConfigurationContext
        ) -> WKWebViewConfiguration? = { _, _ in nil },
        applyWebViewConfigurationOverride: @escaping (
            WKWebViewConfiguration,
            UUID?,
            TabWebViewConfigurationContext
        ) -> Void = { _, _, _ in /* No-op. */ },
        canReuseAsNormalTabWebView: @escaping (
            WKWebView,
            URL,
            Profile?,
            TabWebViewConfigurationContext
        ) -> Bool = { _, _, _, _ in false }
    ) -> TabNormalWebViewConfigurationRuntime {
        TabNormalWebViewConfigurationRuntime(
            normalTabWebViewConfiguration: { url, profile, scripts, context in
                let configuration = normalTabWebViewConfiguration(
                    url,
                    profile,
                    scripts,
                    context
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
            applyWebViewConfigurationOverride: applyWebViewConfigurationOverride,
            canReuseAsNormalTabWebView: canReuseAsNormalTabWebView
        )
    }

    private func makePreparationRuntime(
        prepareCreatedFocusableWebView: @escaping (
            FocusableWKWebView,
            URL?,
            String,
            CreatedWebViewPreparationOptions
        ) -> Void = { _, _, _, _ in /* No-op. */ },
        prepareAssignedWebView: @escaping (WKWebView) -> Void = { _ in /* No-op. */ },
        prepareReusedOrExternallyCreatedWebView: @escaping (WKWebView) -> Void = { _ in /* No-op. */ },
        applyOwnedWebViewNavPreferences: @escaping (WKWebView) -> Void = { _ in /* No-op. */ }
    ) -> TabNormalWebViewPreparationRuntime {
        TabNormalWebViewPreparationRuntime(
            prepareCreatedFocusableWebView: prepareCreatedFocusableWebView,
            prepareAssignedWebView: prepareAssignedWebView,
            prepareReusedOrExternallyCreatedWebView: prepareReusedOrExternallyCreatedWebView,
            applyOwnedWebViewNavPreferences: applyOwnedWebViewNavPreferences
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
