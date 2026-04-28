import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAutoplayBrowserConfigTests: XCTestCase {
    func testNoDecisionUsesCurrentDefaultAllowAllConfiguration() throws {
        let harness = try makeHarness()
        let profile = makeProfile("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let configuration = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, [])
    }

    func testOldUserDefaultsValueDoesNotAffectBrowserConfiguration() throws {
        let harness = try makeHarness()
        let profile = makeProfile("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
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

    func testStoredAllowAllAppliesAllowAllConfiguration() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("11111111-1111-1111-1111-111111111111")
        let url = URL(string: "https://example.com")!
        try await harness.adapter.setPolicy(.allowAll, for: url, profile: profile)

        let configuration = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: url
        )

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, [])
    }

    func testStoredBlockAudibleAppliesAudioConfiguration() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("22222222-2222-2222-2222-222222222222")
        let url = URL(string: "https://example.com")!
        try await harness.adapter.setPolicy(.blockAudible, for: url, profile: profile)

        let configuration = harness.browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: url
        )

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .audio)
    }

    func testStoredBlockAllAppliesAllConfiguration() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("33333333-3333-3333-3333-333333333333")
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
        let profileB = makeProfile("55555555-5555-5555-5555-555555555555")
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

    func testUnknownOriginUsesDefaultConfiguration() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("66666666-6666-6666-6666-666666666666")
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
        container: ModelContainer,
        adapter: SumiAutoplayPolicyStoreAdapter,
        browserConfiguration: BrowserConfiguration
    ) {
        let container = try ModelContainer(
            for: Schema([PermissionDecisionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SwiftDataPermissionStore(container: container)
        let adapter = SumiAutoplayPolicyStoreAdapter(
            modelContainer: container,
            persistentStore: store
        )
        return (container, adapter, BrowserConfiguration(autoplayPolicyStore: adapter))
    }

    private func makeProfile(_ id: String) -> Profile {
        Profile(id: UUID(uuidString: id)!, name: "Profile", icon: "person")
    }
}
