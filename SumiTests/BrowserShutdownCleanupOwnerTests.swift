import XCTest

@testable import Sumi

@MainActor
final class BrowserShutdownCleanupOwnerTests: XCTestCase {
    func testCleanupCancelsRuntimesClosesSurfacesDedupesTabsThenCleansWebViews() {
        let pinned = makeTab("Pinned")
        let regular = makeTab("Regular")
        let ephemeral = makeTab("Ephemeral")
        var events: [String] = []
        var cleanedTabIds: [UUID] = []
        let owner = BrowserShutdownCleanupOwner(
            dependencies: BrowserShutdownCleanupOwner.Dependencies(
                emitDiagnostic: { _ in /* No-op. */ },
                cancelNativeMessagingSessions: { reason in
                    events.append("native:\(reason)")
                },
                closeAllOptionsWindows: {
                    events.append("options")
                },
                closeAllAuxiliaryWindows: {
                    events.append("aux")
                },
                dismissGlance: {
                    events.append("glance")
                },
                pinnedTabs: {
                    [pinned, regular]
                },
                regularTabs: {
                    [regular]
                },
                ephemeralTabs: {
                    [ephemeral, pinned]
                },
                cleanupTab: { tab in
                    events.append("tab:\(tab.name)")
                    cleanedTabIds.append(tab.id)
                },
                cleanupAllWebViews: {
                    events.append("webviews")
                }
            )
        )

        owner.cleanupAllTabs()

        XCTAssertEqual(
            events,
            [
                "native:BrowserManager.cleanupAllTabs",
                "options",
                "aux",
                "glance",
                "tab:Pinned",
                "tab:Regular",
                "tab:Ephemeral",
                "webviews",
            ]
        )
        XCTAssertEqual(cleanedTabIds, [pinned.id, regular.id, ephemeral.id])
    }

    private func makeTab(_ name: String) -> Tab {
        Tab(
            url: URL(string: "https://\(name.lowercased()).example") ?? preconditionFailure("Invalid test URL"),
            name: name,
            loadsCachedFaviconOnInit: false
        )
    }
}
