import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabNormalWebViewSetupOwnerTests: XCTestCase {
    func testEnsureUntrackedNormalWebViewAdoptsCompatibleParkedWebView() {
        let owner = TabNormalWebViewSetupOwner()
        let parkedWebView = WKWebView(frame: .zero)
        var current: WKWebView?
        var adopted: WKWebView?
        var didMakeNormal = false
        let profile = Profile(name: "Ensure Parked Profile")

        let context = TabNormalWebViewRuntimeContext(
            tabId: UUID(),
            currentURL: { URL(string: "https://example.com/parked")! },
            isPopupHost: { false },
            currentWebView: { current },
            parkedWebView: { parkedWebView },
            profileId: { profile.id },
            resolveProfile: { profile },
            deferWebViewUntilProfileAvailable: { false },
            beginSuspendedRestoreIfNeeded: { /* No-op. */ },
            finishSuspendedRestoreIfNeeded: { /* No-op. */ },
            setupWebView: { /* No-op. */ },
            deferWebsiteDataMutationWebViewMaterialization: { _ in false },
            adoptParkedWebViewAsCurrent: { webView in
                adopted = webView
                current = webView
            },
            clearParkedExistingWebView: { /* No-op. */ },
            retireParkedWebView: { _, _ in false },
            replaceUntrackedWebView: { webView in
                current = webView
            },
            cleanupCloneWebView: { _ in /* No-op. */ },
            configurationContext: { .empty },
            configurationRuntime: TabNormalWebViewConfigurationRuntime(
                normalTabWebViewConfiguration: { _, _, _, _ in
                    didMakeNormal = true
                    return WKWebViewConfiguration()
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

        let ensured = owner.ensureUntrackedNormalWebView(
            context: context,
            provisioningOwner: TabWebViewProvisioningOwner(),
            reason: "TabNormalWebViewSetupOwnerTests.parkedReuse"
        )

        XCTAssertIdentical(ensured.webView, parkedWebView)
        XCTAssertIdentical(adopted, parkedWebView)
        XCTAssertIdentical(current, parkedWebView)
        XCTAssertFalse(didMakeNormal)
    }

    func testWebsiteDataMutationDefersPhysicalMaterializationAndRetainsReplay() {
        let owner = TabNormalWebViewSetupOwner()
        let profile = Profile(name: "Deferred Materialization")
        var currentWebView: WKWebView?
        var shouldDefer = true
        var retainedReplay: (@MainActor @Sendable () -> Void)?
        let setupReplay = TabNormalWebViewSetupReplayBox()
        var creationCount = 0
        let context = TabNormalWebViewRuntimeContext(
            tabId: UUID(),
            currentURL: { URL(string: "https://example.com/deferred-materialization")! },
            isPopupHost: { false },
            currentWebView: { currentWebView },
            parkedWebView: { nil },
            profileId: { profile.id },
            resolveProfile: { profile },
            deferWebViewUntilProfileAvailable: { false },
            beginSuspendedRestoreIfNeeded: {},
            finishSuspendedRestoreIfNeeded: {},
            setupWebView: { setupReplay.run() },
            deferWebsiteDataMutationWebViewMaterialization: { replay in
                guard shouldDefer else { return false }
                retainedReplay = replay
                return true
            },
            adoptParkedWebViewAsCurrent: { _ in },
            clearParkedExistingWebView: {},
            retireParkedWebView: { _, _ in false },
            replaceUntrackedWebView: { currentWebView = $0 },
            cleanupCloneWebView: { _ in },
            configurationContext: { .empty },
            configurationRuntime: TabNormalWebViewConfigurationRuntime(
                normalTabWebViewConfiguration: { _, _, _, _ in
                    creationCount += 1
                    return WKWebViewConfiguration()
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
            registerTabWithExtensionRuntimeIfNeeded: { _ in },
            scheduleInitialDocumentRuntimeHandoff: { _, _, _, _ in }
        )
        setupReplay.action = {
            _ = owner.ensureUntrackedNormalWebView(
                context: context,
                provisioningOwner: TabWebViewProvisioningOwner(),
                reason: "TabNormalWebViewSetupOwnerTests.replayedMaterialization"
            )
        }

        let outcome = owner.ensureUntrackedNormalWebView(
            context: context,
            provisioningOwner: TabWebViewProvisioningOwner(),
            reason: "TabNormalWebViewSetupOwnerTests.deferredMaterialization"
        )
        guard case .deferred = outcome else {
            return XCTFail("Expected website-data admission deferral")
        }
        XCTAssertEqual(creationCount, 0)
        XCTAssertNil(currentWebView)

        shouldDefer = false
        retainedReplay?()
        XCTAssertEqual(creationCount, 1)
        XCTAssertNotNil(currentWebView)
    }

    func testInitialNormalTabRuntimeRegistrationDelaysForInitialHTTPDocuments() throws {
        let owner = TabNormalWebViewSetupOwner()

        XCTAssertTrue(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "https://example.com/start"))
            )
        )

        XCTAssertTrue(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "http://example.com/start"))
            )
        )
    }

    func testInitialNormalTabRuntimeRegistrationDoesNotDelayForNonInitialNormalDocuments() throws {
        let owner = TabNormalWebViewSetupOwner()
        let url = try XCTUnwrap(URL(string: "https://example.com/start"))

        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: true,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: url
            )
        )
        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: true,
                didCreateAuxiliaryOverrideWebView: false,
                url: url
            )
        )
        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: true,
                url: url
            )
        )
    }

    func testInitialNormalTabRuntimeRegistrationDoesNotDelayForNonWebURLs() throws {
        let owner = TabNormalWebViewSetupOwner()

        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: URL(fileURLWithPath: "/tmp/index.html")
            )
        )
        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "webkit-extension://extension-id/options.html"))
            )
        )
    }
}

@MainActor
private final class TabNormalWebViewSetupReplayBox {
    var action: (@MainActor @Sendable () -> Void)?

    func run() {
        action?()
    }
}
