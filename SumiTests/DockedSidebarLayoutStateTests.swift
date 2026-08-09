import AppKit
import Observation
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class DockedSidebarLayoutStateTests: XCTestCase {
    func testVisibleLayoutFallsBackToFullProgressBeforeMountStateSyncs() {
        let state = DockedSidebarLayoutState()

        XCTAssertTrue(state.rendersDockedSidebar(isVisible: true))
        XCTAssertEqual(state.layoutProgress(isVisible: true), 1)
    }

    func testAnimatedHideKeepsSidebarMountedAndSeedsProgressWhenStartingCollapsed() {
        var state = DockedSidebarLayoutState()

        state.beginAnimatedHide()

        XCTAssertTrue(state.shouldRender)
        XCTAssertEqual(state.progress, 1)

        state.hide()

        XCTAssertTrue(state.shouldRender)
        XCTAssertEqual(state.progress, 0)
    }

    func testCurrentHideCompletionUnmountsOnlyWhileStillHidden() {
        var state = DockedSidebarLayoutState()
        state.beginAnimatedHide()
        state.hide()

        state.completeAnimatedHide(isVisible: false)

        XCTAssertFalse(state.shouldRender)
    }

    func testHideCompletionDoesNotUnmountAfterSidebarBecameVisible() {
        var state = DockedSidebarLayoutState()
        state.beginAnimatedHide()
        state.hide()

        state.beginShow()
        state.show()
        state.completeAnimatedHide(isVisible: true)

        XCTAssertTrue(state.shouldRender)
        XCTAssertEqual(state.progress, 1)
    }

    func testDockedSidebarStillHasVisibleWidthDuringAnimatedCollapse() async throws {
        let trigger = DockedSidebarAnimationTrigger()
        let host = NSHostingView(
            rootView: DockedSidebarAnimationFixture(trigger: trigger)
        )
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 80)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        try await Task.sleep(for: .milliseconds(30))
        trigger.isVisible = false
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertGreaterThan(
            try visiblePixelWidth(in: host),
            40,
            "The docked column must retain visible width before its 200 ms collapse completes"
        )
    }

    private func visiblePixelWidth(in host: NSView) throws -> Int {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: bitmap)

        var minimumX = bitmap.pixelsWide
        var maximumX = -1
        for row in 0 ..< bitmap.pixelsHigh {
            for column in 0 ..< bitmap.pixelsWide {
                guard (bitmap.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0.5 else {
                    continue
                }
                minimumX = min(minimumX, column)
                maximumX = max(maximumX, column)
            }
        }
        return maximumX >= minimumX ? maximumX - minimumX + 1 : 0
    }
}

@MainActor
@Observable
private final class DockedSidebarAnimationTrigger {
    var isVisible = true
    let presentation = BrowserWindowChromePresentation()
}

private struct DockedSidebarAnimationFixture: View {
    let trigger: DockedSidebarAnimationTrigger
    @State private var layout = DockedSidebarLayoutState()

    var body: some View {
        HStack(spacing: 0) {
            if layout.rendersDockedSidebar(isVisible: trigger.isVisible) {
                Color.white
                    .frame(width: 280)
                    .frame(width: 280 * layout.layoutProgress(isVisible: trigger.isVisible))
                    .clipped()
            }
            Spacer(minLength: 0)
        }
        .background(Color.clear)
        .onChange(of: trigger.isVisible) { _, isVisible in
            let animation = SidebarMotionPolicy.dockedLayoutAnimation(
                for: .standard,
                isShowing: isVisible
            )
            trigger.presentation.performSidebarMotion(
                surface: .docked,
                toward: isVisible ? .visible : .hidden,
                animation: animation,
                prepareLayout: {
                    if isVisible {
                        layout.beginShow()
                    } else {
                        layout.beginAnimatedHide()
                    }
                },
                updateLayout: {
                    if isVisible {
                        layout.show()
                    } else {
                        layout.hide()
                    }
                },
                completion: {
                    if !isVisible {
                        layout.completeAnimatedHide(isVisible: false)
                    }
                }
            )
        }
    }
}
