import WebKit
import XCTest

@testable import Sumi
import SumiDomain

/// Regression: Glance must never present permission prompt UI (fail-closed).
/// Bridges that default surface to `.normalTab` must not weaken this for glance.
@MainActor
final class TabPermissionGlanceFailClosedTests: XCTestCase {
    func testGlanceSurfaceCannotPresentPromptUIEvenWhenActiveAndVisible() {
        let glanceContext = makeSecurityContext(surface: .glance)

        XCTAssertEqual(glanceContext.surface, .glance)
        XCTAssertFalse(
            glanceContext.canPresentPromptUI,
            "Glance must fail closed: canPresentPromptUI must be false"
        )
    }

    func testNormalTabCanPresentPromptUIWhenActiveAndVisible() {
        let normalContext = makeSecurityContext(surface: .normalTab)
        XCTAssertTrue(normalContext.canPresentPromptUI)
    }

    private func makeSecurityContext(
        surface: SumiPermissionSecurityContext.Surface
    ) -> SumiPermissionSecurityContext {
        let origin = SumiPermissionOrigin(url: URL(string: "https://example.com/")!)
        let request = SumiPermissionRequest(
            requestingOrigin: origin,
            topOrigin: origin,
            displayDomain: "example.com",
            permissionTypes: [.geolocation],
            hasUserGesture: true,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isEphemeralProfile: false,
            profilePartitionId: "profile-a"
        )
        return SumiPermissionSecurityContext(
            request: request,
            requestingOrigin: request.requestingOrigin,
            topOrigin: request.topOrigin,
            committedURL: URL(string: "https://example.com/"),
            visibleURL: URL(string: "https://example.com/"),
            mainFrameURL: URL(string: "https://example.com/"),
            isMainFrame: true,
            isActiveTab: true,
            isVisibleTab: true,
            hasUserGesture: true,
            isEphemeralProfile: false,
            profilePartitionId: "profile-a",
            transientPageId: "page-a",
            surface: surface,
            navigationOrPageGeneration: "0",
            now: Date(timeIntervalSince1970: 1_700_000_001)
        )
    }

    func testPermissionSurfaceOwnerReportsGlanceForActivePreview() {
        let tabId = UUID()
        let profile = Profile(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            name: "Glance Fail Closed",
            icon: "person"
        )
        let committedURL = URL(string: "https://example.com/")!
        let webView = PermissionCommittedURLWebView()
        webView.reportedCommittedURL = committedURL
        let documentLease = TabMainFrameDocumentLease(
            revision: 1,
            documentGeneration: 0,
            webViewID: ObjectIdentifier(webView),
            participantID: UUID(),
            committedURL: committedURL,
            presentationURL: committedURL,
            isPDF: false,
            isAuthority: true
        )
        let owner = TabPermissionSurfaceOwner(
            context: TabPermissionSurfaceOwner.Context(
                tabId: tabId,
                currentURL: { URL(string: "https://example.com/")! },
                resolveProfile: { profile },
                profile: { _ in profile },
                surfaceState: { _ in
                    TabPermissionSurfaceState(
                        isActive: true,
                        isVisible: true
                    )
                },
                pageIdentity: {
                    let tabIdString = tabId.uuidString.lowercased()
                    return TabExtensionPageIdentity(
                        tabId: tabIdString,
                        pageGeneration: "0",
                        pageId: "\(tabIdString):0"
                    )
                },
                documentLease: { candidate in
                    candidate === webView ? documentLease : nil
                },
                isCurrentPage: { _, _ in true },
                invalidatePageForWebViewReplacement: {},
                handlePermissionLifecycleEvent: { _ in },
                isActiveGlancePreviewSurface: { _ in true },
                isAuxiliaryMiniWindow: { false }
            )
        )

        XCTAssertEqual(owner.permissionSurface(for: webView), .glance)

        let geolocation = owner.geolocationContext(for: webView)
        XCTAssertEqual(geolocation?.surface, .glance)
    }
}
