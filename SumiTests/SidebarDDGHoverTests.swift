import AppKit
import XCTest
@testable import Sumi

@MainActor
final class SidebarDDGHoverTests: XCTestCase {
    func testFloatingBarLayoutPolicyCapsWideWindowsAndShrinksNarrowWindows() {
        XCTAssertEqual(
            FloatingBarLayoutPolicy.effectiveWidth(availableWindowWidth: 1_200),
            765
        )
        XCTAssertEqual(
            FloatingBarLayoutPolicy.effectiveWidth(availableWindowWidth: 785),
            765
        )
        XCTAssertEqual(
            FloatingBarLayoutPolicy.effectiveWidth(availableWindowWidth: 600),
            580
        )
        XCTAssertEqual(
            FloatingBarLayoutPolicy.effectiveWidth(availableWindowWidth: 120),
            200
        )
    }

    func testFloatingBarViewDoesNotReadGlobalKeyWindowForLayout() throws {
        let source = try Self.source(named: "FloatingBar/FloatingBarView.swift")

        XCTAssertTrue(source.contains("FloatingBarLayoutPolicy"))
        XCTAssertTrue(source.contains("GeometryReader"))
        XCTAssertFalse(source.contains("keyWindow"))
        XCTAssertFalse(source.contains("FloatingBarChromeMetrics"))
    }

    func testFloatingBarUsesWindowLevelHostForStableSidebarIndependentPosition() throws {
        let source = try Self.source(named: "App/Window/WindowView.swift")
        let webContentStart = try XCTUnwrap(source.range(of: "private func WebContent()"))
        let webContentBody = String(source[webContentStart.lowerBound...])

        XCTAssertTrue(source.contains("WindowTransientChromeZIndex.floatingBar"))
        XCTAssertTrue(source.contains("FloatingBarChromeHost"))
        XCTAssertFalse(webContentBody.contains("FloatingBarChromeHost"))
    }

    func testFloatingBarInputAffordancesMatchZenFloatingUrlbar() throws {
        let source = try Self.source(named: "FloatingBar/FloatingBarView.swift")

        XCTAssertTrue(source.contains(".tint(tokens.primaryText)"))
        XCTAssertTrue(source.contains(".lineLimit(1)"))
        XCTAssertTrue(source.contains("focusSearchField(selectAll: false)"))
        XCTAssertTrue(source.contains("triggerSearchModeAnimation"))
        XCTAssertTrue(source.contains("FloatingBarSearchModeGlowView"))
        XCTAssertTrue(source.contains("ScrollView(.vertical)"))
        XCTAssertTrue(source.contains(".scrollIndicators(shouldScroll ? .visible : .hidden)"))
        XCTAssertTrue(source.contains("suggestionsMaxHeight"))
        XCTAssertTrue(source.contains("suggestionsVisibleRowLimit = 5"))
        XCTAssertTrue(source.contains("selectedBackground = tokens.accent.opacity"))
        XCTAssertTrue(source.contains("deleteHistoryEntry"))
        XCTAssertFalse(source.contains("NSAlert"))

        let searchManagerSource = try Self.source(named: "Sumi/Managers/SearchManager/SearchManager.swift")
        XCTAssertTrue(searchManagerSource.contains("maxVisibleSuggestions = 10"))
        let suggestionEngineSource = try Self.source(named: "Sumi/Managers/SearchManager/SumiSuggestionEngine.swift")
        XCTAssertTrue(suggestionEngineSource.contains("maximumNumberOfSuggestions = 12"))
        XCTAssertTrue(suggestionEngineSource.contains("duckDuckGoSuggestions(from: apiSuggestions"))

        let searchUtilsSource = try Self.source(named: "Sumi/Managers/SearchManager/Utils.swift")
        XCTAssertTrue(searchUtilsSource.contains("import URLPredictor"))
        XCTAssertTrue(searchUtilsSource.contains("Classifier.classify"))

        let historyRowSource = try Self.source(named: "FloatingBar/FloatingBar Accessories/HistorySuggestionItem.swift")
        XCTAssertTrue(historyRowSource.contains("isDeleteConfirming"))
        XCTAssertTrue(historyRowSource.contains("isDeleteHovered"))
        XCTAssertTrue(historyRowSource.contains("Image(systemName: \"trash\")"))
        XCTAssertTrue(historyRowSource.contains("FloatingBarFaviconContainer"))
    }

    func testFloatingBarSuggestionHeightAdaptsBeforeZenScrollLimit() {
        XCTAssertEqual(FloatingBarLayoutPolicy.suggestionsVisibleRowLimit, 5)
        XCTAssertEqual(FloatingBarLayoutPolicy.suggestionsHeight(for: 0), 0)
        XCTAssertEqual(FloatingBarLayoutPolicy.suggestionsHeight(for: 2), 104)
        XCTAssertEqual(
            FloatingBarLayoutPolicy.suggestionsHeight(for: 6),
            FloatingBarLayoutPolicy.suggestionsMaxHeight
        )
    }

