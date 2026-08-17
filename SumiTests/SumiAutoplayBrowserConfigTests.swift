import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAutoplayBrowserConfigTests: XCTestCase {
    func testNoDecisionUsesCurrentDefaultAllowAllFallbackConfiguration() throws {
        let harness = try makeHarness()
        let profile = makeProfile("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        try installTestProfile(profile, in: harness.container)
        let configuration = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, [])
    }

    func testOldUserDefaultsValueDoesNotAffectBrowserFallbackConfiguration() throws {
        let harness = try makeHarness()
        let profile = makeProfile("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        try installTestProfile(profile, in: harness.container)
        UserDefaults.standard.set(
            Data(#"{"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee":{"example.com":"block"}}"#.utf8),
            forKey: "settings.sitePermissionOverrides.autoplay"
        )
        defer {
            UserDefaults.standard.removeObject(forKey: "settings.sitePermissionOverrides.autoplay")
        }

        let configuration = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, [])
    }

    func testStoredAllowAllAppliesAllowAllFallbackConfiguration() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("11111111-1111-1111-1111-111111111111")
        try installTestProfile(profile, in: harness.container)
        let url = URL(string: "https://example.com")!
        try await harness.adapter.setPolicy(.allowAll, for: url, profile: profile)

        let configuration = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: url
        )

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, [])
    }

    func testStoredBlockAudibleAppliesAudioFallbackConfiguration() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("22222222-2222-2222-2222-222222222222")
        try installTestProfile(profile, in: harness.container)
        let url = URL(string: "https://example.com")!
        try await harness.adapter.setPolicy(.blockAudible, for: url, profile: profile)

        let configuration = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: url
        )

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .audio)
    }

    func testStoredBlockAllAppliesAllFallbackConfiguration() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("33333333-3333-3333-3333-333333333333")
        try installTestProfile(profile, in: harness.container)
        let url = URL(string: "https://example.com")!
        try await harness.adapter.setPolicy(.blockAll, for: url, profile: profile)

        let configuration = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: url
        )

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .all)
    }

    func testProfileDecisionDoesNotAffectOtherProfile() async throws {
        let harness = try makeHarness()
        let profileA = makeProfile("44444444-4444-4444-4444-444444444444")
        try installTestProfile(profileA, in: harness.container)
        let profileB = makeProfile("55555555-5555-5555-5555-555555555555")
        try installTestProfile(profileB, in: harness.container)
        let url = URL(string: "https://example.com")!
        try await harness.adapter.setPolicy(.blockAll, for: url, profile: profileA)

        let first = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profileA,
            url: url
        )
        let second = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profileB,
            url: url
        )

        XCTAssertEqual(first.mediaTypesRequiringUserActionForPlayback, .all)
        XCTAssertEqual(second.mediaTypesRequiringUserActionForPlayback, [])
    }

    func testUnknownOriginUsesDefaultFallbackConfiguration() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("66666666-6666-6666-6666-666666666666")
        try installTestProfile(profile, in: harness.container)
        try await harness.adapter.setPolicy(
            .blockAll,
            for: URL(string: "https://example.com"),
            profile: profile
        )

        let configuration = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: nil
        )

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, [])
    }

    func testParkedNormalWebViewCannotBeReusedAfterAutoplayPolicyChanges()
        async throws {
        let harness = try makeHarness()
        let profile = makeProfile("77777777-7777-7777-7777-777777777777")
        try installTestProfile(profile, in: harness.container)
        let url = URL(string: "https://example.com/parked-autoplay")!
        let tabID = UUID()
        let scripts = SumiNormalTabUserScripts(
            managedUserScripts: [SumiTabSuspensionUserScript(tabID: tabID)]
        )
        let physicalConfiguration = harness.browserConfiguration
            .normalTabWebViewConfiguration(
                for: profile,
                url: url,
                autoplayPolicy: .allowAll,
                userScriptsProvider: scripts
            )
        let parkedWebView = WKWebView(
            frame: .zero,
            configuration: physicalConfiguration
        )
        let policyLedger = TabConfigurationPolicyLedger()
        let context = configurationContext(
            browserConfiguration: harness.browserConfiguration
        )
        let configuration = TabWebViewConfigurationOwner()

        XCTAssertTrue(
            configuration.canReuseAsNormalTabWebView(
                parkedWebView,
                fallbackURL: url,
                tabId: tabID,
                profile: profile,
                context: context,
                policyLedger: policyLedger
            )
        )

        try await harness.adapter.setPolicy(
            .blockAll,
            for: url,
            profile: profile
        )

        XCTAssertFalse(
            configuration.canReuseAsNormalTabWebView(
                parkedWebView,
                fallbackURL: url,
                tabId: tabID,
                profile: profile,
                context: context,
                policyLedger: policyLedger
            ),
            "A parked WebView carries immutable configuration-time autoplay policy"
        )
    }

    func testActivePagePolicyChangeReportsRebuildRequired() {
        let controller = SumiRuntimePermissionController()
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)

        let result = controller.evaluateAutoplayPolicyChange(.blockAudible, for: webView)

        guard case .requiresReload(let requirement) = result else {
            return XCTFail("Expected autoplay policy changes to require a rebuild")
        }
        XCTAssertEqual(requirement.kind, .rebuild)
        XCTAssertEqual(requirement.permissionType, .autoplay)
        XCTAssertEqual(requirement.currentAutoplayState, .allowAll)
        XCTAssertEqual(requirement.requestedAutoplayState, .blockAudible)
    }

    private func makeHarness() throws -> (
        container: SumiDatabase,
        adapter: SumiAutoplayPolicyStoreAdapter,
        browserConfiguration: BrowserConfiguration
    ) {
        let container = try SumiDatabase.inMemory()
        let store = DatabasePermissionStore(database: container)
        let adapter = SumiAutoplayPolicyStoreAdapter(persistentStore: store)
        return (container, adapter, BrowserConfiguration(autoplayPolicyStore: adapter))
    }

    private func makeProfile(_ id: String) -> Profile {
        Profile(id: UUID(uuidString: id)!, name: "Profile")
    }

    private func configurationContext(
        browserConfiguration: BrowserConfiguration
    ) -> TabWebViewConfigurationContext {
        TabWebViewConfigurationContext(
            browserConfiguration: browserConfiguration,
            adBlockingNormalTabUserScripts: { _ in [] },
            extensionNormalTabUserScripts: { [] },
            boostsNormalTabUserScripts: { _, _, _ in [] },
            protectionDecision: { _, _ in nil },
            protectionDesiredAttachmentState: {
                .disabled(siteHost: $0?.host)
            },
            safariContentBlockerAttachmentState: { _ in nil },
            safariBlockerDesiredAttachmentState: {
                .disabled(siteHost: $0?.host)
            },
            enabledSafariContentBlockingServices: { _, _ in [] },
            prepareWebViewConfigForExtensionRuntime: { _, _, _ in }
        )
    }
}
