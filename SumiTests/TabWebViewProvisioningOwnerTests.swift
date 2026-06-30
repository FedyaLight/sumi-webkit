import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewProvisioningOwnerTests: XCTestCase {
    func testApplyWebViewConfigurationOverrideUsesProfileIdFallbackWhenProfileIsUnresolved() {
        let fallbackProfileId = UUID()
        var preparedProfileId: UUID?
        let configurationOwner = TabWebViewConfigurationOwner()
        let owner = TabWebViewProvisioningOwner()

        let context = makeContext(
            profileId: { fallbackProfileId },
            resolveProfile: { nil },
            configurationContext: {
                TabWebViewConfigurationContext(
                    browserConfiguration: .shared,
                    extensionNormalTabUserScripts: { [] },
                    userscriptsNormalTabUserScripts: { _, _, _, _ in [] },
                    boostsNormalTabUserScripts: { _, _, _ in [] },
                    protectionDecision: { _, _ in nil },
                    protectionDesiredAttachmentState: { _ in .disabled(siteHost: nil) },
                    safariContentBlockerAttachmentState: { _ in nil },
                    safariContentBlockerDesiredAttachmentState: { _ in .disabled(siteHost: nil) },
                    enabledSafariContentBlockingServices: { _, _ in [] },
                    prepareWebViewConfigurationForExtensionRuntime: { _, profileId, _ in
                        preparedProfileId = profileId
                    }
                )
            },
            configurationOwner: configurationOwner
        )

        owner.applyWebViewConfigurationOverride(WKWebViewConfiguration(), context: context)

        XCTAssertEqual(preparedProfileId, fallbackProfileId)
    }

    private func makeContext(
        profileId: @escaping () -> UUID?,
        resolveProfile: @escaping () -> Profile?,
        configurationContext: @escaping () -> TabWebViewConfigurationContext,
        configurationOwner: TabWebViewConfigurationOwner
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
            replaceUntrackedWebView: { _ in },
            assignPrimaryWebView: { _, _ in },
            cleanupCloneWebView: { _ in },
            configurationContext: configurationContext,
            webViewConfigurationOwner: configurationOwner,
            ownedWebViewPreparationOwner: makePreparationOwner(),
            reloadPolicyStateOwner: TabReloadPolicyStateOwner(),
            normalTabUserScriptsProvider: { _ in SumiNormalTabUserScripts() },
            replaceNormalTabUserScripts: { _, _ in },
            loadMainFrameRequest: { _, _ in },
            applyCachedFaviconOrPlaceholder: { _ in },
            registerNormalTabWithExtensionRuntimeIfNeeded: { _ in },
            scheduleInitialDocumentRuntimeHandoff: { _, _, _, _, _ in }
        )
    }

    private func makePreparationOwner() -> TabOwnedWebViewPreparationOwner {
        TabOwnedWebViewPreparationOwner(
            dependencies: TabOwnedWebViewPreparationOwner.Dependencies(
                tab: { nil },
                browserManager: { nil },
                uiDelegate: { nil },
                visitedLinkStore: { nil },
                installNavigationDelegate: { _ in },
                setupNavigationStateObservers: { _ in },
                bindAudioState: { _ in },
                applyRestoredNavigationState: {},
                ensureFaviconsTabExtension: { _ in }
            )
        )
    }
}
