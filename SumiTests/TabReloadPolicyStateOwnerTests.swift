import WebKit
import XCTest
@testable import Sumi

@MainActor
final class TabReloadPolicyStateOwnerTests: XCTestCase {
    func testSafariContentBlockerReloadRequirementUsesInjectedRuntime() throws {
        let owner = TabReloadPolicyStateOwner()
        let webView = WKWebView()
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let desiredState = SumiSafariContentBlockerAttachmentState(
            siteHost: "example.com",
            isEnabledForSite: true,
            enabledContentBlockerIds: ["blocker"],
            enabledContentBlockerRuleIdentities: ["blocker:fingerprint"]
        )
        let runtime = makeRuntime(
            safariContentBlockerAttachmentState: { _ in desiredState }
        )

        XCTAssertTrue(
            owner.markSafariContentBlockerReloadRequiredIfNeeded(
                afterChangingPolicyFor: pageURL,
                currentURL: pageURL,
                existingWebView: webView,
                runtime: runtime
            )
        )
        XCTAssertEqual(
            owner.safariContentBlockerReloadRequirement,
            SumiSafariContentBlockerReloadRequirement(
                siteHost: "example.com",
                desiredAttachmentState: desiredState
            )
        )
    }

    func testProtectionReloadRequirementUsesInjectedRuntimeSurfaceAndAttachmentState() throws {
        let owner = TabReloadPolicyStateOwner()
        let webView = WKWebView()
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let appliedState = SumiProtectionAttachmentState.disabled(
            siteHost: "example.com",
            requestedLevel: .protection
        )
        let desiredState = SumiProtectionAttachmentState(
            siteHost: "example.com",
            requestedLevel: .protection,
            effectiveLevel: .protection,
            activeGroups: [.trackingNetwork],
            attachedRuleListIdentifiers: ["tracking-rule"],
            activeGenerationId: "generation-1"
        )
        owner.noteProtectionAttachmentApplied(appliedState)
        let runtime = makeRuntime(
            protectionAttachmentState: { _ in desiredState },
            protectionSurfaceHost: { _ in "example.com" }
        )

        XCTAssertTrue(
            owner.markProtectionReloadRequiredIfNeeded(
                afterChangingPolicyFor: pageURL,
                currentURL: pageURL,
                existingWebView: webView,
                runtime: runtime
            )
        )
        XCTAssertEqual(
            owner.protectionReloadRequirement,
            SumiProtectionReloadRequirement(
                siteHost: "example.com",
                desiredAttachmentState: desiredState
            )
        )
    }

    func testAutoplayReloadRequirementUsesInjectedRuntimeEvaluator() throws {
        let owner = TabReloadPolicyStateOwner()
        let webView = WKWebView()
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/video"))
        let runtimeRequirement = SumiRuntimePermissionReloadRequirement(
            kind: .rebuild,
            permissionType: .autoplay,
            reason: "test-autoplay-reload",
            currentAutoplayState: .blockAll,
            requestedAutoplayState: .allowAll
        )
        var capturedState: SumiRuntimeAutoplayState?
        weak var capturedWebView: WKWebView?
        let runtime = makeRuntime(
            evaluateAutoplayPolicyChange: { requestedState, webView in
                capturedState = requestedState
                capturedWebView = webView
                return .requiresReload(runtimeRequirement)
            }
        )

        XCTAssertTrue(
            owner.updateAutoplayReloadRequirementForCurrentSite(
                currentURL: pageURL,
                existingWebView: webView,
                profile: nil,
                runtime: runtime
            )
        )
        XCTAssertEqual(capturedState, SumiAutoplayPolicy.default.runtimeState)
        XCTAssertIdentical(capturedWebView, webView)
        XCTAssertEqual(
            owner.autoplayReloadRequirement,
            SumiAutoplayReloadRequirement(
                desiredPolicy: .default,
                runtimeRequirement: runtimeRequirement
            )
        )
    }

    private func makeRuntime(
        safariContentBlockerAttachmentState: @escaping (URL?) -> SumiSafariContentBlockerAttachmentState = { _ in
            .disabled(siteHost: nil)
        },
        protectionAttachmentState: @escaping (URL?) -> SumiProtectionAttachmentState = { _ in
            .disabled(siteHost: nil)
        },
        protectionSurfaceHost: @escaping (URL?) -> String? = { _ in nil },
        protectionCurrentTabDiagnostics: @escaping (
            TabReloadPolicyProtectionDiagnosticsContext
        ) -> SumiProtectionCurrentTabDiagnostics? = { _ in nil },
        evaluateAutoplayPolicyChange: @escaping (
            SumiRuntimeAutoplayState,
            WKWebView
        ) -> SumiRuntimePermissionOperationResult = { _, _ in .noOp }
    ) -> TabReloadPolicyRuntime {
        TabReloadPolicyRuntime(
            safariContentBlockerAttachmentState: safariContentBlockerAttachmentState,
            protectionAttachmentState: protectionAttachmentState,
            protectionSurfaceHost: protectionSurfaceHost,
            protectionCurrentTabDiagnostics: protectionCurrentTabDiagnostics,
            evaluateAutoplayPolicyChange: evaluateAutoplayPolicyChange
        )
    }
}
