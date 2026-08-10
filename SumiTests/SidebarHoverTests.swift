import AppKit
@testable import Sumi
import SwiftUI
import XCTest

@MainActor
final class SidebarHoverTests: XCTestCase {
    func testFolderPreviewOverlayRendersItsCandidateRows() {
        let windowState = BrowserWindowState()
        windowState.sidebarFolderPreview.open(
            request: SidebarFolderPreviewRequest(
                folderID: UUID(),
                folderName: "Preview fixture",
                candidates: [
                    FolderSearchCandidate(
                        id: "preview-candidate",
                        kind: .shortcut(UUID()),
                        title: "Preview candidate",
                        secondaryText: "example.com",
                        icon: .systemImage("globe"),
                        searchText: "Preview candidate example.com",
                        activate: {}
                    ),
                ],
                anchorRect: CGRect(x: 20, y: 20, width: 180, height: 36)
            ),
            sidebarPosition: .left,
            source: SidebarTransientPresentationSource(
                windowID: windowState.id,
                window: nil,
                originOwnerView: nil,
                coordinator: nil
            )
        )

        let host = NSHostingView(
            rootView: SidebarFolderPreviewOverlay(
                sidebarDragState: SidebarDragState()
            )
            .environment(windowState)
        )
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testCommandPaletteLayoutPolicyCapsWideWindowsAndShrinksNarrowWindows() {
        XCTAssertEqual(
            CommandPaletteLayoutPolicy.effectiveWidth(availableWindowWidth: 1_200),
            765
        )
        XCTAssertEqual(
            CommandPaletteLayoutPolicy.effectiveWidth(availableWindowWidth: 785),
            765
        )
        XCTAssertEqual(
            CommandPaletteLayoutPolicy.effectiveWidth(availableWindowWidth: 600),
            580
        )
        XCTAssertEqual(
            CommandPaletteLayoutPolicy.effectiveWidth(availableWindowWidth: 120),
            200
        )
    }

    func testCommandPaletteSuggestionHeightAdaptsBeforeZenScrollLimit() {
        XCTAssertEqual(CommandPaletteLayoutPolicy.suggestionsVisibleRowLimit, 5)
        XCTAssertEqual(CommandPaletteLayoutPolicy.suggestionsHeight(for: 0), 0)
        XCTAssertEqual(CommandPaletteLayoutPolicy.suggestionsHeight(for: 2), 104)
        XCTAssertEqual(CommandPaletteLayoutPolicy.resultsPanelHeight(for: 0), 0)
        XCTAssertEqual(CommandPaletteLayoutPolicy.resultsPanelHeight(for: 2), 116.5)
        XCTAssertEqual(CommandPaletteLayoutPolicy.layoutCount(forVisibleCount: 0), 0)
        XCTAssertEqual(CommandPaletteLayoutPolicy.layoutCount(forVisibleCount: 2), 2)
        XCTAssertEqual(CommandPaletteLayoutPolicy.layoutCount(forVisibleCount: 6), 5)
        XCTAssertTrue(
            CommandPaletteLayoutPolicy.shouldWaitForSuggestionLayout(
                isDebouncing: false,
                isLoading: true,
                visibleLayoutCount: 4
            )
        )
        XCTAssertFalse(
            CommandPaletteLayoutPolicy.shouldWaitForSuggestionLayout(
                isDebouncing: false,
                isLoading: true,
                visibleLayoutCount: 5
            )
        )
        XCTAssertEqual(
            CommandPaletteLayoutPolicy.suggestionsHeight(for: 6),
            CommandPaletteLayoutPolicy.suggestionsMaxHeight
        )
    }

    func testTrackingViewReportsEventHoverImmediately() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let coordinator = SidebarHoverBridge.Coordinator()
        var reported: [Bool] = []
        var isHovered = false
        coordinator.update(
            view: view,
            session: session,
            isHovered: Binding(
                get: { isHovered },
                set: {
                    isHovered = $0
                    reported.append($0)
                }
            ),
            isEnabled: true
        )

        view.mouseEntered(with: Self.enterExitEvent(
            .mouseEntered,
            timestamp: 1,
            location: NSPoint(x: 12, y: 12)
        ))
        view.mouseExited(with: Self.enterExitEvent(
            .mouseExited,
            timestamp: 2,
            location: NSPoint(x: 200, y: 100)
        ))

        XCTAssertEqual(reported, [true, false])
    }

    func testCoordinatorDetachClearsPublishedHover() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        var isHovered = false
        let coordinator = SidebarHoverBridge.Coordinator()
        coordinator.update(
            view: view,
            session: session,
            isHovered: Binding(
                get: { isHovered },
                set: { isHovered = $0 }
            ),
            isEnabled: true
        )

