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
        let viewSource = try Self.source(named: "FloatingBar/FloatingBarView.swift")
        let layoutSource = try Self.source(named: "FloatingBar/FloatingBarLayoutPolicy.swift")
        let motionSource = try Self.source(named: "FloatingBar/FloatingBarMotionPolicy.swift")
        let resultsSource = try Self.source(named: "FloatingBar/FloatingBarResultsPanelView.swift")
        let floatingBarSource = [
            viewSource,
            layoutSource,
            motionSource,
            resultsSource
        ].joined(separator: "\n")

        XCTAssertTrue(viewSource.contains(".tint(tokens.primaryText)"))
        XCTAssertTrue(viewSource.contains(".lineLimit(1)"))
        XCTAssertTrue(viewSource.contains("focusSearchField(selectAll: false)"))
        XCTAssertTrue(viewSource.contains("FloatingBarResultsPanelView"))
        XCTAssertTrue(viewSource.contains("chromeContentAnimation"))
        XCTAssertTrue(viewSource.contains("microAffordanceAnimation"))
        XCTAssertTrue(viewSource.contains("setWaitingForSearchDebounce"))
        XCTAssertTrue(viewSource.contains("visibleSuggestionLayoutCount"))
        XCTAssertTrue(viewSource.contains("triggerSearchModeConfirmation"))
        XCTAssertTrue(viewSource.contains("updateWithoutMotion"))
        XCTAssertTrue(layoutSource.contains("suggestionsVisibleRowLimit = 5"))
        XCTAssertTrue(layoutSource.contains("shouldWaitForSuggestionLayout"))
        XCTAssertTrue(motionSource.contains("FloatingBarMotionPolicy"))
        XCTAssertTrue(motionSource.contains("FloatingBarSearchModeConfirmationView"))
        XCTAssertTrue(resultsSource.contains("resultsPanelHeight"))
        XCTAssertTrue(resultsSource.contains("ScrollView(.vertical)"))
        XCTAssertTrue(resultsSource.contains(".scrollIndicators(shouldScroll ? .visible : .hidden)"))
        XCTAssertTrue(resultsSource.contains("selectedBackground = tokens.accent.opacity"))
        XCTAssertTrue(floatingBarSource.contains("deleteHistoryEntry"))
        XCTAssertFalse(floatingBarSource.contains("pendingSuggestionLayoutCount"))
        XCTAssertFalse(floatingBarSource.contains(".transition(.blur"))
        XCTAssertFalse(floatingBarSource.contains("FloatingBarSearchModeGlowView"))
        XCTAssertFalse(floatingBarSource.contains("NSAlert"))

        let searchManagerSource = try Self.source(named: "Sumi/Managers/SearchManager/SearchManager.swift")
        XCTAssertTrue(searchManagerSource.contains("maxVisibleSuggestions = 10"))
        XCTAssertFalse(searchManagerSource.contains("withAnimation"))
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

    func testFloatingBarSuggestionHeightAdaptsBeforeZenScrollLimit() throws {
        let viewSource = try Self.source(named: "FloatingBar/FloatingBarView.swift")
        let layoutSource = try Self.source(named: "FloatingBar/FloatingBarLayoutPolicy.swift")

        XCTAssertEqual(FloatingBarLayoutPolicy.suggestionsVisibleRowLimit, 5)
        XCTAssertEqual(FloatingBarLayoutPolicy.suggestionsHeight(for: 0), 0)
        XCTAssertEqual(FloatingBarLayoutPolicy.suggestionsHeight(for: 2), 104)
        XCTAssertEqual(FloatingBarLayoutPolicy.resultsPanelHeight(for: 0), 0)
        XCTAssertEqual(FloatingBarLayoutPolicy.resultsPanelHeight(for: 2), 116.5)
        XCTAssertEqual(FloatingBarLayoutPolicy.layoutCount(forVisibleCount: 0), 0)
        XCTAssertEqual(FloatingBarLayoutPolicy.layoutCount(forVisibleCount: 2), 2)
        XCTAssertEqual(FloatingBarLayoutPolicy.layoutCount(forVisibleCount: 6), 5)
        XCTAssertFalse(layoutSource.contains("suggestionLayoutCount("))
        let layoutCountStart = try XCTUnwrap(viewSource.range(of: "private var suggestionLayoutCount: Int"))
        let layoutCountEnd = try XCTUnwrap(viewSource[layoutCountStart.lowerBound...].range(of: "private var shouldShowEmptyStateSuggestions"))
        let layoutCountBody = String(viewSource[layoutCountStart.lowerBound..<layoutCountEnd.lowerBound])
        XCTAssertTrue(layoutCountBody.contains("committedSuggestionLayoutCount"))
        XCTAssertFalse(layoutCountBody.contains("visibleSuggestions.count"))
        XCTAssertTrue(
            FloatingBarLayoutPolicy.shouldWaitForSuggestionLayout(
                isDebouncing: false,
                isLoading: true,
                visibleLayoutCount: 4
            )
        )
        XCTAssertFalse(
            FloatingBarLayoutPolicy.shouldWaitForSuggestionLayout(
                isDebouncing: false,
                isLoading: true,
                visibleLayoutCount: 5
            )
        )
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

    func testSelectedRowShadowBleedIsAppliedToOuterRowWrapper() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SidebarRowLayout.swift")
        let bleedBranchStart = try XCTUnwrap(source.range(of: "if drawsShadow"))
        let surfaceBody = String(source[bleedBranchStart.lowerBound...])

        XCTAssertTrue(source.contains("static let selectionShadowBleed"))
        XCTAssertTrue(surfaceBody.contains(".padding(SidebarRowLayout.selectionShadowBleed)"))
        XCTAssertTrue(surfaceBody.contains(".padding(-SidebarRowLayout.selectionShadowBleed)"))
        XCTAssertTrue(surfaceBody.contains(".zIndex(SidebarRowLayout.selectionZIndex)"))
        XCTAssertFalse(source.contains("reservesShadowBleed"))
        XCTAssertFalse(surfaceBody.contains(".zIndex(0)"))
        XCTAssertLessThan(
            try XCTUnwrap(surfaceBody.range(of: ".padding(-SidebarRowLayout.selectionShadowBleed)")).lowerBound,
            try XCTUnwrap(surfaceBody.range(of: ".zIndex(SidebarRowLayout.selectionZIndex)")).lowerBound
        )
    }

    func testExpandedSidebarRowsDoNotClipSelectionShadowBleed() throws {
        let motionSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarZenMotion.swift")
        let lifecycleStart = try XCTUnwrap(motionSource.range(of: "struct SidebarRowLifecycleModifier"))
        let transitionStart = try XCTUnwrap(
            motionSource.range(
                of: "private struct SidebarRowListItemTransitionModifier",
                range: lifecycleStart.lowerBound..<motionSource.endIndex
            )
        )
        let lifecycleSource = String(motionSource[lifecycleStart.lowerBound..<transitionStart.lowerBound])

        XCTAssertTrue(lifecycleSource.contains("if isCollapsed"))
        XCTAssertTrue(lifecycleSource.contains("row.clipped()"))
        XCTAssertTrue(lifecycleSource.contains("} else {"))

        let splitSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SplitGroupSidebarRow.swift")

        XCTAssertTrue(splitSource.contains(".sidebarRowLifecycle(isCollapsed: isCollapsingRow)"))
        XCTAssertFalse(splitSource.contains("SplitGroupRowLifecycleModifier"))
    }

    func testRegularTabsUseLazyStackForRowVirtualization() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpaceRegularTabsSection.swift")
        let viewStart = try XCTUnwrap(source.range(of: "private func regularTabsView(currentTabs: [Tab]) -> some View"))
        let nextFunctionStart = try XCTUnwrap(
            source.range(
                of: "private func visibleSplitGroups(currentTabs: [Tab]) -> [SplitGroup]",
                range: viewStart.lowerBound..<source.endIndex
            )
        )
        let regularTabsViewSource = String(source[viewStart.lowerBound..<nextFunctionStart.lowerBound])

        XCTAssertFalse(source.contains("regularTabsUsesLazyRowStack"))
        XCTAssertFalse(source.contains("regularTabsRowStack"))
        XCTAssertTrue(regularTabsViewSource.contains("LazyVStack(alignment: .leading, spacing: 2)"))
        XCTAssertFalse(regularTabsViewSource.contains("\n        VStack(alignment: .leading, spacing: 2)"))
        XCTAssertTrue(source.contains(".zIndex(regularTabRowZIndex(tab))"))
        XCTAssertTrue(source.contains(".zIndex(regularSplitGroupRowZIndex(group))"))
    }

    func testSidebarRowInsertionUsesUnifiedFullHeightAppearance() throws {
        let spaceViewSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpaceView.swift")
        let regularTabsSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpaceRegularTabsSection.swift")
        let animationSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/RegularTabsListAnimation.swift")
        let pinnedSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpacePinnedSection.swift")
        let folderSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift")
        let motionSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarZenMotion.swift")

        XCTAssertTrue(spaceViewSource.contains("regularTabsListAnimation"))
        XCTAssertTrue(spaceViewSource.contains("shortcutRestoreAppearingGapIds"))
        XCTAssertTrue(animationSource.contains("struct RegularTabsListAnimationState"))
        XCTAssertTrue(animationSource.contains("enum RegularTabRemovalMode"))
        XCTAssertTrue(animationSource.contains("prepareRemoval(tabId: UUID, tab: Tab)"))
        XCTAssertTrue(animationSource.contains("commitRemovalAppearance(tabId: UUID, mode: RegularTabRemovalMode)"))
        XCTAssertTrue(animationSource.contains("fadeOnly"))
        XCTAssertTrue(animationSource.contains("heightCollapse"))
        XCTAssertTrue(regularTabsSource.contains("regularTabsListAnimation"))
        XCTAssertTrue(regularTabsSource.contains("sidebarRowAnimatedListSlot"))
        XCTAssertTrue(regularTabsSource.contains("regularAnimatedTabRow("))
        XCTAssertTrue(regularTabsSource.contains("regularTabsUsesExpandedDragSpacer"))
        XCTAssertTrue(regularTabsSource.contains("hasRemovalInFlight"))
        XCTAssertFalse(regularTabsSource.contains(".animation(sidebarContentMutationAnimation, value: tabs.map"))
        XCTAssertFalse(regularTabsSource.contains("sidebarRowStagedInsertion"))
        XCTAssertFalse(regularTabsSource.contains("animateRegularLastRowFadeRemoval"))
        XCTAssertFalse(regularTabsSource.contains("regularRemovalGapTabs"))
        XCTAssertTrue(motionSource.contains("enum SidebarMotionTransaction"))
        XCTAssertTrue(motionSource.contains("sidebarRowAnimatedListSlot"))
        XCTAssertTrue(motionSource.contains("struct SidebarRowStagedInsertionModifier"))
        XCTAssertTrue(motionSource.contains("static var sidebarRowListItem: AnyTransition"))
        XCTAssertTrue(motionSource.contains(".identity"))
        XCTAssertFalse(regularTabsSource.contains("guard !regularRenderedTabItems.isEmpty"))
        XCTAssertFalse(regularTabsSource.contains("if !tabs.isEmpty || regularTabsUsesProjectedDropLayout"))
        XCTAssertFalse(regularTabsSource.contains("sidebarRowListItemTransition"))
        XCTAssertTrue(pinnedSource.contains(".sidebarRowStagedInsertion(isRevealing: isAppearing)"))
        XCTAssertTrue(folderSource.contains(".sidebarRowStagedInsertion(isRevealing: isAppearing)"))
        XCTAssertFalse(regularTabsSource.contains("animateRegularDeferredRemoval"))
        XCTAssertFalse(pinnedSource.contains("shortcutRestoreGapHeights"))
        XCTAssertFalse(folderSource.contains("shortcutRestoreGapHeights"))
    }

    func testPinnedAndEssentialsUseLazyStacksForScrollableRows() throws {
        let pinnedGridSource = try Self.source(named: "Sumi/Components/Sidebar/PinnedButtons/PinnedGrid.swift")
        let gridRowsStart = try XCTUnwrap(
            pinnedGridSource.range(of: "LazyVStack(spacing: pinnedTabsConfiguration.gridSpacing)")
        )
        let gridRowsSource = String(pinnedGridSource[gridRowsStart.lowerBound...])

        XCTAssertTrue(gridRowsSource.contains("ForEach(displayRows, id: \\.stableID)"))
        XCTAssertFalse(pinnedGridSource.contains("\n                VStack(spacing: pinnedTabsConfiguration.gridSpacing)"))

        let pinnedSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpacePinnedSection.swift")
        let pinnedListStart = try XCTUnwrap(Self.sourceRangeStart(
            in: pinnedSource,
            marker: "private var pinnedTabsList: some View"
        ))
        let pinnedZIndexStart = try XCTUnwrap(
            pinnedSource.range(
                of: "private func spacePinnedDisplayEntryZIndex",
                range: pinnedListStart..<pinnedSource.endIndex
            )
        )
        let pinnedListSource = String(pinnedSource[pinnedListStart..<pinnedZIndexStart.lowerBound])

        XCTAssertTrue(pinnedListSource.contains("return LazyVStack(spacing: 0)"))
        XCTAssertFalse(pinnedListSource.contains("return VStack(spacing: 0)"))

        let folderSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift")
        let folderBodyStart = try XCTUnwrap(Self.sourceRangeStart(
            in: folderSource,
            marker: "private func folderBodyContent("
        ))
        let nestedFolderStart = try XCTUnwrap(
            folderSource.range(
                of: "private func nestedFolderView",
                range: folderBodyStart..<folderSource.endIndex
            )
        )
        let folderBodySource = String(folderSource[folderBodyStart..<nestedFolderStart.lowerBound])

        XCTAssertTrue(folderBodySource.contains("return LazyVStack(spacing: 0)"))
        XCTAssertFalse(folderBodySource.contains("return VStack(spacing: 0)"))
    }

    func testSelectionShadowIsOwnedByRowSurfaceOnly() throws {
        let rowSurfaceSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SidebarRowLayout.swift")
        let regularTabSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpaceTab.swift")
        let shortcutRowSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/ShortcutSidebarRow.swift")
        let snapshotRowsSource = try Self.source(named: "Navigation/Sidebar/SpacesSideBarView.swift")
        let splitGroupSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SplitGroupSidebarRow.swift")

        XCTAssertTrue(rowSurfaceSource.contains("tokens.sidebarSelectionShadow"))
        XCTAssertFalse(regularTabSource.contains(".shadow("))
        XCTAssertFalse(shortcutRowSource.contains(".shadow("))
        XCTAssertFalse(snapshotRowsSource.contains(".shadow("))
        XCTAssertFalse(splitGroupSource.contains(".shadow("))
    }

    func testUnloadedRegularTabIndicatorDoesNotReserveFaviconLayoutWidth() throws {
        let faviconSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SidebarTabFaviconView.swift")
        let indicatorStart = try XCTUnwrap(faviconSource.range(of: "struct SidebarUnloadedRegularTabFaviconIndicator"))
        let indicatorSource = String(faviconSource[indicatorStart.lowerBound...])
        let snapshotRowsSource = try Self.source(named: "Navigation/Sidebar/SpacesSideBarView.swift")

        XCTAssertFalse(indicatorSource.contains("HStack("))
        XCTAssertFalse(indicatorSource.contains(".fixedSize()"))
        XCTAssertTrue(indicatorSource.contains(".overlay(alignment: .leading)"))
        XCTAssertTrue(indicatorSource.contains(".frame(width: size, height: size)"))
        XCTAssertTrue(indicatorSource.contains("indicatorLeadingOffset"))
        XCTAssertTrue(snapshotRowsSource.contains("SidebarUnloadedRegularTabFaviconIndicator("))
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

    func testSplitGroupHoverBackgroundIsRowScoped() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SplitGroupSidebarRow.swift")
        let segmentStart = try XCTUnwrap(source.range(of: "private struct SplitGroupSegment"))
        let actionButtonStart = try XCTUnwrap(
            source.range(
                of: "private func segmentActionButton",
                range: segmentStart.lowerBound..<source.endIndex
            )
        )
        let rowSource = String(source[..<segmentStart.lowerBound])
        let segmentContentSource = String(source[segmentStart.lowerBound..<actionButtonStart.lowerBound])

        XCTAssertTrue(rowSource.contains(".sidebarRowSurface("))
        XCTAssertTrue(rowSource.contains("background: rowBackground"))
        XCTAssertTrue(rowSource.contains(".sidebarDDGHover($isRowHovered, isEnabled: isRowHoverTrackingEnabled)"))
        XCTAssertTrue(rowSource.contains("private var rowBackground: Color"))
        XCTAssertTrue(rowSource.contains("private var drawsRowSurface: Bool"))
        XCTAssertTrue(rowSource.contains("private var showsRowHoverBackground: Bool"))
        XCTAssertTrue(rowSource.contains("private var isRowHoverTrackingEnabled: Bool"))
        XCTAssertTrue(rowSource.contains("private var isFocusedGroup: Bool"))
        XCTAssertTrue(rowSource.contains("return Color.clear"))
        XCTAssertFalse(rowSource.contains("fieldBackground"))

        XCTAssertFalse(segmentContentSource.contains(".background("))
        XCTAssertFalse(segmentContentSource.contains(".fill("))
        XCTAssertFalse(segmentContentSource.contains("sidebarRowHover"))
        XCTAssertFalse(segmentContentSource.contains("sidebarRowActive"))
        XCTAssertFalse(segmentContentSource.contains("displayIsHovering"))
        XCTAssertTrue(segmentContentSource.contains("showsActionControls"))
    }

    func testEssentialSplitProxyUsesDashedOutlineInsteadOfCornerBadge() throws {
        let pinnedGridSource = try Self.source(named: "Sumi/Components/Sidebar/PinnedButtons/PinnedGrid.swift")
        let pinnedTileSource = try Self.source(named: "Sumi/Components/Sidebar/PinnedButtons/PinnedTabView.swift")
        let shortcutPinSource = try Self.source(named: "Sumi/Models/Tab/ShortcutPin.swift")
        let shortcutRowSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/ShortcutSidebarRow.swift")
        let transitionSnapshotSource = try Self.source(named: "Navigation/Sidebar/SpacesSideBarView.swift")
        let transitionPinnedTileSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSnapshotPinnedTileView.swift")

        XCTAssertFalse(pinnedGridSource.contains("EssentialSplitBadge"))
        XCTAssertFalse(pinnedGridSource.contains("showsSplitProxyBadge"))
        XCTAssertFalse(pinnedGridSource.contains("rectangle.split.2x1"))
        XCTAssertTrue(pinnedGridSource.contains("showsSplitGroupOutline: true"))
        XCTAssertTrue(pinnedGridSource.contains("showsSplitGroupOutline: essentialRuntimeState?.showsSplitProxyOutline == true"))

        XCTAssertTrue(shortcutPinSource.contains("showsSplitProxyOutline"))
        XCTAssertFalse(shortcutPinSource.contains("showsSplitProxyBadge"))

        XCTAssertFalse(shortcutRowSource.contains("showsSplitBadge"))
        XCTAssertFalse(shortcutRowSource.contains("splitBadge"))
        XCTAssertFalse(shortcutRowSource.contains("rectangle.split.2x1"))

        XCTAssertFalse(transitionSnapshotSource.contains("showsSplitProxyBadge"))
        XCTAssertFalse(transitionSnapshotSource.contains("showsSplitBadge"))
        XCTAssertFalse(transitionSnapshotSource.contains("splitBadge"))
        XCTAssertFalse(transitionSnapshotSource.contains("rectangle.split.2x1"))
        XCTAssertTrue(transitionSnapshotSource.contains("showsSplitOutline"))

        XCTAssertFalse(transitionPinnedTileSource.contains("showsSplitProxyBadge"))
        XCTAssertFalse(transitionPinnedTileSource.contains("showsSplitBadge"))
        XCTAssertFalse(transitionPinnedTileSource.contains("splitBadge"))
        XCTAssertTrue(transitionPinnedTileSource.contains("showsSplitOutline"))
        XCTAssertTrue(transitionPinnedTileSource.contains("PinnedTileSplitGroupOutlineMask"))

        XCTAssertTrue(pinnedTileSource.contains("PinnedTileSplitGroupOutlineMask"))
        XCTAssertTrue(pinnedTileSource.contains("dash: [dash, gap]"))
        XCTAssertTrue(pinnedTileSource.contains("x: size.width * 0.3"))
        XCTAssertTrue(pinnedTileSource.contains("x: size.width * 0.7"))
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
            "Sumi/Components/Sidebar/SpaceSection/SplitGroupSidebarRow.swift",
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

    private static func sourceRangeStart(in source: String, marker: String) -> String.Index? {
        source.range(of: marker)?.lowerBound
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
