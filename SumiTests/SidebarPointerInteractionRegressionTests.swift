import AppKit
import Observation
import SwiftUI
@testable import Sumi
import XCTest

@MainActor
final class SidebarPointerInteractionRegressionTests: XCTestCase {
    func testColdShortcutMaterializationContinuesIntoDragFromSameEventStream() throws {
        let monitor = TestSidebarPointerEventMonitor()
        var nativeDragStartCount = 0
        let interactionState = SidebarInteractionState(
            pointerEventMonitor: monitor,
            nativeDragStarter: SidebarNativeDragSessionStarter { _, _, _ in
                nativeDragStartCount += 1
            }
        )
        let model = ShortcutMaterializationHarness()
        let windowState = BrowserWindowState(
            sidebarInteractionState: interactionState
        )
        windowState.currentSpaceId = model.pin.spaceId
        let dragState = SidebarDragState(interactionState: interactionState)
        let host = NSHostingView(
            rootView: ShortcutMaterializationHarnessView(model: model)
                .environment(windowState)
                .environment(interactionState)
                .environment(\.sidebarDragStateHandle, dragState)
                .environmentObject(GlanceManager())
        )
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 36)
        let window = Self.makeWindow(contentView: host)
        defer {
            dragState.resetInteractionState()
            window.contentView = nil
            window.close()
        }

        host.layoutSubtreeIfNeeded()
        let originalOwner = try XCTUnwrap(
            host.sidebarInteractiveOwner(
                identifier: ShortcutMaterializationHarnessView.sourceID
            )
        )
        originalOwner.mouseDown(
            with: Self.mouseEvent(
                .leftMouseDown,
                location: NSPoint(x: 60, y: 18),
                windowNumber: window.windowNumber
            )
        )
        host.layoutSubtreeIfNeeded()

        XCTAssertNotNil(model.liveTab)
        XCTAssertTrue(interactionState.hasActivePointerSession)
        XCTAssertEqual(monitor.startCount, 1)

        let consumed = monitor.send(
            Self.mouseEvent(
                .leftMouseDragged,
                location: NSPoint(x: 60, y: 60),
                windowNumber: window.windowNumber
            )
        )

