@testable import Sumi
import SumiDomain
import WebKit
import XCTest

@MainActor
final class TabReloadPolicyStateTests: XCTestCase {
    func testSafariReloadStateUsesInjectedPolicyReader() throws {
        let ledger = TabConfigurationPolicyLedger()
        let state = SafariContentBlockerReloadState(
            policyLedger: ledger
        )
        let webView = WKWebView()
        let pageURL = try XCTUnwrap(
            URL(string: "https://example.com/article")
        )
        let desired = SumiSafariContentBlockerAttachmentState(
            siteHost: "example.com",
            isEnabledForSite: true,
            enabledContentBlockerIds: ["blocker"],
            enabledContentBlockerRuleIdentities: ["blocker:fingerprint"]
        )
        let policies = makePolicies(
            safariContentBlockerAttachmentState: { _ in desired }
        )

        XCTAssertTrue(
            state.markRequiredIfNeeded(
                afterChangingPolicyFor: pageURL,
                currentURL: pageURL,
                existingWebView: webView,
                policy: policies.safariContentBlockers
            )
        )
        XCTAssertEqual(
            state.requirement,
            SumiSafariContentBlockerReloadRequirement(
                siteHost: "example.com",
                desiredAttachmentState: desired
            )
        )
    }

    func testProtectionReloadStateUsesSurfaceAndAttachmentReaders() throws {
        let ledger = TabConfigurationPolicyLedger()
        let state = ProtectionReloadState(policyLedger: ledger)
        let webView = WKWebView()
        let pageURL = try XCTUnwrap(
            URL(string: "https://example.com/article")
        )
        let applied = SumiProtectionAttachmentState.disabled(
            siteHost: "example.com",
            requestedLevel: .adblock
        )
        let desired = SumiProtectionAttachmentState(
            siteHost: "example.com",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [.adblockAdsPrivacyNetwork],
            attachedRuleListIdentifiers: ["tracking-rule"],
            activeGenerationId: "generation-1"
        )
        webView.sumiPreparedConfigurationPolicyChange = ledger.prepare(
            TabConfigurationPolicyState(
                profileID: nil,
                websiteDataStoreIdentity: ObjectIdentifier(
                    webView.configuration.websiteDataStore
                ),
                protectionAttachment: applied,
                safariContentBlockerAttachment: nil,
                autoplayState: nil
            ),
            expectedSessionGeneration: 0
        )
        let changeSet = try XCTUnwrap(
            PreparedConfigurationPolicyChangeSet(
                webViews: [webView],
                policyLedger: ledger
            )
        )
        XCTAssertTrue(changeSet.commit(as: .canonicalGeneration))
        let policies = makePolicies(
            protectionAttachmentState: { _ in desired },
            protectionSurfaceHost: { _ in "example.com" }
        )

        XCTAssertTrue(
            state.markRequiredIfNeeded(
                afterChangingPolicyFor: pageURL,
                currentURL: pageURL,
                existingWebView: webView,
                policy: policies.protection
            )
        )
        XCTAssertEqual(
            state.requirement,
            SumiProtectionReloadRequirement(
                siteHost: "example.com",
                desiredAttachmentState: desired
            )
        )
    }

    func testAutoplayReloadStateUsesRuntimeEvaluator() throws {
        let state = AutoplayReloadState()
        let webView = WKWebView()
        let pageURL = try XCTUnwrap(
            URL(string: "https://example.com/video")
        )
        let runtimeRequirement = SumiRuntimePermissionReloadRequirement(
            kind: .rebuild,
            permissionType: .autoplay,
            reason: "test-autoplay-reload",
            currentAutoplayState: .blockAll,
            requestedAutoplayState: .allowAll
        )
        var capturedState: SumiRuntimeAutoplayState?
        weak var capturedWebView: WKWebView?
        let policies = makePolicies(
            autoplayPolicy: { _, _ in .blockAll },
            evaluateAutoplayPolicyChange: {
                requestedState, evaluatedWebView in
                capturedState = requestedState
                capturedWebView = evaluatedWebView
                return .requiresReload(runtimeRequirement)
            }
        )

        XCTAssertTrue(
            state.updateRequirement(
                currentURL: pageURL,
                existingWebView: webView,
                profile: nil,
                policy: policies.autoplay
            )
        )
        XCTAssertEqual(
            capturedState,
            SumiAutoplayPolicy.blockAll.runtimeState
        )
        XCTAssertIdentical(capturedWebView, webView)
        XCTAssertEqual(
            state.requirement,
            SumiAutoplayReloadRequirement(
                desiredPolicy: .blockAll,
                runtimeRequirement: runtimeRequirement
            )
        )
    }

    private func makePolicies(
        safariContentBlockerAttachmentState: @escaping (URL?)
            -> SumiSafariContentBlockerAttachmentState = {
                _ in .disabled(siteHost: nil)
            },
        protectionAttachmentState: @escaping (URL?)
            -> SumiProtectionAttachmentState = {
                _ in .disabled(siteHost: nil)
            },
        protectionSurfaceHost: @escaping (URL?) -> String? = {
            _ in nil
        },
        autoplayPolicy: @escaping (URL?, Profile?)
            -> SumiAutoplayPolicy = { _, _ in .default },
        evaluateAutoplayPolicyChange: @escaping (
            SumiRuntimeAutoplayState,
            WKWebView
        ) -> SumiRuntimePermissionOperationResult = { _, _ in .noOp }
    ) -> TabReloadPolicies {
        TabReloadPolicies(
            safariContentBlockers: SafariPolicyStub(
                attachment: safariContentBlockerAttachmentState
            ),
            protection: ProtectionPolicyStub(
                attachment: protectionAttachmentState,
                host: protectionSurfaceHost
            ),
            autoplay: AutoplayPolicyStub(
                policyResult: autoplayPolicy,
                evaluation: evaluateAutoplayPolicyChange
            )
        )
    }
}

@MainActor
private struct SafariPolicyStub: SafariContentBlockerPolicyReading {
    let attachment: (URL?) -> SumiSafariContentBlockerAttachmentState

    func attachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        attachment(url)
    }
}

@MainActor
private struct ProtectionPolicyStub: ProtectionPolicyReading {
    let attachment: (URL?) -> SumiProtectionAttachmentState
    let host: (URL?) -> String?

    func attachmentState(
        for url: URL?
    ) -> SumiProtectionAttachmentState {
        attachment(url)
    }

    func surfaceHost(for url: URL?) -> String? { host(url) }

}

@MainActor
private struct AutoplayPolicyStub: AutoplayPolicyReading {
    let policyResult: (URL?, Profile?) -> SumiAutoplayPolicy
    let evaluation: (SumiRuntimeAutoplayState, WKWebView)
        -> SumiRuntimePermissionOperationResult

    func policy(
        for url: URL?,
        profile: Profile?
    ) -> SumiAutoplayPolicy {
        policyResult(url, profile)
    }

    func evaluateChange(
        _ requestedState: SumiRuntimeAutoplayState,
        for webView: WKWebView
    ) -> SumiRuntimePermissionOperationResult {
        evaluation(requestedState, webView)
    }
}
