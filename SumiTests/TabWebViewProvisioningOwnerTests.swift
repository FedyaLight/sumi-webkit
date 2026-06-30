import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewProvisioningOwnerTests: XCTestCase {
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

    func testCreatePopupWebViewUsesAuxiliaryPreparationRuntime() {
        let owner = TabWebViewProvisioningOwner()
        var capturedOptions: TabCreatedFocusableWebViewPreparationOptions?
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

        XCTAssertTrue(didReplaceWebView)
        XCTAssertEqual(capturedReason, "test.popup")
        XCTAssertEqual(capturedOptions?.installFaviconRuntime, false)
        XCTAssertEqual(capturedOptions?.prepareExtensionRuntime, true)
        XCTAssertEqual(capturedOptions?.enableVisitedLinkRecording, true)
        XCTAssertEqual(capturedOptions?.applyNavigationPreferences, true)
    }

    private func makeContext(
        profileId: @escaping () -> UUID? = { nil },
        resolveProfile: @escaping () -> Profile? = { nil },
        replaceUntrackedWebView: @escaping (WKWebView) -> Void = { _ in },
        configurationContext: @escaping () -> TabWebViewConfigurationContext = { .empty },
        configurationRuntime: TabNormalWebViewConfigurationRuntime? = nil,
        preparationRuntime: TabNormalWebViewPreparationRuntime? = nil
    ) -> TabNormalWebViewRuntimeContext {
        TabNormalWebViewRuntimeContext(
            tabId: UUID(),
            currentURL: { URL(string: "https://example.com")! },
            isPopupHost: { false },
            currentWebView: { nil },
            parkedWebView: { nil },
            profileId: profileId,
            resolveProfile: resolveProfile,
            deferWebViewCreationUntilProfileAvailable: {},
            beginSuspendedRestoreIfNeeded: {},
            finishSuspendedRestoreIfNeeded: {},
            setupWebView: {},
            adoptParkedWebViewAsCurrent: { _ in },
            clearParkedExistingWebView: {},
            replaceUntrackedWebView: replaceUntrackedWebView,
            assignPrimaryWebView: { _, _ in },
            cleanupCloneWebView: { _ in },
            configurationContext: configurationContext,
            configurationRuntime: configurationRuntime ?? makeConfigurationRuntime(),
            preparationRuntime: preparationRuntime ?? makePreparationRuntime(),
            normalTabUserScriptsProvider: { _ in SumiNormalTabUserScripts() },
            replaceNormalTabUserScripts: { _, _ in },
            loadMainFrameRequest: { _, _ in },
            applyCachedFaviconOrPlaceholder: { _ in },
            registerNormalTabWithExtensionRuntimeIfNeeded: { _ in },
            scheduleInitialDocumentRuntimeHandoff: { _, _, _, _, _ in }
        )
    }

    private func makeConfigurationRuntime(
        normalTabWebViewConfiguration: @escaping (
            URL,
            Profile,
            SumiNormalTabUserScripts,
            TabWebViewConfigurationContext
        ) -> WKWebViewConfiguration = { _, _, _, _ in WKWebViewConfiguration() },
        auxiliaryOverrideConfiguration: @escaping (
            Profile,
            TabWebViewConfigurationContext
        ) -> WKWebViewConfiguration? = { _, _ in nil },
        applyWebViewConfigurationOverride: @escaping (
            WKWebViewConfiguration,
            UUID?,
            TabWebViewConfigurationContext
        ) -> Void = { _, _, _ in },
        canReuseAsNormalTabWebView: @escaping (
            WKWebView,
            URL,
            Profile?,
            TabWebViewConfigurationContext
        ) -> Bool = { _, _, _, _ in false }
    ) -> TabNormalWebViewConfigurationRuntime {
        TabNormalWebViewConfigurationRuntime(
            normalTabWebViewConfiguration: normalTabWebViewConfiguration,
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
            TabCreatedFocusableWebViewPreparationOptions
        ) -> Void = { _, _, _, _ in },
        prepareAssignedWebView: @escaping (WKWebView) -> Void = { _ in },
        prepareReusedOrExternallyCreatedWebView: @escaping (WKWebView) -> Void = { _ in },
        applyOwnedTabWebViewNavigationPreferences: @escaping (WKWebView) -> Void = { _ in }
    ) -> TabNormalWebViewPreparationRuntime {
        TabNormalWebViewPreparationRuntime(
            prepareCreatedFocusableWebView: prepareCreatedFocusableWebView,
            prepareAssignedWebView: prepareAssignedWebView,
            prepareReusedOrExternallyCreatedWebView: prepareReusedOrExternallyCreatedWebView,
            applyOwnedTabWebViewNavigationPreferences: applyOwnedTabWebViewNavigationPreferences
        )
    }
}