        XCTAssertTrue(consumed)
        XCTAssertTrue(dragState.isDragging)
        XCTAssertTrue(dragState.isInternalDragSession)
        XCTAssertEqual(nativeDragStartCount, 1)
        XCTAssertFalse(interactionState.hasActivePointerSession)
        XCTAssertEqual(monitor.stopCount, 1)
    }

    func testColdShortcutNeverGainsPressVisualWhenMaterialized() throws {
        let monitor = TestSidebarPointerEventMonitor()
        let interactionState = SidebarInteractionState(
            pointerEventMonitor: monitor
        )
        let model = ShortcutMaterializationHarness()
        let windowState = BrowserWindowState(
            sidebarInteractionState: interactionState
        )
        let host = NSHostingView(
            rootView: ShortcutMaterializationHarnessView(model: model)
                .environment(windowState)
                .environment(interactionState)
                .environmentObject(GlanceManager())
        )
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 36)
        let window = Self.makeWindow(contentView: host)
        defer {
            window.contentView = nil
            window.close()
        }

        host.layoutSubtreeIfNeeded()
        let owner = try XCTUnwrap(
            host.sidebarInteractiveOwner(
                identifier: ShortcutMaterializationHarnessView.sourceID
            )
        )
        owner.mouseDown(
            with: Self.mouseEvent(
                .leftMouseDown,
                windowNumber: window.windowNumber
            )
        )
        host.layoutSubtreeIfNeeded()

        XCTAssertNotNil(model.liveTab)
        XCTAssertTrue(
            interactionState.hasActivePointerSession(
                for: ShortcutMaterializationHarnessView.sourceID
            )
        )
        XCTAssertFalse(
            interactionState.presentsPressVisual(
                for: ShortcutMaterializationHarnessView.sourceID
            )
        )

        XCTAssertTrue(
            monitor.send(
                Self.mouseEvent(
                    .leftMouseUp,
                    windowNumber: window.windowNumber
                )
            )
        )
        XCTAssertFalse(interactionState.hasActivePointerSession)
    }

    func testAcceptedDragSurvivesPresenterConfigurationDisablement() throws {
        let monitor = TestSidebarPointerEventMonitor()
        var nativeDragStartCount = 0
        let state = SidebarInteractionState(
            pointerEventMonitor: monitor,
            nativeDragStarter: SidebarNativeDragSessionStarter { _, _, _ in
                nativeDragStartCount += 1
            }
        )
        let dragState = SidebarDragState(interactionState: state)
        let spaceID = UUID()
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = spaceID
        let item = SumiDragItem(tabId: UUID(), title: "Initializing launcher")
        let source = SidebarDragSourceConfiguration(
            item: item,
            sourceZone: .spacePinned(spaceID),
            previewKind: .row
        )
        let scope = try XCTUnwrap(
            SidebarDragScope(
                windowState: windowState,
                sourceZone: source.sourceZone,
                item: item
            )
        )
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 36)
        )
        let window = Self.makeWindow(contentView: view)
        defer {
            dragState.resetInteractionState()
            view.prepareForDismantle()
            window.contentView = nil
            window.close()
        }
        view.sidebarDragState = dragState
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                dragSource: source,
                dragScope: scope,
                pageActivation: {},
                sourceID: "initializing-launcher"
            )
        )

        view.mouseDown(
            with: Self.mouseEvent(
                .leftMouseDown,
                windowNumber: window.windowNumber
            )
        )
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                isInteractionEnabled: false,
                interactionState: state,
                pageActivation: {},
                sourceID: "initializing-launcher"
            )
        )

        XCTAssertTrue(
            monitor.send(
                Self.mouseEvent(
                    .leftMouseDragged,
                    location: NSPoint(x: 40, y: 12),
                    windowNumber: window.windowNumber
                )
            )
        )
        XCTAssertEqual(nativeDragStartCount, 1)
        XCTAssertTrue(dragState.isDragging)
    }

    func testTrackedReleaseRunsCapturedActionAndStopsMonitoring() {
        let monitor = TestSidebarPointerEventMonitor()
        let state = SidebarInteractionState(pointerEventMonitor: monitor)
        var releaseCount = 0
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 36)
        )
        let window = Self.makeWindow(contentView: view)
        defer {
            view.prepareForDismantle()
            window.contentView = nil
            window.close()
        }
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                releaseAction: { releaseCount += 1 },
                sourceID: "release-row"
            )
        )

        view.mouseDown(
            with: Self.mouseEvent(
                .leftMouseDown,
                windowNumber: window.windowNumber
            )
        )
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertTrue(
            monitor.send(
                Self.mouseEvent(
                    .leftMouseUp,
                    windowNumber: window.windowNumber
                )
            )
        )

        XCTAssertEqual(releaseCount, 1)
        XCTAssertFalse(state.hasActivePointerSession)
        XCTAssertEqual(monitor.stopCount, 1)
    }

    func testOwnerGapConsumesSameWindowReleaseAndEndsSession() {
        let monitor = TestSidebarPointerEventMonitor()
        let state = SidebarInteractionState(pointerEventMonitor: monitor)
        let dragState = SidebarDragState(interactionState: state)
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 36)
        )
        let window = Self.makeWindow(contentView: view)
        defer {
            window.contentView = nil
            window.close()
        }
        view.sidebarDragState = dragState
        view.update(
            configuration: Self.draggableConfiguration(
                state: state,
                windowState: BrowserWindowState(),
                sourceID: "departed-row"
            )
        )
        view.mouseDown(
            with: Self.mouseEvent(
                .leftMouseDown,
                windowNumber: window.windowNumber
            )
        )
        view.prepareForDismantle()
        view.removeFromSuperview()

        XCTAssertTrue(dragState.isInternalDragGeometryArmed)
        XCTAssertTrue(
            monitor.send(
                Self.mouseEvent(
                    .leftMouseUp,
                    windowNumber: window.windowNumber
                )
            )
        )
        XCTAssertFalse(state.hasActivePointerSession)
        XCTAssertFalse(dragState.isInternalDragGeometryArmed)
    }

    func testOwnerGapDoesNotConsumeAnotherWindowsPointerEvent() {
        let monitor = TestSidebarPointerEventMonitor()
        let state = SidebarInteractionState(pointerEventMonitor: monitor)
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 36)
        )
        let sourceWindow = Self.makeWindow(contentView: view)
        let otherWindow = Self.makeWindow(contentView: NSView())
        defer {
            sourceWindow.contentView = nil
            sourceWindow.close()
            otherWindow.contentView = nil
            otherWindow.close()
        }
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                pageActivation: {},
                sourceID: "departed-row"
            )
        )
        view.mouseDown(
            with: Self.mouseEvent(
                .leftMouseDown,
                windowNumber: sourceWindow.windowNumber
            )
        )
        view.prepareForDismantle()
        view.removeFromSuperview()

        XCTAssertFalse(
            monitor.send(
                Self.mouseEvent(
                    .leftMouseUp,
                    windowNumber: otherWindow.windowNumber
                )
            )
        )
        XCTAssertTrue(state.hasActivePointerSession)
        XCTAssertTrue(
            monitor.send(
                Self.mouseEvent(
                    .leftMouseUp,
                    windowNumber: sourceWindow.windowNumber
                )
            )
        )
        XCTAssertFalse(state.hasActivePointerSession)
    }

    func testSameIdentityOwnerInAnotherWindowCannotAdoptSession() {
        let monitor = TestSidebarPointerEventMonitor()
        let state = SidebarInteractionState(pointerEventMonitor: monitor)
        let sourceView = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 36)
        )
        let replacementView = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 36)
        )
        let sourceWindow = Self.makeWindow(contentView: sourceView)
        let otherWindow = Self.makeWindow(contentView: replacementView)
        var sourceReleaseCount = 0
        var replacementReleaseCount = 0
        defer {
            sourceWindow.contentView = nil
            sourceWindow.close()
            otherWindow.contentView = nil
            otherWindow.close()
        }
        sourceView.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                releaseAction: { sourceReleaseCount += 1 },
                sourceID: "shared-row"
            )
        )
        sourceView.mouseDown(
            with: Self.mouseEvent(
                .leftMouseDown,
                windowNumber: sourceWindow.windowNumber
            )
        )
        sourceView.prepareForDismantle()
        replacementView.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                releaseAction: { replacementReleaseCount += 1 },
                sourceID: "shared-row"
            )
        )

        XCTAssertTrue(
            monitor.send(
                Self.mouseEvent(
                    .leftMouseUp,
                    windowNumber: sourceWindow.windowNumber
                )
            )
        )
        XCTAssertEqual(sourceReleaseCount, 0)
        XCTAssertEqual(replacementReleaseCount, 0)
        XCTAssertFalse(state.hasActivePointerSession)
    }

    func testPointerEventsAreUntrackedWithoutAcceptedSession() {
        let monitor = TestSidebarPointerEventMonitor()
        _ = SidebarInteractionState(pointerEventMonitor: monitor)

        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertFalse(monitor.send(Self.mouseEvent(.leftMouseDragged)))
        XCTAssertFalse(monitor.send(Self.mouseEvent(.leftMouseUp)))
    }

    func testNestedActionOwnerWinsOverGenericDraggableRowOwner() {
        let state = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: state
        )
        let controller = SidebarContextMenuController(
            interactionState: state,
            transientSessionCoordinator: coordinator
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 36),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        let rowOwner = SidebarInteractiveItemView(frame: container.bounds)
        let actionOwner = SidebarInteractiveItemView(
            frame: NSRect(x: 140, y: 7, width: 22, height: 22)
        )
        let actionPoint = NSPoint(x: 151, y: 18)
        let spaceID = UUID()

        rowOwner.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Launcher"),
                    sourceZone: .spacePinned(spaceID),
                    previewKind: .row
                ),
                pageActivation: {},
                sourceID: "launcher-row"
            )
        )
        actionOwner.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                releaseAction: {},
                sourceID: "launcher-action"
            )
        )

        window.contentView = container
        container.addSubview(rowOwner)
        container.addSubview(actionOwner)
        rowOwner.contextMenuController = controller
        actionOwner.contextMenuController = controller
        defer {
            rowOwner.prepareForDismantle()
            actionOwner.prepareForDismantle()
            window.contentView = nil
            window.close()
        }

        let routedHit = SidebarColumnHitTestRouting.routedHit(
            point: actionPoint,
            in: container,
            originalHit: actionOwner,
            hostedSidebarView: container,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )

        XCTAssertIdentical(routedHit, actionOwner)
    }

    private static func draggableConfiguration(
        state: SidebarInteractionState,
        windowState: BrowserWindowState,
        sourceID: String
    ) -> SidebarAppKitItemConfiguration {
        let spaceID = UUID()
        windowState.currentSpaceId = spaceID
        let item = SumiDragItem(tabId: UUID(), title: sourceID)
        let source = SidebarDragSourceConfiguration(
            item: item,
            sourceZone: .spacePinned(spaceID),
            previewKind: .row
        )
        return SidebarAppKitItemConfiguration(
            interactionState: state,
            dragSource: source,
            dragScope: SidebarDragScope(
                windowState: windowState,
                sourceZone: source.sourceZone,
                item: item
            ),
            pageActivation: {},
            sourceID: sourceID
        )
    }

    private static func makeWindow(contentView: NSView) -> NSWindow {
        let contentSize = contentView.frame.size
        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: contentSize.width > 0 ? contentSize.width : 280,
            height: contentSize.height > 0 ? contentSize.height : 80
        )
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        return window
    }

    private static func mouseEvent(
        _ type: NSEvent.EventType,
        location: NSPoint = NSPoint(x: 12, y: 12),
        windowNumber: Int = 0
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }
}

