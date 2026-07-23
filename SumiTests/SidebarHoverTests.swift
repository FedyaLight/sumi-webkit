import AppKit
@testable import Sumi
import SwiftUI
import XCTest

@MainActor
final class SidebarHoverTests: XCTestCase {
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

    func testCommandPaletteOutsideClickRoutingKeepsInsideCardEvent() throws {
        let event = try Self.mouseDownEvent()
        var closeCount = 0

        let result = CommandPaletteOutsideClickRouting.monitorResult(
            for: event,
            isCommandPaletteVisible: true,
            isEventInsideCard: true
        ) {
            closeCount += 1
        }

        XCTAssertIdentical(result, event)
        XCTAssertEqual(closeCount, 0)
    }

    func testCommandPaletteOutsideClickRoutingClosesOutsideCardAndPreservesEvent() throws {
        let event = try Self.mouseDownEvent()
        var closeCount = 0

        let result = CommandPaletteOutsideClickRouting.monitorResult(
            for: event,
            isCommandPaletteVisible: true,
            isEventInsideCard: false
        ) {
            closeCount += 1
        }

        XCTAssertIdentical(result, event)
        XCTAssertEqual(closeCount, 1)
    }

    func testCommandPaletteCardHitDetectionSeparatesInsideAndOutsideGeometry() {
        let cardView = Self.makeCommandPaletteCardView()

        XCTAssertTrue(CommandPaletteOutsideClickRouting.isLocationInsideCard(
            NSPoint(x: 32, y: 32),
            cardView: cardView
        ))
        XCTAssertFalse(CommandPaletteOutsideClickRouting.isLocationInsideCard(
            NSPoint(x: 180, y: 90),
            cardView: cardView
        ))
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

    /// Consumers that stand in for a `mouseenter` — the folder preview's show
    /// timer — need to tell a real pointer event apart from a hover the view
    /// inferred from the parked pointer.
    func testPointerEventsAreReportedAsPointerHover() {
        let window = Self.makeHoverWindow()
        let view = Self.addHoverView(
            to: window,
            frame: NSRect(x: 0, y: 0, width: 120, height: 36)
        )
        let session = SidebarHoverSession()
        let registration = SidebarHoverRegistration()
        var sources: [SidebarHoverChangeSource] = []
        registration.update(
            view: view,
            session: session,
            isEnabled: true
        ) { _, source in
            sources.append(source)
        }

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

        XCTAssertEqual(sources, [.pointer, .pointer])
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

    func testActionVisibilityDoesNotChangeTrailingPaddingReservation() {
        let reservedPadding = SidebarHoverChrome.trailingPadding(showsTrailingAction: true)

        XCTAssertEqual(reservedPadding, SidebarRowLayout.trailingActionPadding)
        XCTAssertFalse(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: true, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: true))
        XCTAssertEqual(reservedPadding, SidebarHoverChrome.trailingPadding(showsTrailingAction: true))
    }

    private static func makeCommandPaletteCardView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 140))
        let view = NSView(frame: NSRect(x: 20, y: 20, width: 100, height: 60))
        container.addSubview(view)
        return view
    }

    private static func mouseDownEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
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
}