        view.mouseEntered(with: Self.enterExitEvent(
            .mouseEntered,
            timestamp: 1,
            location: NSPoint(x: 12, y: 12)
        ))
        coordinator.detach()

        XCTAssertFalse(isHovered)
    }

    func testEnteringSecondRegionClearsFirstEvenWhenAppKitMissesExit() {
        let window = Self.makeHoverWindow()
        let firstView = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let secondView = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 36, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        var firstHovered = false
        var secondHovered = false
        let firstCoordinator = SidebarHoverBridge.Coordinator()
        let secondCoordinator = SidebarHoverBridge.Coordinator()
        firstCoordinator.update(
            view: firstView,
            session: session,
            isHovered: Binding(
                get: { firstHovered },
                set: { firstHovered = $0 }
            ),
            isEnabled: true
        )
        secondCoordinator.update(
            view: secondView,
            session: session,
            isHovered: Binding(
                get: { secondHovered },
                set: { secondHovered = $0 }
            ),
            isEnabled: true
        )

        firstView.mouseEntered(with: Self.enterExitEvent(
            .mouseEntered,
            timestamp: 1,
            location: NSPoint(x: 12, y: 12)
        ))
        secondView.mouseEntered(with: Self.enterExitEvent(
            .mouseEntered,
            timestamp: 2,
            location: NSPoint(x: 12, y: 48)
        ))

        XCTAssertFalse(firstHovered)
        XCTAssertTrue(secondHovered)
    }

    func testRepeatedMissedExitsNeverLeaveAnEarlierRegionHovered() {
        let window = Self.makeHoverWindow()
        let session = SidebarHoverSession()
        let regionCount = 24
        var hovered = Array(repeating: false, count: regionCount)
        var views: [SidebarHoverTrackingView] = []
        var registrations: [SidebarHoverRegistration] = []

        for index in 0..<regionCount {
            let view = Self.addHoverView(
                to: window,
                frame: NSRect(x: 0, y: CGFloat(index * 5), width: 120, height: 5)
            )
            let registration = SidebarHoverRegistration()
            registration.update(
                view: view,
                session: session,
                isEnabled: true
            ) { isHovered, _ in
                hovered[index] = isHovered
            }
            views.append(view)
            registrations.append(registration)
        }

        for index in 0..<regionCount {
            views[index].mouseEntered(with: Self.enterExitEvent(
                .mouseEntered,
                timestamp: TimeInterval(index + 1),
                location: NSPoint(x: 12, y: CGFloat(index * 5 + 2))
            ))

            XCTAssertEqual(
                hovered.enumerated().filter(\.element).map(\.offset),
                [index]
            )
        }

        XCTAssertEqual(registrations.count, regionCount)
    }

    func testNestedRegionsCanBothBeHoveredFromOneGeometryResolution() {
        let window = Self.makeHoverWindow()
        let rowView = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 72)
        )
        let actionView = Self.addHoverView(
            to: window,
            frame: NSRect(x: 80, y: 10, width: 30, height: 30)
        )
        let session = SidebarHoverSession()
        var rowHovered = false
        var actionHovered = false
        let rowCoordinator = SidebarHoverBridge.Coordinator()
        let actionCoordinator = SidebarHoverBridge.Coordinator()
        rowCoordinator.update(
            view: rowView,
            session: session,
            isHovered: Binding(get: { rowHovered }, set: { rowHovered = $0 }),
            isEnabled: true
        )
        actionCoordinator.update(
            view: actionView,
            session: session,
            isHovered: Binding(get: { actionHovered }, set: { actionHovered = $0 }),
            isEnabled: true
        )

        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 90, y: 20)
        )

        XCTAssertTrue(rowHovered)
        XCTAssertTrue(actionHovered)
    }

    func testOverlayHoverShieldSuppressesCoveredRegionButKeepsNestedControlHovered() {
        let window = Self.makeHoverWindow()
        let coveredView = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 72)
        )
        let overlayView = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 72)
        )
        let controlView = Self.addHoverView(
            to: window,
            frame: NSRect(x: 80, y: 10, width: 30, height: 30)
        )
        let session = SidebarHoverSession()
        let coveredRegistration = SidebarHoverRegistration()
        let overlayRegistration = SidebarHoverRegistration()
        let controlRegistration = SidebarHoverRegistration()
        var coveredHovered = false
        var overlayHovered = false
        var controlHovered = false

        coveredRegistration.update(
            view: coveredView,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            coveredHovered = hovering
        }
        overlayRegistration.update(
            view: overlayView,
            session: session,
            isEnabled: true,
            layer: SidebarHoverLayer(priority: 40, occludesLowerPriority: true)
        ) { hovering, _ in
            overlayHovered = hovering
        }
        controlRegistration.update(
            view: controlView,
            session: session,
            isEnabled: true,
            layer: SidebarHoverLayer(priority: 50)
        ) { hovering, _ in
            controlHovered = hovering
        }

        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 90, y: 20)
        )

        XCTAssertFalse(coveredHovered)
        XCTAssertTrue(overlayHovered)
        XCTAssertTrue(controlHovered)
    }

    func testLifecycleChangesDoNotPublishSynchronouslyDuringNativeLayout() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()

        var publishedHover: [Bool] = []
        var isHovered = false
        let coordinator = SidebarHoverBridge.Coordinator()
        coordinator.update(
            view: view,
            session: session,
            isHovered: Binding(
                get: { isHovered },
                set: {
                    isHovered = $0
                    publishedHover.append($0)
                }
            ),
            isEnabled: true
        )

        view.updateTrackingAreas()
        view.updateTrackingAreas()

        XCTAssertEqual(publishedHover, [])
    }

    func testDetachingTrackingViewClearsHoverAfterLifecyclePass() async {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let registration = SidebarHoverRegistration()
        var reported: [Bool] = []
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            reported.append(hovering)
        }
        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 12, y: 12)
        )
        XCTAssertEqual(reported, [true])

        view.removeFromSuperview()

        XCTAssertEqual(reported, [true])
        await Task.yield()
        XCTAssertEqual(reported, [true, false])
    }

    /// Consumers that stand in for a `mouseenter` — the folder preview's show
    /// timer — need to tell a real pointer event apart from a hover the view
    /// inferred from the parked pointer.
    func testPointerEventsAreReportedAsPointerHover() {
        var pointerScreenLocation = NSPoint(x: 900, y: 700)
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession(
            pointerScreenLocation: { pointerScreenLocation }
        )
        let registration = SidebarHoverRegistration()
        var sources: [SidebarHoverChangeSource] = []
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { _, source in
            sources.append(source)
        }

        pointerScreenLocation.x += 20
        view.mouseEntered(with: Self.enterExitEvent(
            .mouseEntered,
            timestamp: 1,
            location: NSPoint(x: 12, y: 12)
        ))
        pointerScreenLocation.x += 20
        view.mouseExited(with: Self.enterExitEvent(
            .mouseExited,
            timestamp: 2,
            location: NSPoint(x: 200, y: 100)
        ))

        XCTAssertEqual(sources, [.pointer, .pointer])
    }

    func testStartupTrackingEnterWithoutPointerMovementDoesNotArmFolderPreview() async throws {
        var pointerScreenLocation = NSPoint(x: 900, y: 700)
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession(
            pointerScreenLocation: { pointerScreenLocation }
        )
        let coordinator = SidebarFolderPreviewAnchorBridge.Coordinator()
        var openCount = 0
        coordinator.update(
            view: view,
            hoverSession: session,
            isEnabled: true,
            onOpen: { _, _ in openCount += 1 },
            onHoverChanged: { _ in }
        )

        view.mouseEntered(with: Self.enterExitEvent(
            .mouseEntered,
            timestamp: 1,
            location: NSPoint(x: 12, y: 12)
        ))

        try await Task.sleep(
            nanoseconds: SidebarFolderPreviewHoverPolicy.showDelayNanoseconds + 50_000_000
        )
        XCTAssertEqual(openCount, 0)

        pointerScreenLocation.x += 20
        view.mouseExited(with: Self.enterExitEvent(
            .mouseExited,
            timestamp: 2,
            location: NSPoint(x: 200, y: 100)
        ))
        pointerScreenLocation.x += 20
        view.mouseEntered(with: Self.enterExitEvent(
            .mouseEntered,
            timestamp: 3,
            location: NSPoint(x: 12, y: 12)
        ))

        try await Task.sleep(
            nanoseconds: SidebarFolderPreviewHoverPolicy.showDelayNanoseconds + 50_000_000
        )
        XCTAssertEqual(openCount, 1)
    }

    func testTrackingViewReconcilesHoverWhenMouseIsAlreadyInsideAfterReenable() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let registration = SidebarHoverRegistration()
        var reported: [(hovering: Bool, source: SidebarHoverChangeSource)] = []
        registration.update(
            view: view,
            session: session,
            isEnabled: false
        ) { hovering, source in
            reported.append((hovering, source))
        }
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { hovering, source in
            reported.append((hovering, source))
        }
        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 24, y: 18)
        )

        XCTAssertEqual(reported.map(\.hovering), [true])
        XCTAssertEqual(reported.map(\.source), [.lifecycle])
    }

    func testTrackingViewPublishesBalancedExitWhenDisabled() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let registration = SidebarHoverRegistration()
        var reported: [Bool] = []
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            reported.append(hovering)
        }

        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 12, y: 12)
        )
        reported.removeAll()
        registration.update(
            view: view,
            session: session,
            isEnabled: false
        ) { hovering, _ in
            reported.append(hovering)
        }

        XCTAssertEqual(reported, [false])
        XCTAssertNil(view.hitTest(NSPoint(x: 12, y: 12)))
    }

    func testScrollRestoreDoesNotAccumulateHoveringRows() async {
        let window = Self.makeHoverWindow()
        let windowState = BrowserWindowState()
        let coordinator = NativeSurfaceScrollHoverCoordinator(
            hoverRestoreDelayNanoseconds: 0,
            sleepForNanoseconds: { _ in }
        )
        let model = ScrollHoverHarnessModel()
        var firstHovered = false
        var secondHovered = false
        let host = NSHostingView(
            rootView: ScrollHoverHarness(
                windowState: windowState,
                coordinator: coordinator,
                model: model,
                firstHovered: Binding(
                    get: { firstHovered },
                    set: { firstHovered = $0 }
                ),
                secondHovered: Binding(
                    get: { secondHovered },
                    set: { secondHovered = $0 }
                )
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 72)
        window.contentView?.addSubview(host)
        host.layoutSubtreeIfNeeded()
        await waitForHoverPasses()

        let session = windowState.sidebarInteractionState.hoverSession
        // Model a reused row whose SwiftUI state is still hovered while its
        // native registration has not published hover for this incarnation.
        firstHovered = true
        XCTAssertTrue(firstHovered)
        XCTAssertFalse(secondHovered)

        coordinator.setScrolling(true, region: "sidebar")
        model.contentOffset = -36
        await waitForHoverPasses()
        host.layoutSubtreeIfNeeded()

        XCTAssertFalse(firstHovered)
        XCTAssertFalse(secondHovered)

        coordinator.setScrolling(false, region: "sidebar")
        await waitForHoverPasses()
        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 24, y: 54)
        )

        XCTAssertFalse(firstHovered)
        XCTAssertTrue(secondHovered)
    }

    func testStaleMouseEnteredAfterNewerExitDoesNotPublishHover() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let registration = SidebarHoverRegistration()
        var reported: [Bool] = []
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            reported.append(hovering)
        }

        view.mouseExited(with: Self.enterExitEvent(
            .mouseExited,
            timestamp: 10,
            location: NSPoint(x: 200, y: 100)
        ))
        view.mouseEntered(with: Self.enterExitEvent(
            .mouseEntered,
            timestamp: 9,
            location: NSPoint(x: 12, y: 12)
        ))

        XCTAssertEqual(reported, [])
    }

    func testStaleMouseExitedAfterNewerEnterDoesNotClearReportedHover() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let registration = SidebarHoverRegistration()
        var reported: [Bool] = []
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            reported.append(hovering)
        }

        view.mouseEntered(with: Self.enterExitEvent(
            .mouseEntered,
            timestamp: 10,
            location: NSPoint(x: 12, y: 12)
        ))
        reported.removeAll()
        view.mouseExited(with: Self.enterExitEvent(
            .mouseExited,
            timestamp: 9,
            location: NSPoint(x: 200, y: 100)
        ))

        XCTAssertEqual(reported, [])
    }

    func testSuspendingSessionClearsHoverSynchronously() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let registration = SidebarHoverRegistration()
        var isHovered = false
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            isHovered = hovering
        }
        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 12, y: 12)
        )

        session.setSuspended(true)

        XCTAssertFalse(isHovered)
    }

    func testScrollSuppressionClearsHoverBeforeRestoringCurrentGeometry() {
        let window = Self.makeHoverWindow()
        let firstView = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let secondView = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 36, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let firstRegistration = SidebarHoverRegistration()
        let secondRegistration = SidebarHoverRegistration()
        var firstHovered = false
        var secondHovered = false
        firstRegistration.update(
            view: firstView,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            firstHovered = hovering
        }
        secondRegistration.update(
            view: secondView,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            secondHovered = hovering
        }

        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 12, y: 12)
        )
        XCTAssertTrue(firstHovered)
        XCTAssertFalse(secondHovered)

        session.setScrollSuppressed(true)

        XCTAssertFalse(firstHovered)
        XCTAssertFalse(secondHovered)

        firstView.frame.origin.y = 36
        secondView.frame.origin.y = 0
        session.setScrollSuppressed(false)
        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 12, y: 12)
        )

        XCTAssertFalse(firstHovered)
        XCTAssertTrue(secondHovered)
    }

    func testScrollRestoreDoesNotOverrideInteractionSuspension() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let registration = SidebarHoverRegistration()
        var isHovered = false
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            isHovered = hovering
        }
        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 12, y: 12)
        )
        XCTAssertTrue(isHovered)

        session.setSuspended(true)
        session.setScrollSuppressed(true)
        session.setScrollSuppressed(false)
        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 12, y: 12)
        )

        XCTAssertFalse(isHovered)

        session.setSuspended(false)
        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 12, y: 12)
        )

        XCTAssertTrue(isHovered)
    }

    func testApplicationDeactivationClearsEveryRegisteredHover() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let registration = SidebarHoverRegistration()
        var isHovered = false
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { hovering, _ in
            isHovered = hovering
        }
        session.reconcile(
            window: window,
            mouseLocationInWindow: NSPoint(x: 12, y: 12)
        )

        NotificationCenter.default.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )

        XCTAssertFalse(isHovered)
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification,
            object: NSApp
        )
    }

    func testTrackingViewIsPaintlessNSViewNotAppKitControl() {
        let view = SidebarHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        let nsView: NSView = view

        view.setHoverTrackingEnabled(false)

        XCTAssertFalse(nsView is NSControl)
        XCTAssertFalse(view.isOpaque)
        XCTAssertNil(view.hitTest(NSPoint(x: 12, y: 12)))
    }

    func testHoverSensorDoesNotRequestContinuousMouseMovedEvents() {
        let view = SidebarHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))

        view.updateTrackingAreas()

        XCTAssertFalse(view.trackingAreas.contains { $0.options.contains(.mouseMoved) })
    }

    func testSelectedStateWinsOverHoverState() {
        XCTAssertEqual(
            SidebarHoverChrome.visualState(isSelected: true, isHovered: true),
            .selected
        )
        XCTAssertEqual(
            SidebarHoverChrome.visualState(isSelected: false, isHovered: true),
            .hovered
        )
        XCTAssertEqual(
            SidebarHoverChrome.visualState(isSelected: false, isHovered: false),
            .idle
        )
    }

    func testTrailingActionVisibilityPolicy() {
        XCTAssertFalse(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: true, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: true))
    }

    private static func makeHoverWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private static func addHoverView(
        to window: NSWindow,
        frame: NSRect
    ) -> SidebarHoverTrackingView {
        let view = SidebarHoverTrackingView(frame: frame)
        window.contentView?.addSubview(view)
        return view
    }

    private static func enterExitEvent(
        _ type: NSEvent.EventType,
        timestamp: TimeInterval,
        location: NSPoint = .zero
    ) -> NSEvent {
        guard let event = NSEvent.enterExitEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 1,
            userData: nil
        ) else {
            fatalError("Failed to create \(type) event")
        }
        return event
    }

    private func waitForHoverPasses() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}

@MainActor
private final class ScrollHoverHarnessModel: ObservableObject {
    @Published var contentOffset: CGFloat = 0
}

@MainActor
private struct ScrollHoverHarness: View {
    let windowState: BrowserWindowState
    let coordinator: NativeSurfaceScrollHoverCoordinator
    @ObservedObject var model: ScrollHoverHarnessModel
    @Binding var firstHovered: Bool
    @Binding var secondHovered: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(width: 120, height: 36)
                    .contentShape(Rectangle())
                    .sidebarHover($firstHovered)

                Color.clear
                    .frame(width: 120, height: 36)
                    .contentShape(Rectangle())
                    .sidebarHover($secondHovered)
            }
            .offset(y: model.contentOffset)
        }
        .frame(width: 120, height: 72)
        .environment(windowState)
        .modifier(ScrollHoverEnvironmentHarnessModifier(coordinator: coordinator))
    }
}

private struct ScrollHoverEnvironmentHarnessModifier: ViewModifier {
    @ObservedObject var coordinator: NativeSurfaceScrollHoverCoordinator

    func body(content: Content) -> some View {
        content.environment(
            \.nativeSurfaceHoverUpdatesEnabled,
            coordinator.hoverUpdatesEnabled
        )
    }
}