@MainActor
private final class TestSidebarPointerEventMonitor: SidebarPointerEventMonitoring {
    private var handler: ((NSEvent) -> Bool)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(_ handler: @escaping (NSEvent) -> Bool) {
        guard self.handler == nil else { return }
        self.handler = handler
        startCount += 1
    }

    func stop() {
        guard handler != nil else { return }
        handler = nil
        stopCount += 1
    }

    func send(_ event: NSEvent) -> Bool {
        handler?(event) ?? false
    }
}

@MainActor
@Observable
private final class ShortcutMaterializationHarness {
    let pin = ShortcutPin(
        id: UUID(),
        role: .spacePinned,
        spaceId: UUID(),
        index: 0,
        launchURL: URL(string: "https://example.com/launcher")!,
        title: "Launcher"
    )
    var liveTab: Sumi.Tab?

    static func makeLiveTab(pinID: UUID) -> Sumi.Tab {
        let tab = Sumi.Tab(
            url: URL(string: "https://example.com/live")!,
            name: "Live",
            favicon: "globe"
        )
        tab.shortcutPinId = pinID
        return tab
    }
}

private struct ShortcutMaterializationHarnessView: View {
    static let sourceID = "space-pinned-shortcut-materialization-test"

    let model: ShortcutMaterializationHarness

    var body: some View {
        ShortcutSidebarRow(
            pin: model.pin,
            liveTab: model.liveTab,
            faviconPartition: .regular(nil),
            faviconImageReader:
                TabDependencyIsolationDefaults.faviconCapabilities.images,
            runtimeAffordance:
                model.liveTab == nil ? .launcherOnly : .liveSelected,
            accessibilityID: Self.sourceID,
            action: {
                guard model.liveTab == nil else { return }
                model.liveTab = ShortcutMaterializationHarness.makeLiveTab(
                    pinID: model.pin.id
                )
            },
            dragSourceZone: .spacePinned(model.pin.spaceId!),
            onResetToLaunchURL: nil,
            onUnload: {},
            onRemove: {}
        )
        .frame(width: 280, height: 36)
    }
}

private extension NSView {
    func sidebarInteractiveOwner(
        identifier: String
    ) -> SidebarInteractiveItemView? {
        if let owner = self as? SidebarInteractiveItemView,
           owner.identifier?.rawValue == identifier {
            return owner
        }
        for subview in subviews {
            if let owner = subview.sidebarInteractiveOwner(
                identifier: identifier
            ) {
                return owner
            }
        }
        return nil
    }
}
