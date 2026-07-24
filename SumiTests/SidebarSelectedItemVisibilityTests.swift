@testable import Sumi
import Observation
import SwiftUI
import XCTest

@MainActor
final class SidebarSelectedItemVisibilityTests: XCTestCase {
    func testRepeatedRevealOfSameItemPublishesANewRequest() throws {
        let owner = SidebarSelectedItemRevealOwner()
        let itemID = SidebarScrollTargetID.regularTab(UUID())
        owner.surfaceDidBecomeReady()

        owner.reveal(itemID)
        let first = try XCTUnwrap(owner.request)
        owner.reveal(itemID)
        let second = try XCTUnwrap(owner.request)

        XCTAssertEqual(first.targetID, second.targetID)
        XCTAssertNotEqual(first.generation, second.generation)
    }

    func testRevealPathAdvancesWhenLazyAncestorAppears() throws {
        let owner = SidebarSelectedItemRevealOwner()
        let folderID = UUID()
        let itemID = UUID()
        owner.surfaceDidBecomeReady()

        owner.reveal(
            SidebarSelectedItemRevealPath([
                .folder(folderID),
                .launcher(itemID)
            ])
        )
        XCTAssertEqual(try XCTUnwrap(owner.request).targetID, .folder(folderID))
        XCTAssertEqual(try XCTUnwrap(owner.request).purpose, .materializePath)

        owner.targetDidAppear(.folder(folderID))

        XCTAssertEqual(try XCTUnwrap(owner.request).targetID, .launcher(itemID))
        XCTAssertEqual(try XCTUnwrap(owner.request).purpose, .revealSelection)
    }

    func testRevealPathSkipsAnAlreadyMountedAncestor() throws {
        let owner = SidebarSelectedItemRevealOwner()
        let folderID = UUID()
        let itemID = UUID()
        owner.surfaceDidBecomeReady()
        owner.targetDidAppear(.folder(folderID))

        owner.reveal(
            SidebarSelectedItemRevealPath([
                .folder(folderID),
                .launcher(itemID)
            ])
        )

        XCTAssertEqual(try XCTUnwrap(owner.request).targetID, .launcher(itemID))
        XCTAssertEqual(try XCTUnwrap(owner.request).purpose, .revealSelection)
    }

    func testRevealWaitsUntilRestoredSurfaceIsReady() throws {
        let owner = SidebarSelectedItemRevealOwner()
        let itemID = SidebarScrollTargetID.regularTab(UUID())

        owner.reveal(itemID)

        XCTAssertNil(owner.request)

        owner.surfaceDidBecomeReady()

        XCTAssertEqual(try XCTUnwrap(owner.request).targetID, itemID)
    }

    func testLatestRevealWinsWhileRestoredSurfaceIsPending() throws {
        let owner = SidebarSelectedItemRevealOwner()
        let firstItemID = SidebarScrollTargetID.regularTab(UUID())
        let lastItemID = SidebarScrollTargetID.regularTab(UUID())

        owner.reveal(firstItemID)
        owner.reveal(lastItemID)
        owner.surfaceDidBecomeReady()

        XCTAssertEqual(try XCTUnwrap(owner.request).targetID, lastItemID)
    }

    func testPendingRevealSurvivesTemporaryMountDuringViewportRestoration() throws {
        let owner = SidebarSelectedItemRevealOwner()
        let itemID = SidebarScrollTargetID.regularTab(UUID())

        owner.reveal(itemID)
        owner.targetDidAppear(itemID)
        owner.targetDidDisappear(itemID)
        owner.surfaceDidBecomeReady()

        XCTAssertEqual(try XCTUnwrap(owner.request).targetID, itemID)
    }

