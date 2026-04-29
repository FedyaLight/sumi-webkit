import AppKit
import XCTest
@testable import Sumi

@MainActor
final class SidebarDDGHoverTests: XCTestCase {
    func testDirectMouseOverMutationDoesNotReportSwiftUIHover() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.isMouseOver = true
        view.isMouseOver = false

        XCTAssertEqual(reported, [])
    }

    func testTrackingViewReportsEventHoverImmediately() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.mouseEntered(with: Self.enterExitEvent(.mouseEntered, timestamp: 1))
        view.mouseExited(with: Self.enterExitEvent(.mouseExited, timestamp: 2))

        XCTAssertEqual(reported, [true, false])
    }

    func testTrackingViewDoesNotPublishWhenDisabledThroughLifecycle() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.mouseEntered(with: Self.enterExitEvent(.mouseEntered, timestamp: 1))
        reported.removeAll()

        view.setHoverTrackingEnabled(false)

        XCTAssertEqual(reported, [])
        XCTAssertFalse(view.currentEffectiveHover)
    }

    func testStaleMouseEnteredAfterNewerExitDoesNotPublishHover() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.mouseExited(with: Self.enterExitEvent(.mouseExited, timestamp: 10))
        view.mouseEntered(with: Self.enterExitEvent(.mouseEntered, timestamp: 9))

        XCTAssertEqual(reported, [])
        XCTAssertFalse(view.currentEffectiveHover)
    }

    func testStaleMouseExitedAfterNewerEnterDoesNotClearReportedHover() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.mouseEntered(with: Self.enterExitEvent(.mouseEntered, timestamp: 10))
        reported.removeAll()
        view.mouseExited(with: Self.enterExitEvent(.mouseExited, timestamp: 9))

        XCTAssertEqual(reported, [])
        XCTAssertTrue(view.currentEffectiveHover)
    }

    func testTrackingViewIsPaintlessNSViewNotAppKitControl() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        let nsView: NSView = view

        view.setHoverTrackingEnabled(false)

        XCTAssertFalse(nsView is NSControl)
        XCTAssertFalse(view.isOpaque)
        XCTAssertNil(view.backgroundLayer(createIfNeeded: true))
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

    func testActionVisibilityDoesNotChangeTrailingFadeReservation() {
        let reservedPadding = SidebarHoverChrome.trailingActionFadePadding

        XCTAssertEqual(reservedPadding, SidebarRowLayout.trailingActionFadePadding)
        XCTAssertFalse(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: true, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: true))
        XCTAssertEqual(reservedPadding, SidebarHoverChrome.trailingActionFadePadding)
    }

    func testHoverRoutingUsesNativeTrackingForDockedAndAppKitBridgeForCollapsedOverlay() {
        let docked = SidebarPresentationContext.docked(sidebarWidth: 280)
        let collapsedHidden = SidebarPresentationContext.collapsedHidden(sidebarWidth: 280)
        let collapsedVisible = SidebarPresentationContext.collapsedVisible(sidebarWidth: 280)

        XCTAssertTrue(SidebarHoverInputRouting.usesSwiftUIHover(in: docked))
        XCTAssertFalse(SidebarHoverInputRouting.usesAppKitHoverBridge(in: docked))
        XCTAssertFalse(SidebarHoverInputRouting.usesSwiftUIHover(in: collapsedHidden))
        XCTAssertTrue(SidebarHoverInputRouting.usesAppKitHoverBridge(in: collapsedHidden))
        XCTAssertFalse(SidebarHoverInputRouting.usesSwiftUIHover(in: collapsedVisible))
        XCTAssertTrue(SidebarHoverInputRouting.usesAppKitHoverBridge(in: collapsedVisible))
    }

    func testMigratedSidebarHoverDoesNotUseGlobalHoverOrDelayedHoverPatterns() throws {
        let sourceByPath = try Self.sidebarHoverSourceByPath()
        let sidebarBridgeSource = try XCTUnwrap(sourceByPath["Sumi/Components/Sidebar/SidebarDDGHover.swift"])
        let mouseOverDeclaration = try XCTUnwrap(sidebarBridgeSource.range(of: "@objc dynamic var isMouseOver"))
        let mouseOverDeclarationPrefix = sidebarBridgeSource[mouseOverDeclaration.lowerBound...].prefix(260)
        let forbiddenGlobalHoverTokens = [
            "sidebarHoverTarget",
            "SidebarHoverTarget",
            "setSidebarHover",
            "isSidebarHoverActive"
        ]
        let forbiddenHoverDelayTokens = [
            "asyncAfter",
            "Timer",
            "debounce",
            "withAnimation",
            ".animation(",
            "spring",
            "easeInOut"
        ]

        XCTAssertFalse(mouseOverDeclarationPrefix.contains("onHoverChanged"))
        XCTAssertFalse(mouseOverDeclarationPrefix.contains("setBindingIfNeeded"))

        for (path, source) in sourceByPath {
            for token in forbiddenGlobalHoverTokens {
                XCTAssertFalse(source.contains(token), "\(path) still contains \(token)")
            }

            for line in source.split(separator: "\n") where line.localizedCaseInsensitiveContains("hover") {
                for token in forbiddenHoverDelayTokens {
                    XCTAssertFalse(line.contains(token), "\(path) hover line still contains \(token): \(line)")
                }
            }
        }
    }

    private static func sidebarHoverSourceByPath() throws -> [String: String] {
        let paths = [
            "Sumi/Components/Sidebar/SidebarDDGHover.swift",
            "Sumi/Components/Sidebar/SpaceSection/SpaceTab.swift",
            "Sumi/Components/Sidebar/SpaceSection/SplitTabRow.swift",
            "Sumi/Components/Sidebar/SpaceSection/SpaceView.swift",
            "Sumi/Components/Sidebar/SpaceSection/ShortcutSidebarRow.swift",
            "Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift",
            "Sumi/Components/Sidebar/SpaceSection/SpaceTitle.swift",
            "Sumi/Components/Sidebar/PinnedButtons/PinnedTabView.swift",
            "Navigation/Sidebar/SpacesList/SpacesListItem.swift"
        ]

        return try Dictionary(
            uniqueKeysWithValues: paths.map { path in
                let url = repoRoot.appendingPathComponent(path)
                return (path, try String(contentsOf: url, encoding: .utf8))
            }
        )
    }

    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }

    private static func enterExitEvent(_ type: NSEvent.EventType, timestamp: TimeInterval) -> NSEvent {
        guard let event = NSEvent.enterExitEvent(
            with: type,
            location: .zero,
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
