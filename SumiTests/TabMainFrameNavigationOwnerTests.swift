import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabMainFrameNavigationOwnerTests: XCTestCase {
    func testPreparedNavigationRunsOnlyAfterPreparation() async {
        let owner = TabMainFrameNavigationOwner()
        let webView = WKWebView(frame: .zero)
        var preparation: CheckedContinuation<Void, Never>?
        var clearCount = 0
        var loadedWebViews: [WKWebView] = []

        owner.performAfterPreparation(
            on: webView,
            clearRelatedNavigationState: {
                clearCount += 1
            },
            prepare: {
                await withCheckedContinuation { continuation in
                    preparation = continuation
                }
            },
            performLoad: { loadedWebViews.append($0) }
        )

        await waitUntil { preparation != nil }
        XCTAssertEqual(clearCount, 1)
        XCTAssertTrue(loadedWebViews.isEmpty)

        preparation?.resume()
        await drainMainActorTasks()

        XCTAssertEqual(loadedWebViews.count, 1)
        XCTAssertTrue(loadedWebViews.first === webView)
    }

    func testCancelSuppressesPreparedNavigationLoad() async {
        let owner = TabMainFrameNavigationOwner()
        let webView = WKWebView(frame: .zero)
        var preparation: CheckedContinuation<Void, Never>?
        var clearCount = 0
        var didLoad = false

        owner.performAfterPreparation(
            on: webView,
            clearRelatedNavigationState: {
                clearCount += 1
            },
            prepare: {
                await withCheckedContinuation { continuation in
                    preparation = continuation
                }
            },
            performLoad: { _ in didLoad = true }
        )

        await waitUntil { preparation != nil }
        owner.cancel {
            clearCount += 1
        }
        preparation?.resume()
        await drainMainActorTasks()

        XCTAssertEqual(clearCount, 2)
        XCTAssertFalse(didLoad)
    }

    func testImmediateNavigationSupersedesPreparedNavigation() async {
        let owner = TabMainFrameNavigationOwner()
        let webView = WKWebView(frame: .zero)
        var preparation: CheckedContinuation<Void, Never>?
        var clearCount = 0
        var loadEvents: [String] = []

        owner.performAfterPreparation(
            on: webView,
            clearRelatedNavigationState: {
                clearCount += 1
            },
            prepare: {
                await withCheckedContinuation { continuation in
                    preparation = continuation
                }
            },
            performLoad: { _ in loadEvents.append("prepared") }
        )
        await waitUntil { preparation != nil }

        owner.perform(
            on: webView,
            clearRelatedNavigationState: {
                clearCount += 1
            },
            performLoad: { _ in loadEvents.append("immediate") }
        )
        preparation?.resume()
        await drainMainActorTasks()

        XCTAssertEqual(clearCount, 2)
        XCTAssertEqual(loadEvents, ["immediate"])
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<20 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private func drainMainActorTasks() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }
}
