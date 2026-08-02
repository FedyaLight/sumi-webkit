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

    func testInteractiveViewportCacheUpdatesBeforeTheNextInputEvent() throws {
        let state = SidebarSelectedItemLazyHarnessState(itemCount: 20)
        let viewportRecorder = SidebarViewportRecorder()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemPresentedLayoutHarness(
                state: state,
                viewportRecorder: viewportRecorder
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
        runMainLoop()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))
        viewportRecorder.reset()

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 400))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        let capturedViewport = try XCTUnwrap(viewportRecorder.viewports.last)
        XCTAssertEqual(
            capturedViewport.contentOffsetY,
            400,
            accuracy: 1,
            "A side-button or trackpad transition can be the next AppKit event, so snapshot state cannot wait for an async SwiftUI geometry delivery"
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

        XCTAssertGreaterThanOrEqual(
            offsetRecorder.offsets.first ?? -1,
            500,
            "The surface must mount at its saved viewport; an initial top frame creates a visible snap before autofocus"
        )
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

    func testPresentedLayoutRevealHandlesChangingRegularAndPinnedTargetsAcrossTheList() throws {
        let state = SidebarSelectedItemLazyHarnessState(itemCount: 20)
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemPresentedLayoutHarness(state: state)
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
        XCTAssertGreaterThan(
            scrollView.documentView?.bounds.height ?? 0,
            scrollView.documentVisibleRect.height
        )
        let targetIndices = [
            19, 0, 18, 1, 17, 2, 16, 3, 15, 4,
            14, 5, 13, 6, 12, 7, 11, 8, 10, 9,
        ]

        for targetIndex in targetIndices {
            state.selectedItemID = targetIndex.isMultiple(of: 2)
                ? .launcher(state.itemIDs[targetIndex])
                : .regularTab(state.itemIDs[targetIndex])
            runMainLoop()
            let visibleRect = scrollView.documentVisibleRect
            let rowMinY = CGFloat(targetIndex) * 40
            let rowMaxY = rowMinY + 40
            XCTAssertGreaterThanOrEqual(
                rowMinY,
                visibleRect.minY - 1,
                "Autofocus clipped the top of row \(targetIndex)"
            )
            XCTAssertLessThanOrEqual(
                rowMaxY,
                visibleRect.maxY + 1,
                "Autofocus clipped the bottom of row \(targetIndex)"
            )
        }
    }

    func testPresentedLayoutRevealRunsWhenCollapsedSurfaceBecomesInteractive() throws {
        let state = SidebarSelectedItemLazyHarnessState(
            itemCount: 20,
            initiallySelectedItemIndex: 19,
            isEnabled: false
        )
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemPresentedLayoutHarness(state: state)
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

        state.isEnabled = true
        runMainLoop()

        XCTAssertGreaterThanOrEqual(
            CGFloat(19 * 40),
            scrollView.documentVisibleRect.minY - 1
        )
        XCTAssertLessThanOrEqual(
            CGFloat(20 * 40),
            scrollView.documentVisibleRect.maxY + 1
        )
    }

    func testPresentedLayoutSnapshotRestoreAnimatesPinnedUpwardInOnePass() throws {
        let state = SidebarSelectedItemLazyHarnessState(itemCount: 20)
        state.selectedItemID = .launcher(state.itemIDs[0])
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemPresentedLayoutHarness(
                state: state,
                motionMode: .standard,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: 700,
                    contentHeight: 800,
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

        runMainLoop(for: 1)

        XCTAssertGreaterThanOrEqual(
            offsetRecorder.offsets.first ?? -1,
            690,
            "Upward autofocus must start at the restored bottom viewport"
        )
        XCTAssertTrue(
            offsetRecorder.offsets.contains { $0 > 50 && $0 < 650 },
            "Upward autofocus must produce intermediate animated offsets"
        )
        XCTAssertTrue(
            zip(offsetRecorder.offsets, offsetRecorder.offsets.dropFirst())
                .allSatisfy { previous, next in next <= previous + 1 },
            "Upward autofocus must not jump down before continuing upward"
        )
        XCTAssertEqual(scrollView.documentVisibleRect.minY, 0, accuracy: 1)
    }

    func testPresentedLayoutRepeatsUpwardRevealForTheSamePinnedTarget() throws {
        let state = SidebarSelectedItemLazyHarnessState(itemCount: 20)
        state.selectedItemID = .launcher(state.itemIDs[0])
        let requestRecorder = SidebarRevealRequestRecorder()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemPresentedLayoutHarness(
                state: state,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: 700,
                    contentHeight: 800,
                    viewportHeight: 100
                ),
                requestRecorder: requestRecorder
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

        state.isEnabled = false
        runMainLoop()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 700))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        runMainLoop(for: 0.1)
        XCTAssertEqual(scrollView.documentVisibleRect.minY, 700, accuracy: 1)

        state.isEnabled = true
        runMainLoop()

        XCTAssertEqual(requestRecorder.generations.count, 2)
        XCTAssertEqual(
            scrollView.documentVisibleRect.minY,
            0,
            accuracy: 1,
            "Returning to the same pinned target must issue a fresh upward scroll"
        )
    }

    func testPresentedLayoutUpwardRevealDoesNotWaitForUserScrollAfterContentGrowth() throws {
        let state = SidebarSelectedItemLazyHarnessState(
            itemCount: 20,
            visibleItemCount: 10
        )
        state.selectedItemID = .launcher(state.itemIDs[0])
        let requestRecorder = SidebarRevealRequestRecorder()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemPresentedLayoutHarness(
                state: state,
                motionMode: .reducedMotion,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: 300,
                    contentHeight: 400,
                    viewportHeight: 100
                ),
                requestRecorder: requestRecorder
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
        state.visibleItemCount = 20
        hostingView.layoutSubtreeIfNeeded()
        runMainLoop()

        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))
        XCTAssertEqual(
            requestRecorder.generations.count,
            1,
            "Content materialization must not leave upward autofocus pending until user scrolls"
        )
        XCTAssertEqual(scrollView.documentVisibleRect.minY, 0, accuracy: 1)
    }

    func testPresentedLayoutUpwardRevealWaitsForFinalContentHeight() throws {
        let state = SidebarSelectedItemLazyHarnessState(
            itemCount: 20,
            visibleItemCount: 10
        )
        state.selectedItemID = .launcher(state.itemIDs[0])
        let requestRecorder = SidebarRevealRequestRecorder()
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemPresentedLayoutHarness(
                state: state,
                motionMode: .reducedMotion,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: 300,
                    contentHeight: 400,
                    viewportHeight: 100
                ),
                requestRecorder: requestRecorder
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
        runMainLoop(for: 0.1)

        XCTAssertTrue(
            requestRecorder.generations.isEmpty,
            "Upward autofocus must wait while the scroll document is still materializing"
        )

        state.visibleItemCount = 20
        hostingView.layoutSubtreeIfNeeded()
        runMainLoop()

        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))
        XCTAssertEqual(requestRecorder.generations.count, 1)
        XCTAssertEqual(scrollView.documentVisibleRect.minY, 0, accuracy: 1)
    }

    func testPresentedLayoutUpwardRevealDoesNotCorrectInTheOppositeDirectionBeforeAnimating() throws {
        let state = SidebarSelectedItemLazyHarnessState(
            itemCount: 20,
            visibleItemCount: 10
        )
        state.selectedItemID = .launcher(state.itemIDs[0])
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemPresentedLayoutHarness(
                state: state,
                motionMode: .standard,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: 300,
                    contentHeight: 400,
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

        state.visibleItemCount = 20
        hostingView.layoutSubtreeIfNeeded()
        runMainLoop(for: 1)

        XCTAssertTrue(
            zip(offsetRecorder.offsets, offsetRecorder.offsets.dropFirst())
                .allSatisfy { previous, next in next <= previous + 1 },
            "Upward autofocus must not jump toward the new bottom before animating upward"
        )
        XCTAssertTrue(
            offsetRecorder.offsets.contains { $0 > 50 && $0 < 250 },
            "Upward autofocus must retain intermediate animated offsets"
        )
        XCTAssertEqual(scrollView.documentVisibleRect.minY, 0, accuracy: 1)
    }

    func testPresentedLayoutSnapshotRestoreAnimatesDownwardInOnePass() throws {
        let state = SidebarSelectedItemLazyHarnessState(
            itemCount: 20,
            initiallySelectedItemIndex: 19
        )
        let hostingView = NSHostingView(
            rootView: SidebarSelectedItemPresentedLayoutHarness(
                state: state,
                motionMode: .standard,
                restoredViewport: SpaceSidebarSnapshotViewport(
                    contentOffsetY: 0,
                    contentHeight: 800,
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

        runMainLoop(for: 1)

        XCTAssertLessThanOrEqual(
            offsetRecorder.offsets.first ?? .infinity,
            10,
            "Downward autofocus must start at the restored top viewport"
        )
        XCTAssertTrue(
            offsetRecorder.offsets.contains { $0 > 50 && $0 < 650 },
            "Downward autofocus must produce intermediate animated offsets"
        )
        XCTAssertTrue(
            zip(offsetRecorder.offsets, offsetRecorder.offsets.dropFirst())
                .allSatisfy { previous, next in next >= previous - 1 },
            "Downward autofocus must not jump up before continuing downward"
        )
        XCTAssertEqual(scrollView.documentVisibleRect.minY, 700, accuracy: 1)
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
private final class SidebarRevealRequestRecorder {
    private(set) var generations: [Int] = []

    func record(_ request: SidebarSelectedItemRevealOwner.Request?) {
        guard let request,
              generations.last != request.generation else {
            return
        }
        generations.append(request.generation)
    }
}

@MainActor
private final class SidebarViewportRecorder {
    private(set) var viewports: [SpaceSidebarSnapshotViewport] = []

    func record(_ viewport: SpaceSidebarSnapshotViewport) {
        viewports.append(viewport)
    }

    func reset() {
        viewports.removeAll()
    }
}

@MainActor
@Observable
private final class SidebarSelectedItemLazyHarnessState {
    let itemIDs: [UUID]
    var selectedItemID: SidebarScrollTargetID?
    var isEnabled: Bool
    var visibleItemCount: Int

    init(
        itemCount: Int = 40,
        initiallySelectedItemIndex: Int? = nil,
        isEnabled: Bool = true,
        visibleItemCount: Int? = nil
    ) {
        let itemIDs = (0..<itemCount).map { _ in UUID() }
        self.itemIDs = itemIDs
        selectedItemID = initiallySelectedItemIndex.map {
            .regularTab(itemIDs[$0])
        }
        self.isEnabled = isEnabled
        self.visibleItemCount = visibleItemCount ?? itemCount
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
            isEnabled: true,
            motionMode: motionMode,
            restoredViewport: restoredViewport
        ) { surfaceObservation in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.itemIDs, id: \.self) { itemID in
                        Color.clear
                            .frame(height: 40)
                            .sidebarScrollTarget(.regularTab(itemID))
                    }
                }
                .background {
                    SidebarTestScrollSurfaceObserver(
                        observation: surfaceObservation
                    )
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
            isEnabled: true,
            motionMode: .reducedMotion,
            restoredViewport: nil
        ) { surfaceObservation in
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
                .background {
                    SidebarTestScrollSurfaceObserver(
                        observation: surfaceObservation
                    )
                }
            }
        }
    }
}

private struct SidebarSelectedItemPresentedLayoutHarness: View {
    let state: SidebarSelectedItemLazyHarnessState
    var motionMode: SidebarMotionPolicy.Mode = .reducedMotion
    var restoredViewport: SpaceSidebarSnapshotViewport? = nil
    var requestRecorder: SidebarRevealRequestRecorder? = nil
    var viewportRecorder: SidebarViewportRecorder? = nil

    var body: some View {
        SidebarSelectedItemVisibilityScope(
            revealPath: state.selectedItemID.map {
                SidebarSelectedItemRevealPath([$0])
            },
            isEnabled: state.isEnabled,
            motionMode: motionMode,
            targetResolution: .presentedLayout,
            restoredViewport: restoredViewport,
            onViewportChange: { viewport in
                viewportRecorder?.record(viewport)
            }
        ) { surfaceObservation in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(
                        Array(state.itemIDs.prefix(state.visibleItemCount)),
                        id: \.self
                    ) { _ in
                        Color.clear.frame(height: 40)
                    }
                }
                .scrollTargetLayout()
                .background {
                    ZStack {
                        SidebarTestScrollSurfaceObserver(
                            observation: surfaceObservation
                        )
                        SidebarPresentedLayoutHarnessPublisher(
                            itemIDs: state.itemIDs,
                            requestRecorder: requestRecorder
                        )
                    }
                    .frame(width: 0, height: 0)
                }
            }
        }
    }
}