    func testInitialSavedViewportIsAppliedToScrollSurface() throws {
        let state = SidebarSelectedItemLazyHarnessState()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemLazyHarness(
                state: state,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: 600,
                    contentHeight: 1_600,
                    viewportHeight: 100
                )
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))

        XCTAssertEqual(scrollView.documentVisibleRect.minY, 600, accuracy: 1)
    }

    func testElasticSavedViewportIsClampedBeforeRestore() throws {
        let state = SidebarSelectedItemLazyHarnessState()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemLazyHarness(
                state: state,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: -150,
                    contentHeight: 1_600,
                    viewportHeight: 100
                )
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))

        XCTAssertEqual(scrollView.documentVisibleRect.minY, 0, accuracy: 1)
    }

    func testSelectedItemRevealUsesMotionOnlyInStandardMode() {
        XCTAssertNotNil(SidebarMotionPolicy.selectedItemRevealAnimation(for: .standard))
        XCTAssertNil(
            SidebarMotionPolicy.selectedItemRevealAnimation(for: .reducedMotion)
        )
    }

    func testInitialRevealPresentsRestoredViewportBeforeAnimating() throws {
        let state = SidebarSelectedItemLazyHarnessState(
            initiallySelectedItemIndex: 0
        )
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemLazyHarness(
                state: state,
                motionMode: .standard,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: 600,
                    contentHeight: 1_600,
                    viewportHeight: 100
                )
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))
        scrollView.contentView.postsBoundsChangedNotifications = true
        let offsetRecorder = SidebarScrollOffsetRecorder(
            initialOffset: scrollView.documentVisibleRect.minY
        )
        let observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak scrollView, weak offsetRecorder] _ in
            MainActor.assumeIsolated {
                if let scrollView {
                    offsetRecorder?.record(scrollView.documentVisibleRect.minY)
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        runMainLoop()

        XCTAssertTrue(offsetRecorder.offsets.contains { $0 >= 500 })
        XCTAssertTrue(offsetRecorder.offsets.contains { $0 > 50 && $0 < 500 })
        XCTAssertLessThan(scrollView.documentVisibleRect.minY, 44)
    }

    func testOffscreenSelectionMaterializesLazyRowAndRevealsIt() throws {
        let state = SidebarSelectedItemLazyHarnessState()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemLazyHarness(
                state: state,
                restoredViewport: nil
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))
        scrollView.contentView.scroll(
            to: NSPoint(
                x: 0,
                y: max(
                    (scrollView.documentView?.bounds.height ?? 0)
                        - scrollView.contentView.bounds.height,
                    0
                )
            )
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)

        state.selectedItemID = .regularTab(state.itemIDs[0])
        runMainLoop()

        XCTAssertLessThan(scrollView.documentVisibleRect.minY, 44)
    }

    func testRevealUsesOneNearestEdgeScroll() throws {
        let state = SidebarSelectedItemLazyHarnessState()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemLazyHarness(
                state: state,
                restoredViewport: nil
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))

        // Row 3 spans [120, 160] in a 100pt viewport. One nearest-edge reveal
        // lands directly on 60 without a delayed correction pass.
        state.selectedItemID = .regularTab(state.itemIDs[3])
        runMainLoop()

        XCTAssertEqual(
            scrollView.documentVisibleRect.minY,
            60,
            accuracy: 1
        )
    }

    func testAnimatedRevealEndsAtTheNearestViewportEdge() throws {
        let state = SidebarSelectedItemLazyHarnessState()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemLazyHarness(
                state: state,
                motionMode: .standard,
                restoredViewport: nil
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))

        state.selectedItemID = .regularTab(state.itemIDs[3])
        runMainLoop(for: 1.0)

        XCTAssertEqual(
            scrollView.documentVisibleRect.minY,
            60,
            accuracy: 1
        )
    }

    func testUpwardRevealEndsAtTheNearestViewportEdge() throws {
        let state = SidebarSelectedItemLazyHarnessState()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemLazyHarness(
                state: state,
                restoredViewport: nil
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 1_500))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        // Row 20 spans [800, 840]; one nearest-edge reveal lands on 800.
        state.selectedItemID = .regularTab(state.itemIDs[20])
        runMainLoop()

        XCTAssertEqual(
            scrollView.documentVisibleRect.minY,
            800,
            accuracy: 1
        )
    }

    func testSelectionRevealDoesNotStallWhenRestoredContentShrank() throws {
        let state = SidebarSelectedItemLazyHarnessState(
            itemCount: 5,
            initiallySelectedItemIndex: 4
        )
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemLazyHarness(
                state: state,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: 600,
                    contentHeight: 1_600,
                    viewportHeight: 100
                )
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))

        XCTAssertEqual(scrollView.documentVisibleRect.minY, 100, accuracy: 1)
    }

    func testRevealOfAnAlreadyVisibleRowDoesNotScroll() throws {
        let state = SidebarSelectedItemLazyHarnessState()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemLazyHarness(
                state: state,
                restoredViewport: nil
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))

        // Row 1 spans [40, 80] and is fully in view, so nothing should move.
        state.selectedItemID = .regularTab(state.itemIDs[1])
        runMainLoop()

        XCTAssertEqual(scrollView.documentVisibleRect.minY, 0, accuracy: 1)
    }

    func testDirectLazyRowIdentityMaterializesNestedRowContent() throws {
        let state = SidebarSelectedItemLazyHarnessState()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemNestedIdentityHarness(state: state)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))
        scrollView.contentView.scroll(
            to: NSPoint(
                x: 0,
                y: max(
                    (scrollView.documentView?.bounds.height ?? 0)
                        - scrollView.contentView.bounds.height,
                    0
                )
            )
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)

        state.selectedItemID = .regularTab(state.itemIDs[0])
        runMainLoop()

        XCTAssertLessThan(scrollView.documentVisibleRect.minY, 44)
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private func runMainLoop(for duration: TimeInterval = 0.4) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
}

