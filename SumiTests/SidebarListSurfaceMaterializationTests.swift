import AppKit
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
private final class SidebarRowMaterializationRecorder {
    var materializedIDs: Set<Int> = []
}

private struct SidebarMaterializationProbeRow: View {
    let id: Int
    let recorder: SidebarRowMaterializationRecorder

    var body: some View {
        Color.clear.onAppear { recorder.materializedIDs.insert(id) }
    }
}

/// `LazyVStack` refuses to materialize anything below two consecutive
/// zero-height children. An empty space is that exact scene — pinned top,
/// boundary, and both regular-run markers collapse to zero — and it used to
/// take the New Tab row down with it.
final class SidebarListSurfaceMaterializationTests: XCTestCase {
    @MainActor
    func testEmptySpaceSceneStillMaterializesItsOnlySizedRow() {
        // pinnedTop, boundary, runStart, runEnd, newTabGap, newTab.
        let materialized = materializedIDs(
            extents: [0, 0, 0, 0, 0, SidebarRowLayout.rowHeight]
        )

        XCTAssertTrue(
            materialized.contains(5),
            "New Tab must render in a space with no pinned content and no tabs."
        )
    }

    @MainActor
    func testScenesWithSizedLeadingRowsAreUnaffected() {
        // A space with pinned content: leading rows already have extent.
        let materialized = materializedIDs(
            extents: [
                SidebarInsertionGuide.visualCenterY,
                SidebarRowLayout.rowGap,
                0,
                0,
                0,
                SidebarRowLayout.rowHeight,
            ]
        )

        XCTAssertTrue(materialized.contains(5))
    }

    @MainActor
    private func materializedIDs(extents: [CGFloat]) -> Set<Int> {
        let width: CGFloat = 213
        let height: CGFloat = 600
        let recorder = SidebarRowMaterializationRecorder()
        let scene = SidebarListScene<Int, Int>(
            elements: extents.enumerated().map { index, extent in
                .init(id: index, payload: index, targetExtent: extent)
            }
        )

        let root = ScrollView(.vertical, showsIndicators: false) {
            SidebarListSurface(scene: scene, animation: nil) { payload, _ in
                SidebarMaterializationProbeRow(
                    id: payload,
                    recorder: recorder
                )
            }
            .frame(width: width, alignment: .leading)
        }
        .frame(width: width, height: height)
        .environmentObject(SidebarDragGeometryModule())

        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.orderOut(nil)
        return recorder.materializedIDs
    }
}