    func testFloatingBarOutsideClickMonitorUsesPassThroughRouting() throws {
        let source = try Self.source(named: "FloatingBar/FloatingBarView.swift")
        let monitorStart = try XCTUnwrap(source.range(of: "private func installOutsideClickMonitorIfNeeded()"))
        let monitorEnd = try XCTUnwrap(source[monitorStart.lowerBound...].range(of: "private func removeOutsideClickMonitor()"))
        let monitorBody = String(source[monitorStart.lowerBound..<monitorEnd.lowerBound])

        XCTAssertTrue(monitorBody.contains("FloatingBarOutsideClickRouting.monitorResult"))
        XCTAssertFalse(monitorBody.contains("return nil"))
        XCTAssertTrue(source.contains("cardView.window === eventWindow"))
    }

    func testFloatingBarOutsideClickRoutingKeepsInsideCardEvent() throws {
        let event = try Self.mouseDownEvent()
        var closeCount = 0

        let result = FloatingBarOutsideClickRouting.monitorResult(
            for: event,
            isFloatingBarVisible: true,
            isEventInsideCard: true
        ) {
            closeCount += 1
        }

        XCTAssertTrue(result === event)
        XCTAssertEqual(closeCount, 0)
    }

    func testFloatingBarOutsideClickRoutingClosesOutsideCardAndPreservesEvent() throws {
        let event = try Self.mouseDownEvent()
        var closeCount = 0

        let result = FloatingBarOutsideClickRouting.monitorResult(
            for: event,
            isFloatingBarVisible: true,
            isEventInsideCard: false
        ) {
            closeCount += 1
        }

        XCTAssertTrue(result === event)
        XCTAssertEqual(closeCount, 1)
    }

    func testFloatingBarCardHitDetectionSeparatesInsideAndOutsideGeometry() {
        let cardView = Self.makeFloatingBarCardView()

        XCTAssertTrue(FloatingBarOutsideClickRouting.isLocationInsideCard(
            NSPoint(x: 32, y: 32),
            cardView: cardView
        ))
        XCTAssertFalse(FloatingBarOutsideClickRouting.isLocationInsideCard(
            NSPoint(x: 180, y: 90),
            cardView: cardView
        ))
    }

    func testTransientChromeStaysInBrowserWindowResponderChain() throws {
        let commandSource = try Self.source(named: "Sumi/Components/Window/FloatingBarChromeHost.swift")
        let findSource = try Self.source(named: "Sumi/Components/FindInPage/FindInPageChromeHost.swift")

        XCTAssertTrue(commandSource.contains("struct FloatingBarChromeHost: View"))
        XCTAssertTrue(findSource.contains("struct FindInPageChromeHost: View"))
        XCTAssertFalse(commandSource.contains("NSPanel"))
        XCTAssertFalse(findSource.contains("NSPanel"))
        XCTAssertFalse(commandSource.contains("makeKey"))
        XCTAssertFalse(findSource.contains("makeKey"))
        XCTAssertFalse(commandSource.contains("NSViewRepresentable"))
        XCTAssertFalse(findSource.contains("NSViewRepresentable"))
    }

    func testTransientChromeZIndexesUseNamedConstants() throws {
        let source = try Self.source(named: "App/Window/WindowView.swift")

        XCTAssertTrue(source.contains("static let findInPage"))
        XCTAssertTrue(source.contains("WindowTransientChromeZIndex.findInPage"))
        XCTAssertFalse(source.contains(".zIndex(3500)"))
    }

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

    func testTrackingViewReconcilesHoverWhenMouseIsAlreadyInsideAfterReenable() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        window.contentView?.addSubview(view)
        view.setHoverTrackingEnabled(false)

        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.setHoverTrackingEnabled(true)
        view.reconcileHoverForLifecycle(mouseLocationInWindow: NSPoint(x: 220, y: 100))
        reported.removeAll()
        view.reconcileHoverForLifecycle(mouseLocationInWindow: NSPoint(x: 24, y: 18))

        XCTAssertEqual(reported, [true])
        XCTAssertTrue(view.currentEffectiveHover)
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
        XCTAssertNil(view.hitTest(NSPoint(x: 12, y: 12)))
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
        XCTAssertNil(view.hitTest(NSPoint(x: 12, y: 12)))
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
        let reservedPadding = SidebarHoverChrome.trailingFadePadding(showsTrailingAction: true)

        XCTAssertEqual(reservedPadding, SidebarRowLayout.trailingActionFadePadding)
        XCTAssertFalse(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: true, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: true))
        XCTAssertEqual(reservedPadding, SidebarHoverChrome.trailingFadePadding(showsTrailingAction: true))
    }

    func testCollapsedSidebarHoverTrackingUsesActiveAppTrackingArea() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SidebarDDGHover.swift")

        XCTAssertTrue(source.contains(".activeInActiveApp"))
        XCTAssertFalse(source.contains("HoverTrackingArea.updateTrackingAreas"))
    }

    func testHoverBridgeSkipsUnchangedTrackingEnabledUpdates() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SidebarDDGHover.swift")

        XCTAssertTrue(source.contains("if view.isHoverTrackingEnabled != isEnabled"))
        XCTAssertTrue(source.contains("view.setHoverTrackingEnabled(isEnabled)"))
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
                return (path, try source(named: path))
            }
        )
    }

    private static func source(named path: String) throws -> String {
        let url = repoRoot.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }

    private static func makeFloatingBarCardView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 140))
        let view = NSView(frame: NSRect(x: 20, y: 20, width: 100, height: 60))
        container.addSubview(view)
        return view
    }

    private static func mouseDownEvent() throws -> NSEvent {
        return try XCTUnwrap(NSEvent.mouseEvent(
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
