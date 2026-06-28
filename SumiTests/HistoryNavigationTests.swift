import XCTest

@testable import Sumi

@MainActor
final class HistoryNavigationTests: XCTestCase {
    func testOpenHistoryTabCreatesSelectedHistorySurface() {
        let (browserManager, _, windowState, space) = makeHarness()

        browserManager.openHistoryTab(in: windowState)

        let historyTabs = browserManager.tabManager.tabs(in: space).filter(\.representsSumiHistorySurface)
        XCTAssertEqual(historyTabs.count, 1)
        XCTAssertEqual(
            historyTabs.first?.url,
            SumiSurface.historySurfaceURL(rangeQuery: HistoryRange.all.paneQueryValue)
        )
        XCTAssertEqual(historyTabs.first?.name, "History")
        XCTAssertEqual(windowState.currentTabId, historyTabs.first?.id)
    }

    func testHistorySurfaceIsNativeBrowserTab() {
        let historyURL = SumiSurface.historySurfaceURL(
            rangeQuery: HistoryRange.all.paneQueryValue
        )
        let tab = Tab(url: historyURL)

        XCTAssertTrue(tab.representsSumiHistorySurface)
        XCTAssertTrue(tab.representsSumiInternalSurface)
        XCTAssertTrue(tab.representsSumiNativeSurface)
        XCTAssertTrue(tab.representsSumiNativeSurface)
        XCTAssertFalse(tab.requiresPrimaryWebView)
        XCTAssertTrue(tab.usesChromeThemedTemplateFavicon)
    }

    func testOpenHistoryTabReusesExistingHistorySurface() throws {
        let (browserManager, _, windowState, space) = makeHarness()

        browserManager.openHistoryTab(in: windowState)
        let firstHistoryTab = try XCTUnwrap(
            browserManager.tabManager.tabs(in: space).first(where: \.representsSumiHistorySurface)
        )

        browserManager.openHistoryTab(selecting: .older, in: windowState)

        let historyTabs = browserManager.tabManager.tabs(in: space).filter(\.representsSumiHistorySurface)
        XCTAssertEqual(historyTabs.count, 1)
        XCTAssertEqual(historyTabs.first?.id, firstHistoryTab.id)
        XCTAssertEqual(
            historyTabs.first?.url,
            SumiSurface.historySurfaceURL(rangeQuery: HistoryRange.older.paneQueryValue)
        )
        XCTAssertEqual(windowState.currentTabId, firstHistoryTab.id)
    }

    func testHistoryWindowOpenPathsShareWindowRegistrationAwaiter() throws {
        let source = try Self.source(named: "Sumi/Managers/BrowserManager/BrowserManager+History.swift")
        let reopenSource = try Self.functionSource(named: "reopenWindow", in: source)

        XCTAssertEqual(source.components(separatedBy: "awaitNextRegisteredWindow(").count - 1, 1)
        XCTAssertTrue(source.contains("private func createNewWindowRegistrationAwaiter()"))
        XCTAssertTrue(reopenSource.contains("createNewWindowRegistrationAwaiter()"))
        XCTAssertTrue(reopenSource.contains("windowSessionService.applyWindowSessionSnapshot("))
    }

    private func makeHarness() -> (BrowserManager, WindowRegistry, BrowserWindowState, Space) {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.historyManager.switchProfile(profile.id)
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (browserManager, windowRegistry, windowState, space)
    }

    private static func source(named relativePath: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "HistoryNavigationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate \(relativePath)"]
        )
    }

    private static func functionSource(named functionName: String, in source: String) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: "func \(functionName)"))
        let remainingSource = source[start.upperBound...]
        let nextFunctionBoundaries = [
            remainingSource.range(of: "\n    func ")?.lowerBound,
            remainingSource.range(of: "\n    private func ")?.lowerBound,
        ].compactMap(\.self)
        let end = nextFunctionBoundaries.min() ?? source.endIndex

        return source[start.lowerBound..<end]
    }
}