@MainActor
private final class SidebarScrollOffsetRecorder {
    private(set) var offsets: [CGFloat]

    init(initialOffset: CGFloat) {
        offsets = [initialOffset]
    }

    func record(_ offset: CGFloat) {
        offsets.append(offset)
    }
}

@MainActor
@Observable
private final class SidebarSelectedItemLazyHarnessState {
    let itemIDs: [UUID]
    var selectedItemID: SidebarScrollTargetID?

    init(
        itemCount: Int = 40,
        initiallySelectedItemIndex: Int? = nil
    ) {
        itemIDs = (0..<itemCount).map { _ in UUID() }
        selectedItemID = initiallySelectedItemIndex.map {
            .regularTab(itemIDs[$0])
        }
    }
}

private struct SidebarSelectedItemLazyHarness: View {
    let state: SidebarSelectedItemLazyHarnessState
    var motionMode: SidebarMotionPolicy.Mode = .reducedMotion
    let restoredViewport: SpaceSidebarSnapshotViewport?

    var body: some View {
        SidebarSelectedItemVisibilityScope(
            revealPath: state.selectedItemID.map {
                SidebarSelectedItemRevealPath([$0])
            },
            selection: .none,
            isEnabled: true,
            motionMode: motionMode,
            restoredViewport: restoredViewport
        ) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.itemIDs, id: \.self) { itemID in
                        Color.clear
                            .frame(height: 40)
                            .sidebarScrollTarget(.regularTab(itemID))
                    }
                }
            }
        }
    }
}

private struct SidebarSelectedItemNestedIdentityHarness: View {
    let state: SidebarSelectedItemLazyHarnessState

    var body: some View {
        SidebarSelectedItemVisibilityScope(
            revealPath: state.selectedItemID.map {
                SidebarSelectedItemRevealPath([$0])
            },
            selection: .none,
            isEnabled: true,
            motionMode: .reducedMotion,
            restoredViewport: nil
        ) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.itemIDs, id: \.self) { itemID in
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: 40)
                        }
                        .sidebarScrollTarget(.regularTab(itemID))
                    }
                }
            }
        }
    }
}
