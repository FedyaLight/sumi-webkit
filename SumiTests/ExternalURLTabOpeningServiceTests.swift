import XCTest

@testable import Sumi

@MainActor
final class ExternalURLTabOpeningServiceTests: XCTestCase {
    func testNoActiveWindowDoesNotOpenTab() {
        let registry = WindowRegistry()
        let opening = RecordingURLTabOpening()
        let service = ExternalURLTabOpeningService(
            windowRegistry: registry,
            tabOpening: opening
        )

        service.presentExternalURL(URL(string: "https://external.example")!)

        XCTAssertTrue(opening.requests.isEmpty)
    }

    func testRoutesExternalURLToExactActiveWindowForegroundContext() throws {
        let registry = WindowRegistry()
        let activeWindow = BrowserWindowState()
        let otherWindow = BrowserWindowState()
        registry.register(activeWindow)
        registry.register(otherWindow)
        registry.activeWindowId = activeWindow.id
        let opening = RecordingURLTabOpening()
        let service = ExternalURLTabOpeningService(
            windowRegistry: registry,
            tabOpening: opening
        )

        service.presentExternalURL(URL(string: "https://external.example/path")!)

        let request = try XCTUnwrap(opening.requests.first)
        XCTAssertEqual(request.url, "https://external.example/path")
        switch request.context.activationPolicy {
        case .foreground(let windowState, _):
            XCTAssertIdentical(windowState, activeWindow)
        case .background:
            XCTFail("External URL must open in the foreground")
        }
    }

    func testExternalURLActivatesTheTargetBrowserWindow() throws {
        let registry = WindowRegistry()
        let activeWindow = BrowserWindowState()
        registry.register(activeWindow)
        registry.activeWindowId = activeWindow.id
        let opening = RecordingURLTabOpening()
        var focusedWindow: BrowserWindowState?
        let service = ExternalURLTabOpeningService(
            windowRegistry: registry,
            tabOpening: opening,
            focusWindow: { focusedWindow = $0 }
        )

        service.presentExternalURL(try XCTUnwrap(URL(string: "https://external.example")))

        XCTAssertIdentical(focusedWindow, activeWindow)
    }

    func testIncognitoWindowIdentityIsPreservedForEphemeralOpeningPolicy() throws {
        let registry = WindowRegistry()
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        registry.register(incognitoWindow)
        registry.activeWindowId = incognitoWindow.id
        let opening = RecordingURLTabOpening()
        let service = ExternalURLTabOpeningService(
            windowRegistry: registry,
            tabOpening: opening
        )

        service.presentExternalURL(URL(string: "https://private.example")!)

        let request = try XCTUnwrap(opening.requests.first)
        XCTAssertIdentical(request.context.windowState, incognitoWindow)
        switch request.context.activationPolicy {
        case .foreground(let windowState, _):
            XCTAssertIdentical(windowState, incognitoWindow)
        case .background:
            XCTFail("Incognito external URL must use the foreground ephemeral path")
        }
    }

    func testRetainedHandlerDoesNotKeepRuntimeGraphAliveAndNoOpsAfterRelease() throws {
        var registry: WindowRegistry? = WindowRegistry()
        var browserManager: BrowserManager? = BrowserManager(
            windowRegistry: try XCTUnwrap(registry),
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupDatabase()
            )
        )
        let retainedService: ExternalURLTabOpeningService
        weak let releasedBrowserManager = browserManager
        weak let releasedRegistry = registry
        weak var releasedOpening: BrowserTabOpeningOwner?

        do {
            let browserManager = try XCTUnwrap(browserManager)
            let registry = try XCTUnwrap(registry)
            let window = BrowserWindowState()
            browserManager.tabResidenceAuthority.establishResidenceSession(
                on: window
            )
            registry.register(window)
            registry.setActive(window)
            let opening = browserManager.tabOpening
            releasedOpening = opening
            retainedService = ExternalURLTabOpeningService(
                windowRegistry: registry,
                tabOpening: opening
            )
        }

        registry = nil
        browserManager = nil

        XCTAssertNil(releasedRegistry)
        XCTAssertNil(releasedOpening)
        XCTAssertNil(releasedBrowserManager)

        retainedService.presentExternalURL(
            try XCTUnwrap(URL(string: "https://released.example"))
        )
    }
}

@MainActor
private final class RecordingURLTabOpening: URLTabOpening {
    struct Request {
        let url: String
        let context: BrowserTabOpenContext
    }

    var requests: [Request] = []

    func openNewTab(url: String, context: BrowserTabOpenContext) -> Tab {
        requests.append(.init(url: url, context: context))
        return Tab(
            url: URL(string: url)!,
            name: url,
            loadsCachedFaviconOnInit: false
        )
    }
}
