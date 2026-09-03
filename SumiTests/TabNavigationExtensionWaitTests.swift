import Foundation
import WebKit
import XCTest

@testable import Sumi

/// Ordinary main-frame navigations must wait for the profile's content-script
/// contexts before submitting `load()`: WebKit injects `document_start` /
/// `document_end` scripts from the contexts loaded when navigation starts, and
/// a context that finishes mid-document misses the early hooks the page
/// already ran. For userscript-manager extensions this surfaces as a rendered
/// but hung action (e.g. a Translate button stuck in its loading state).
@MainActor
final class TabNavigationExtensionWaitTests: XCTestCase {
    func testExtensionContextWaitDelaysMainFrameLoadUntilContextsReady() async throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/extension-gated"))
        let fixture = ExtensionGatedNavigationFixture(url: targetURL)
        var didLoad = false

        fixture.tab.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: fixture.webView,
            waitForContentBlockingAssets: false
        ) { resolvedWebView, _ in
            XCTAssertIdentical(resolvedWebView, fixture.webView)
            didLoad = true
            return resolvedWebView.loadHTMLString("", baseURL: nil)
        }

        for _ in 0..<50 where fixture.recorded.ids.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(fixture.recorded.ids, [fixture.profile.id])
        XCTAssertFalse(didLoad)

        await fixture.gate.open()

        for _ in 0..<50 where !didLoad {
            await Task.yield()
        }

        XCTAssertTrue(didLoad)
    }

    func testExtensionContextWaitSkippedForNonInjectableURL() throws {
        let targetURL = try XCTUnwrap(URL(string: "about:blank"))
        let fixture = ExtensionGatedNavigationFixture(url: targetURL)
        var didLoad = false

        fixture.tab.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: fixture.webView,
            waitForContentBlockingAssets: false
        ) { resolvedWebView, _ in
            XCTAssertIdentical(resolvedWebView, fixture.webView)
            didLoad = true
            return resolvedWebView.loadHTMLString("", baseURL: nil)
        }

        XCTAssertTrue(fixture.recorded.ids.isEmpty)
        XCTAssertTrue(didLoad)
    }

    func testExtensionContextWaitFailureBlocksMainFrameLoad() async throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/extension-failed"))
        let fixture = ExtensionGatedNavigationFixture(url: targetURL, readiness: .failed)
        var didLoad = false

        fixture.tab.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: fixture.webView,
            waitForContentBlockingAssets: false
        ) { resolvedWebView, _ in
            XCTAssertIdentical(resolvedWebView, fixture.webView)
            didLoad = true
            return resolvedWebView.loadHTMLString("", baseURL: nil)
        }

        for _ in 0..<50 where fixture.recorded.ids.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(fixture.recorded.ids, [fixture.profile.id])
        await fixture.gate.open()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertFalse(didLoad)
    }
}

@MainActor
private final class ExtensionGatedNavigationFixture {
    let tab: Tab
    let webView: FocusableWKWebView
    let profile: Profile
    let gate: GatedExtensionContextReadiness
    let recorded = RecordedProfileIDs()

    init(url: URL, readiness: PageNavigationPrerequisiteResult = .ready) {
        let configuration = WKWebViewConfiguration()
        configuration.webExtensionController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(
            url: url,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.installNavigationDelegate(on: webView)

        let profile = Profile(name: "Extension Gated Profile")
        tab.profileId = profile.id
        tab.navigationRuntime.profileResolutionRuntime = TabProfileResolutionRuntime(
            ephemeralProfileForTab: { _, _ in nil },
            profile: { _ in profile },
            spaceProfile: { _ in nil },
            currentProfile: { profile },
            firstProfile: { profile }
        )
        let gate = GatedExtensionContextReadiness(result: readiness)
        tab.navigationRuntime.normalWebViewExtensionRuntime = TabNormalWebViewExtensionRuntime(
            registerTabWithExtensionRuntimeIfNeeded: { _, _ in /* No-op. */ },
            ensureInitialDocumentTabPublication: { _, _ in .ready },
            prepareWebViewForExtensionRuntime: { _, _, _ in /* No-op. */ },
            ensureInitialExtensionContextsIfNeeded: { [recorded] profileID in
                recorded.ids.append(profileID)
                return await gate.wait()
            }
        )

        self.tab = tab
        self.webView = webView
        self.profile = profile
        self.gate = gate
    }
}

@MainActor
private final class RecordedProfileIDs {
    var ids: [UUID] = []
}

@MainActor
private final class GatedExtensionContextReadiness {
    private let result: PageNavigationPrerequisiteResult
    private var isOpen = false
    private var continuations: [CheckedContinuation<PageNavigationPrerequisiteResult, Never>] = []

    init(result: PageNavigationPrerequisiteResult) {
        self.result = result
    }

    func wait() async -> PageNavigationPrerequisiteResult {
        if isOpen { return result }
        return await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations = []
        pending.forEach { $0.resume(returning: result) }
    }
}