private struct SidebarTestScrollSurfaceObserver: View {
    let observation: SidebarScrollSurfaceObservation
    @State private var dragAutoscrollRegistry =
        SidebarTabListDragAutoscrollRegistry()

    var body: some View {
        SidebarTabListScrollRegistrationViewRepresentable(
            isEnabled: true,
            indicatorColor: .clear,
            contentViewportWidth: 0,
            trailingProjection: 0,
            dragAutoscrollRegistry: dragAutoscrollRegistry,
            surfaceObservation: observation
        )
        .frame(width: 0, height: 0)
    }
}

private struct SidebarPresentedLayoutHarnessPublisher: View {
    let itemIDs: [UUID]
    let requestRecorder: SidebarRevealRequestRecorder?
    @Environment(\.sidebarSelectedItemRevealOwner) private var revealOwner

    var body: some View {
        Color.clear
            .onAppear(perform: publishLayout)
            .onChange(of: revealOwner?.request, initial: true) { _, request in
                requestRecorder?.record(request)
            }
    }

    private func publishLayout() {
        var targets: [
            SidebarScrollTargetID: SidebarAutofocusLayout.Target
        ] = [:]
        for (index, itemID) in itemIDs.enumerated() {
            let minY = CGFloat(index) * 40
            let target = SidebarAutofocusLayout.Target(
                minY: minY,
                maxY: minY + 40
            )
            targets[.regularTab(itemID)] = target
            targets[.launcher(itemID)] = target
        }
        revealOwner?.updateAutofocusLayout(
            SidebarAutofocusLayout(
                targets: targets,
                contentHeight: CGFloat(itemIDs.count) * 40
            )
        )
    }
}
