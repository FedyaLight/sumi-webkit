import AppKit
@testable import Sumi
import SumiDomain
import SwiftUI
import XCTest


@MainActor
final class SpaceSidebarTransitionStateTests: XCTestCase {
    func testClickTransitionCommitsOnlyOnce() {
        let ids = [UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginClick(
                from: ids[0],
                to: ids[1],
                orderedSpaceIds: ids
            )
        )
        XCTAssertFalse(
            state.beginClick(
                from: ids[0],
                to: ids[1],
                orderedSpaceIds: ids
            )
        )
        XCTAssertEqual(state.finishTransition(commit: true), ids[1])
        XCTAssertNil(state.finishTransition(commit: true))
    }

    func testRenderPolicyKeepsCommittedInteractiveAndTransitionLayersSnapshot() {
        XCTAssertEqual(
            SpaceSidebarRenderPolicy.pageRenderMode(for: .committed),
            .interactive
        )
        XCTAssertEqual(
            SpaceSidebarRenderPolicy.pageRenderMode(for: .transitionLayer),
            .transitionSnapshot
        )
    }

    func testRenderPolicyCompletionDelayMatchesAnimationDuration() {
        XCTAssertEqual(
            SpaceSidebarRenderPolicy.completionDelay,
            SpaceSidebarTransitionConfig.spaceSwitchAnimationDuration,
            accuracy: 0.0001
        )
    }

    func testTransitionLayersPreserveSnapshotContentOpacity() {
        let coordinator = SpaceSidebarTransitionCoordinator()

        for progress in [0.0, 0.5, 1.0] {
            XCTAssertEqual(coordinator.sourceOpacity(for: progress), 1)
            XCTAssertEqual(coordinator.destinationOpacity(for: progress), 1)
        }
    }

    func testRenderPolicyKeepsUnresolvedSwipeOnCommittedInteractivePage() {
        let ids = [UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        XCTAssertFalse(SpaceSidebarRenderPolicy.shouldUseTransitionLayers(for: state))

        state.updateSwipeGesture(
            progress: 0.2,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertTrue(SpaceSidebarRenderPolicy.shouldUseTransitionLayers(for: state))
    }

    func testTransitionSnapshotMatchesOnlyActiveSourceDestination() {
        let sourceId = UUID()
        let destinationId = UUID()
        let unrelatedId = UUID()
        let orderedSpaceIds = [sourceId, destinationId, unrelatedId]
        let snapshot = SpaceSidebarTransitionSnapshot(
            source: makePageSnapshot(
                spaceId: sourceId,
                title: "Source",
                iconValue: SumiPersistentGlyph.spaceDefaultIconValue
            ),
            destination: makePageSnapshot(spaceId: destinationId, title: "Destination", iconValue: "star"),
            stationaryFavorite: nil
        )
        var activeState = SpaceSidebarTransitionState()
        var unresolvedState = SpaceSidebarTransitionState()
        var staleDestinationState = SpaceSidebarTransitionState()

        XCTAssertTrue(
            activeState.beginClick(
                from: sourceId,
                to: destinationId,
                orderedSpaceIds: orderedSpaceIds
            )
        )
        XCTAssertTrue(snapshot.matches(activeState))
        XCTAssertFalse(snapshot.matches(unresolvedState))

        XCTAssertTrue(
            staleDestinationState.beginClick(
                from: sourceId,
                to: unrelatedId,
                orderedSpaceIds: orderedSpaceIds
            )
        )
        XCTAssertFalse(snapshot.matches(staleDestinationState))

        unresolvedState = activeState
        _ = unresolvedState.finishTransition(commit: false)
        XCTAssertFalse(snapshot.matches(unresolvedState))
    }

    func testSwipeTransitionBeginsOnlyAfterHorizontalDirectionLatches() {
        XCTAssertFalse(
            SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(
                for: .init(phase: .began, direction: nil, progress: 0)
            )
        )
        XCTAssertFalse(
            SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(
                for: .init(phase: .changed, direction: nil, progress: 0.02)
            )
        )
        XCTAssertTrue(
            SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(
                for: .init(phase: .changed, direction: 1, progress: 0.02)
            )
        )
    }

    func testChromePreviewPolicyAnimatesFavoriteOnlyForInteractiveCommittedPage() {
        XCTAssertTrue(
            SpaceSidebarChromePreviewPolicy.shouldAnimateFavoriteLayout(
                isActiveWindow: true,
                isTransitioningProfile: false,
                pageRenderMode: .interactive
            )
        )
        XCTAssertFalse(
            SpaceSidebarChromePreviewPolicy.shouldAnimateFavoriteLayout(
                isActiveWindow: true,
                isTransitioningProfile: false,
                pageRenderMode: .transitionSnapshot
            )
        )
        XCTAssertFalse(
            SpaceSidebarChromePreviewPolicy.shouldAnimateFavoriteLayout(
                isActiveWindow: true,
                isTransitioningProfile: true,
                pageRenderMode: .interactive
            )
        )
    }

    func testFavoritePlacementUsesSharedPinnedGridForSameProfileTransition() {
        let profileId = UUID()

        XCTAssertTrue(
            SpaceSidebarFavoritePlacementPolicy.usesSharedPinnedGrid(
                sourceProfileId: profileId,
                destinationProfileId: profileId
            )
        )
    }

    func testFavoritePlacementKeepsEmbeddedPinnedGridForCrossProfileTransition() {
        XCTAssertFalse(
            SpaceSidebarFavoritePlacementPolicy.usesSharedPinnedGrid(
                sourceProfileId: UUID(),
                destinationProfileId: UUID()
            )
        )
    }

    func testPinnedGridContextPrefersExplicitSpaceOverWindowSpace() {
        let explicitSpaceId = UUID()
        let windowSpaceId = UUID()

        XCTAssertEqual(
            PinnedGridContextResolver.contextMenuSpaceId(
                explicitSpaceId: explicitSpaceId,
                windowSpaceId: windowSpaceId
            ),
            explicitSpaceId
        )
        XCTAssertEqual(
            PinnedGridContextResolver.geometrySpaceId(
                explicitSpaceId: explicitSpaceId,
                windowSpaceId: windowSpaceId
            ),
            explicitSpaceId
        )
    }

    func testPinnedGridContextUsesWindowSpaceWithoutGlobalFallback() {
        let windowSpaceId = UUID()

        XCTAssertEqual(
            PinnedGridContextResolver.contextMenuSpaceId(
                explicitSpaceId: nil,
                windowSpaceId: windowSpaceId
            ),
            windowSpaceId
        )
        XCTAssertEqual(
            PinnedGridContextResolver.geometrySpaceId(
                explicitSpaceId: nil,
                windowSpaceId: windowSpaceId
            ),
            windowSpaceId
        )
    }

    func testPinnedGridContextWithoutSpaceKeepsStableGeometryAndNoMenuTarget() {
        XCTAssertNil(
            PinnedGridContextResolver.contextMenuSpaceId(
                explicitSpaceId: nil,
                windowSpaceId: nil
            )
        )
        XCTAssertEqual(
            PinnedGridContextResolver.geometrySpaceId(
                explicitSpaceId: nil,
                windowSpaceId: nil
            ),
            PinnedGridContextResolver.unresolvedGeometrySpaceId
        )
    }

    func testSnapshotBuilderKeepsSingleStationaryFavoriteForSameProfileTransition() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let favorite = makeFavoritePin(profileId: profileId, title: "Pinned")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setPinnedTabs([favorite], for: profileId)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertNotNil(snapshot.stationaryFavorite)
        XCTAssertEqual(snapshot.stationaryFavorite?.items.map(\.id), [favorite.id])
    }

    func testSnapshotBuilderPreservesActiveStationaryFavoriteAccentSource() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let favorite = makeFavoritePin(profileId: profileId, title: "Pinned")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setPinnedTabs([favorite], for: profileId)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id
        _ = browserManager.shortcutTabMaterializer.materialize(
            favorite,
            in: windowState.id,
            currentSpaceId: source.id
        )!
        windowState.currentShortcutPinId = favorite.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )
        let expectedPartition = browserManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(
            for: favorite,
            currentSpaceId: windowState.currentSpaceId
        )

        guard let item = snapshot.stationaryFavorite?.items.first else {
            return XCTFail("Expected stationary favorite snapshot item")
        }
        guard case .shortcut(let shortcut) = item else {
            return XCTFail("Expected stationary favorite shortcut")
        }
        XCTAssertEqual(shortcut.presentationState, .visuallySelected)
        XCTAssertEqual(shortcut.accentSource.launchURL, favorite.launchURL)
        XCTAssertEqual(shortcut.accentSource.partition, expectedPartition)
    }

    func testSnapshotBuilderIncludesFavoriteSplitTileMembers() throws {
        let browser = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileID = UUID()
        let source = Space(name: "Source", profileId: profileID)
        let destination = Space(name: "Destination", profileId: profileID)
        let pins = [
            ShortcutPin(
                id: UUID(),
                role: .favorite,
                profileId: profileID,
                index: 0,
                launchURL: URL(string: "https://first-favorite-split.example")!,
                title: "First",
                iconAsset: "star.fill"
            ),
            ShortcutPin(
                id: UUID(),
                role: .favorite,
                profileId: profileID,
                index: 1,
                launchURL: URL(string: "https://second-favorite-split.example")!,
                title: "Second",
                iconAsset: "bolt.fill"
            ),
        ]
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: pins.map { .shortcutPin($0.id) },
                layoutKind: .horizontal,
                container: .favoriteSidebar(
                    profileId: profileID,
                    index: 0
                )
            )
        )

        browser.spaceStateOwner.replaceSpaces([source, destination])
        browser.structuralCollectionMutationOwner.setPinnedTabs(
            pins,
            for: profileID
        )
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browser,
            windowState: windowState,
            settings: settings
        )

        let item = try XCTUnwrap(snapshot.stationaryFavorite?.items.first)
        guard case .splitGroup(let split) = item else {
            return XCTFail("Expected one Favorite Split Tile")
        }
        XCTAssertEqual(snapshot.stationaryFavorite?.items.count, 1)
        XCTAssertEqual(split.members.map(\.id), group.memberIDs)
        XCTAssertEqual(
            split.members.compactMap { member -> String? in
                guard case .system(let name) = member.icon else { return nil }
                return name
            },
            ["star.fill", "bolt.fill"]
        )
    }

    func testSnapshotBuilderCapturesSpaceTitleNameIconAndCornerRadius() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source Space", icon: "sparkles", profileId: profileId)
        let destination = Space(name: "Destination Space", icon: "star.fill", profileId: profileId)

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertEqual(snapshot.source.title, "Source Space")
        XCTAssertEqual(snapshot.source.iconValue, "sparkles")
        XCTAssertEqual(snapshot.destination.title, "Destination Space")
        XCTAssertEqual(snapshot.destination.iconValue, "star.fill")
        XCTAssertEqual(
            snapshot.source.rowCornerRadius,
            settings.resolvedCornerRadius(SpaceTitleRowLayout.defaultCornerRadius),
            accuracy: 0.0001
        )
    }

    func testSnapshotBuilderStoresSourceAndDestinationViewportOffsets() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let sourceViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 44,
            contentHeight: 480,
            viewportHeight: 160
        )
        let destinationViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 88,
            contentHeight: 520,
            viewportHeight: 180
        )

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings,
            scrollViewportForSpace: { spaceId in
                switch spaceId {
                case source.id:
                    sourceViewport
                case destination.id:
                    destinationViewport
                default:
                    nil
                }
            }
        )

        XCTAssertEqual(snapshot.source.scrollViewport, sourceViewport)
        XCTAssertEqual(snapshot.destination.scrollViewport, destinationViewport)
    }

    func testSnapshotBuilderDefaultsMissingDestinationViewportToTop() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let sourceViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 72,
            contentHeight: 420,
            viewportHeight: 140
        )

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings,
            scrollViewportForSpace: { spaceId in
                spaceId == source.id ? sourceViewport : nil
            }
        )

        XCTAssertEqual(snapshot.source.scrollViewport, sourceViewport)
        XCTAssertEqual(snapshot.destination.scrollViewport, .zero)
        XCTAssertEqual(snapshot.destination.scrollViewport.clampedOffset(), 0, accuracy: 0.001)
    }

    func testSnapshotBuilderEmbedsFavoriteForCrossProfileTransition() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let destination = Space(name: "Destination", profileId: destinationProfileId)
        let sourceFavorite = makeFavoritePin(profileId: sourceProfileId, title: "Source Pin")
        let destinationFavorite = makeFavoritePin(profileId: destinationProfileId, title: "Destination Pin")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setPinnedTabs([sourceFavorite], for: sourceProfileId)
        browserManager.structuralCollectionMutationOwner.setPinnedTabs([destinationFavorite], for: destinationProfileId)
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertNil(snapshot.stationaryFavorite)
        XCTAssertEqual(snapshot.source.favorite?.items.map(\.id), [sourceFavorite.id])
        XCTAssertEqual(snapshot.destination.favorite?.items.map(\.id), [destinationFavorite.id])
    }

    func testSnapshotBuilderMarksSelectedRegularTabWithoutObservedTabRows() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let first = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/first")!,
            name: "First",
            spaceId: source.id,
            index: 0
        )
        let second = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/second")!,
            name: "Second",
            spaceId: source.id,
            index: 1
        )
        first.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        second.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.regularTabLifecycleOwner.addTab(first)
        browserManager.regularTabLifecycleOwner.addTab(second)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id
        windowState.currentTabId = second.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        let regularTabs = regularTabRows(in: snapshot.source)
        XCTAssertEqual(regularTabs.map(\.id), [first.id, second.id])
        XCTAssertEqual(regularTabs.map(\.isSelected), [false, true])
    }

    func testSnapshotBuilderCarriesChangedURLSlashForDriftedShortcut() throws {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: source.id,
            index: 0,
            launchURL: URL(string: "https://example.com/pinned")!,
            title: "Pinned"
        )

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: source.id)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let liveTab = try XCTUnwrap(
            browserManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: source.id
            )
        )
        liveTab.url = URL(string: "https://example.com/live")!

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        guard case .shortcut(let shortcut) = snapshot.source.pinnedItems.first
        else {
            return XCTFail("Expected one pinned shortcut snapshot")
        }

        XCTAssertTrue(shortcut.showsChangedURLSlash)
    }

    func testSnapshotShortcutRowRendersChangedURLSlash() throws {
        let normal = try renderedSnapshotShortcutRow(
            showsChangedURLSlash: false
        )
        let changed = try renderedSnapshotShortcutRow(
            showsChangedURLSlash: true
        )
        let backingScale = CGFloat(changed.pixelsWide) / changed.size.width
        let slashRegion = Int(34 * backingScale)..<Int(46 * backingScale)

        func inkCount(in image: NSBitmapImageRep) -> Int {
            slashRegion.reduce(into: 0) { count, x in
                for y in 0..<image.pixelsHigh {
                    guard let color = image.colorAt(x: x, y: y) else {
                        continue
                    }
                    if color.alphaComponent > 0.02 {
                        count += 1
                    }
                }
            }
        }

        XCTAssertGreaterThan(
            inkCount(in: changed),
            inkCount(in: normal),
            "A drifted shortcut snapshot must retain the live row's reset slash"
        )
    }

    func testSnapshotShortcutUnloadedAppearanceMatchesLiveOpacityAndSetting() throws {
        let enabled = try renderedSnapshotShortcutRow(
            showsChangedURLSlash: false,
            showUnloadedAppearance: true
        )
        let disabled = try renderedSnapshotShortcutRow(
            showsChangedURLSlash: false,
            showUnloadedAppearance: false
        )
        let iconCenter = CGPoint(
            x: SidebarRowLayout.leadingInset + SidebarRowLayout.faviconSize / 2,
            y: SidebarRowLayout.rowHeight / 2
        )
        let enabledColor = try XCTUnwrap(color(in: enabled, at: iconCenter))
        let disabledColor = try XCTUnwrap(color(in: disabled, at: iconCenter))

        XCTAssertEqual(enabledColor.alphaComponent, 0.5, accuracy: 0.05)
        XCTAssertGreaterThan(disabledColor.redComponent, 0.9)
        XCTAssertEqual(disabledColor.alphaComponent, 1, accuracy: 0.05)
    }

    func testChangedURLSnapshotKeepsLiveTitleLeadingInset() throws {
        let image = try renderedSnapshotShortcutRow(
            showsChangedURLSlash: true,
            title: "Pinned"
        )
        let backingScale = CGFloat(image.pixelsWide) / image.size.width
        let titleStartX = Int(
            (SidebarRowLayout.changedLauncherResetWidth
                + SidebarRowLayout.changedLauncherResetTrailingGap)
                * backingScale
        )

        let firstTitleInkX = (titleStartX..<image.pixelsWide).first { x in
            (0..<image.pixelsHigh).contains { y in
                guard let color = image.colorAt(x: x, y: y) else {
                    return false
                }
                return color.alphaComponent > 0.05
            }
        }

        let expectedTitleLeadingX = Int(
            ceil(
                (SidebarRowLayout.changedLauncherResetWidth
                    + SidebarRowLayout.changedLauncherResetTrailingGap
                    + SidebarRowLayout.changedLauncherTitleLeading)
                    * backingScale
            )
        )

        XCTAssertNotNil(firstTitleInkX)
        XCTAssertGreaterThanOrEqual(
            firstTitleInkX ?? 0,
            expectedTitleLeadingX,
            "Changed-URL snapshot title must keep the live row's leading inset"
        )
    }

    func testSelectedSnapshotRowSurfaceKeepsFixedHeightInsideViewportProposal() throws {
        let viewportSize = CGSize(width: 213, height: 240)
        let settings = makeIsolatedSettings()
        let tokens = ResolvedThemeContext.default.tokens(settings: settings)
        let measurement = expectation(description: "Measure selected row surface")
        var measuredHeight: CGFloat?
        let root = VStack(spacing: 0) {
            Color.clear
                .frame(height: SidebarRowLayout.rowHeight)
                .frame(maxWidth: .infinity)
                .sidebarRowSurface(
                    background: .red,
                    cornerRadius: 0,
                    tokens: tokens,
                    isVisible: true,
                    drawsSelectionShadow: true
                )
                .overlay {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                measuredHeight = geometry.size.height
                                measurement.fulfill()
                            }
                    }
                }
        }
        .frame(
            width: viewportSize.width,
            height: viewportSize.height,
            alignment: .top
        )
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(origin: .zero, size: viewportSize)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        wait(for: [measurement], timeout: 1)

        XCTAssertEqual(
            try XCTUnwrap(measuredHeight),
            SidebarRowLayout.rowHeight,
            accuracy: 0.001,
            "The selected surface must not consume the snapshot viewport's spare height"
        )
    }

    func testSnapshotBuilderPreservesRegularTabUnloadedIndicator() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let unloadedTab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/unloaded")!,
            name: "Unloaded",
            spaceId: source.id,
            index: 0
        )
        unloadedTab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.regularTabLifecycleOwner.addTab(unloadedTab)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id
        windowState.currentTabId = unloadedTab.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertTrue(unloadedTab.showsWebViewUnloadedIndicator)
        XCTAssertEqual(
            regularTabRows(in: snapshot.source).map(\.showsUnloadedIndicator),
            [true]
        )
    }

    func testSnapshotBuilderHidesRegularTabUnloadedAppearanceWhenDisabled() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        settings.showUnloadedTabAppearance = false
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let unloadedTab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/unloaded")!,
            name: "Unloaded",
            spaceId: source.id,
            index: 0
        )
        unloadedTab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.regularTabLifecycleOwner.addTab(unloadedTab)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id
        windowState.currentTabId = unloadedTab.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertTrue(unloadedTab.showsWebViewUnloadedIndicator)
        XCTAssertEqual(
            regularTabRows(in: snapshot.source).map(\.showsUnloadedIndicator),
            [false]
        )
    }

    func testSnapshotBuilderProjectsRegularSplitAsOneRowWithResolvedFavicons() throws {
        let browser = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileID = UUID()
        let source = Space(name: "Source", profileId: profileID)
        let destination = Space(name: "Destination", profileId: profileID)
        let tabs = (0..<3).map { index in
            browser.tabFactory.makeTab(
                url: URL(string: "https://split-\(index).example")!,
                name: "Split \(index)",
                favicon: index == 0 ? "star.fill" : "bolt.fill",
                spaceId: source.id,
                index: index,
                loadsCachedFaviconOnInit: false
            )
        }
        tabs.forEach {
            $0.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browser))
        }

        browser.spaceStateOwner.replaceSpaces([source, destination])
        tabs.forEach { browser.regularTabLifecycleOwner.addTab($0) }
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(tabs[0].id),
                    .regularTab(tabs[1].id),
                ],
                layoutKind: .horizontal,
                container: .regularTabs(spaceId: source.id)
            )
        )
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = source.id
        windowState.currentTabId = tabs[0].id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browser,
            windowState: windowState,
            settings: settings
        )

        XCTAssertEqual(snapshot.source.regularRows.count, 2)
        guard case .splitGroup(let split) = snapshot.source.regularRows[0] else {
            return XCTFail("Expected one split-group row before the trailing tab")
        }
        XCTAssertEqual(split.id, group.id)
        XCTAssertEqual(split.members.map(\.id), group.memberIDs)
        XCTAssertTrue(split.members.allSatisfy { member in
            if case .system("globe") = member.icon {
                return false
            }
            return true
        })
        guard case .tab(let trailing) = snapshot.source.regularRows[1] else {
            return XCTFail("Expected the remaining regular tab")
        }
        XCTAssertEqual(trailing.id, tabs[2].id)
    }

    func testSnapshotSplitMemberContentMatchesLiveVerticalCenter() throws {
        let image = try renderedSnapshotSplitRow()
        var redPixelRows: [Int] = []

        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent > 0.8,
                   color.greenComponent < 0.4,
                   color.blueComponent < 0.4,
                   color.alphaComponent > 0.8 {
                    redPixelRows.append(y)
                }
            }
        }

        let minY = try XCTUnwrap(redPixelRows.min())
        let maxY = try XCTUnwrap(redPixelRows.max())
        let backingScale = CGFloat(image.pixelsHigh) / image.size.height
        XCTAssertEqual(
            CGFloat(minY + maxY) / 2,
            SidebarRowLayout.rowHeight * backingScale / 2,
            accuracy: backingScale / 2,
            "Snapshot split favicons and titles must not jump above live rows"
        )
    }

    func testSnapshotSplitFaviconMatchesLiveSize() throws {
        let image = try renderedSnapshotSplitRow(
            sourceIconSize: 32,
            memberCount: 1
        )
        var redPixelColumns: [Int] = []
        var redPixelRows: [Int] = []

        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent > 0.8,
                   color.greenComponent < 0.4,
                   color.blueComponent < 0.4,
                   color.alphaComponent > 0.8 {
                    redPixelColumns.append(x)
                    redPixelRows.append(y)
                }
            }
        }

        let minX = try XCTUnwrap(redPixelColumns.min())
        let maxX = try XCTUnwrap(redPixelColumns.max())
        let minY = try XCTUnwrap(redPixelRows.min())
        let maxY = try XCTUnwrap(redPixelRows.max())
        let backingScale = CGFloat(image.pixelsWide) / image.size.width
        XCTAssertEqual(
            maxX - minX + 1,
            Int(SplitGroupSidebarVisualLayout.iconWidth * backingScale),
            accuracy: Int(backingScale),
            "Snapshot bitmaps must scale down to the live split favicon width"
        )
        XCTAssertEqual(
            maxY - minY + 1,
            Int(SplitGroupSidebarVisualLayout.iconWidth * backingScale),
            accuracy: Int(backingScale),
            "Snapshot bitmaps must scale down to the live split favicon height"
        )
    }

    func testSnapshotLauncherFaviconKeepsLiveIntrinsicSize() throws {
        let sourceIconSize: CGFloat = 32
        let image = try renderedSnapshotLauncherIcon(
            sourceIconSize: sourceIconSize
        )
        var redPixelColumns: [Int] = []
        var redPixelRows: [Int] = []

        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent > 0.8,
                   color.greenComponent < 0.4,
                   color.blueComponent < 0.4,
                   color.alphaComponent > 0.8 {
                    redPixelColumns.append(x)
                    redPixelRows.append(y)
                }
            }
        }

        let minX = try XCTUnwrap(redPixelColumns.min())
        let maxX = try XCTUnwrap(redPixelColumns.max())
        let minY = try XCTUnwrap(redPixelRows.min())
        let maxY = try XCTUnwrap(redPixelRows.max())
        let backingScale = CGFloat(image.pixelsWide) / image.size.width
        XCTAssertEqual(
            maxX - minX + 1,
            Int(sourceIconSize * backingScale),
            accuracy: Int(backingScale),
            "Snapshot launchers must preserve the same intrinsic bitmap presentation as live rows"
        )
        XCTAssertEqual(
            maxY - minY + 1,
            Int(sourceIconSize * backingScale),
            accuracy: Int(backingScale),
            "Snapshot launchers must preserve the same intrinsic bitmap presentation as live rows"
        )
    }

    func testSelectedFavoriteSplitSnapshotDoesNotDrawOutsideTileBounds() throws {
        let rendered = try renderedSelectedFavoriteSplitSnapshot()
        let image = rendered.image
        let tileFrame = rendered.tileFrame
        let scaleX = CGFloat(image.pixelsWide) / image.size.width
        let scaleY = CGFloat(image.pixelsHigh) / image.size.height
        var exteriorPixelCount = 0

        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                let point = CGPoint(
                    x: (CGFloat(x) + 0.5) / scaleX,
                    y: (CGFloat(y) + 0.5) / scaleY
                )
                guard !tileFrame.contains(point),
                      let color = image.colorAt(x: x, y: y)?
                        .usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.001 else {
                    continue
                }
                exteriorPixelCount += 1
            }
        }

        XCTAssertEqual(
            exteriorPixelCount,
            0,
            "The transition snapshot must not add a shadow around a Favorite split tile"
        )
    }

    func testSnapshotBuilderKeepsPinnedSplitIconsDuringTransition() throws {
        let browser = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileID = UUID()
        let source = Space(name: "Source", profileId: profileID)
        let destination = Space(name: "Destination", profileId: profileID)
        let pins = [
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: source.id,
                index: 0,
                launchURL: URL(string: "https://first-split.example")!,
                title: "First",
                iconAsset: "star.fill"
            ),
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: source.id,
                index: 1,
                launchURL: URL(string: "https://second-split.example")!,
                title: "Second",
                iconAsset: "bolt.fill"
            ),
        ]
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: pins.map { .shortcutPin($0.id) },
                layoutKind: .horizontal,
                container: .shortcutSidebar(
                    spaceId: source.id,
                    profileId: profileID,
                    folderId: nil,
                    index: 0
                ),
                title: "Research",
                iconAsset: "rectangle.split.2x1"
            )
        )

        browser.spaceStateOwner.replaceSpaces([source, destination])
        browser.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts(pins, for: source.id)
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browser,
            windowState: windowState,
            settings: settings
        )

        XCTAssertEqual(snapshot.source.pinnedItems.count, 1)
        guard case .splitGroup(let split) = snapshot.source.pinnedItems[0] else {
            return XCTFail("Expected one pinned split-group row")
        }
        XCTAssertEqual(split.members.map(\.id), group.memberIDs)
        XCTAssertEqual(split.displayTitle, "Research")
        guard case .system("rectangle.split.2x1") = split.customIcon else {
            return XCTFail("Expected the custom group icon in the snapshot")
        }
        XCTAssertTrue(split.members.allSatisfy(\.desaturatesIcon))
        XCTAssertEqual(
            split.members.compactMap { member -> String? in
                guard case .system(let name) = member.icon else { return nil }
                return name
            },
            ["star.fill", "bolt.fill"]
        )
    }

    func testSnapshotBuilderKeepsOnlyStickyPinnedRowsWhenSpaceIsCollapsed() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileID = UUID()
        let source = Space(name: "Source", profileId: profileID)
        let destination = Space(name: "Destination", profileId: profileID)
        let hiddenPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: source.id,
            index: 0,
            launchURL: URL(string: "https://example.com/hidden")!,
            title: "Hidden"
        )
        let stickyPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: source.id,
            index: 1,
            launchURL: URL(string: "https://example.com/sticky")!,
            title: "Sticky"
        )

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([hiddenPin, stickyPin], for: source.id)
        let regularTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/regular",
            in: source,
            activate: false
        )
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = source.id
        _ = TransitionStateSidebarFixture(
            browser: browserManager,
            windowState: windowState
        )
        _ = browserManager.shortcutTabMaterializer.materialize(
            stickyPin,
            in: windowState.id,
            currentSpaceId: source.id
        )
        windowState.sidebarSpacePinnedCollapse.setCollapsed(true, for: source.id)
        windowState.sidebarSpacePinnedCollapse.scheduleMutation(
            for: source.id
        ) { _ in
            SidebarFolderProjectionState(
                stickyItemIDs: [stickyPin.id],
                hasActiveProjection: true
            )
        }

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertTrue(snapshot.source.hasPinnedContent)
        XCTAssertTrue(snapshot.source.isPinnedContentCollapsed)
        XCTAssertEqual(snapshot.source.pinnedItems.map(\.id), [stickyPin.id])
        XCTAssertEqual(
            regularTabRows(in: snapshot.source).map(\.id),
            [regularTab.id]
        )
    }

    func testSnapshotFolderBodyKeepsLiveFolderLayoutMetrics() {
        XCTAssertEqual(SpaceSidebarSnapshotFolderLayout.contentLeadingPadding, 14)
        XCTAssertEqual(SpaceSidebarSnapshotFolderLayout.contentVerticalPadding, 4)
    }

    func testSnapshotPageThemeContextUsesPageWorkspaceThemeWithoutInteractiveProgress() {
        let settings = makeIsolatedSettings()
        let sourceTheme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#0A84FF",
                        isPrimary: true,
                        position: .monochrome
                    ),
                ],
                opacity: 1,
                texture: 0
            )
        )
        let destinationTheme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#FF3B30",
                        isPrimary: true,
                        position: .monochrome
                    ),
                ],
                opacity: 1,
                texture: 0
            )
        )
        let destination = Space(name: "Destination", workspaceTheme: destinationTheme)
        var baseContext = ResolvedThemeContext.default
        baseContext.workspaceTheme = sourceTheme
        baseContext.sourceWorkspaceTheme = sourceTheme
        baseContext.targetWorkspaceTheme = destinationTheme
        baseContext.isInteractiveTransition = true
        baseContext.transitionProgress = 0.42

        let pageContext = SpaceSidebarSnapshotThemeResolver.pageThemeContext(
            for: destination,
            baseContext: baseContext,
            settings: settings,
            isIncognito: false
        )

        XCTAssertEqual(pageContext.workspaceTheme.gradient.primaryColorHex, "#FF3B30")
        XCTAssertEqual(pageContext.sourceWorkspaceTheme.gradient.primaryColorHex, "#FF3B30")
        XCTAssertEqual(pageContext.targetWorkspaceTheme.gradient.primaryColorHex, "#FF3B30")
        XCTAssertFalse(pageContext.isInteractiveTransition)
        XCTAssertEqual(pageContext.transitionProgress, 1.0, accuracy: 0.0001)
    }

    func testSnapshotBuilderKeepsClosedFolderProjectionRowsForLiveLaunchers() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let folder = TabFolder(name: "Folder", spaceId: source.id)
        let firstPin = makeSpacePinnedPin(spaceId: source.id, folderId: folder.id, index: 0, title: "First")
        let secondPin = makeSpacePinnedPin(spaceId: source.id, folderId: folder.id, index: 1, title: "Second")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setFolders([folder], for: source.id)
        browserManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([firstPin, secondPin], for: source.id)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        _ = browserManager.shortcutTabMaterializer.materialize(
            secondPin,
            in: windowState.id,
            currentSpaceId: source.id
        )!
        windowState.sidebarFolderProjections.scheduleUpdate(
            for: folder.id,
            stickyItemIDs: [secondPin.id],
            hasActiveProjection: true
        )

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        guard case .folder(let folderSnapshot) = snapshot.source.pinnedItems.first else {
            return XCTFail("Expected first pinned item to be a folder snapshot")
        }

        XCTAssertFalse(folderSnapshot.isOpen)
        XCTAssertEqual(folderSnapshot.bodyChildren.map(\.id), [secondPin.id])
        XCTAssertTrue(folderSnapshot.hasActiveSelection)
    }

    func testSnapshotBuilderPreservesOpenNestedFolderTreeForSpaceTransition() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let parent = TabFolder(name: "Parent", spaceId: source.id, index: 0)
        let child = TabFolder(name: "Child", spaceId: source.id, parentFolderId: parent.id, index: 0)
        parent.isOpen = true
        child.isOpen = true
        let nestedPin = makeSpacePinnedPin(spaceId: source.id, folderId: child.id, index: 0, title: "Nested")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setFolders([parent, child], for: source.id)
        browserManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([nestedPin], for: source.id)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        guard case .folder(let parentSnapshot) = snapshot.source.pinnedItems.first else {
            return XCTFail("Expected parent folder snapshot")
        }
        guard case .folder(let childSnapshot) = parentSnapshot.bodyChildren.first else {
            return XCTFail("Expected child folder snapshot")
        }

        XCTAssertTrue(parentSnapshot.isOpen)
        XCTAssertEqual(parentSnapshot.bodyChildren.map(\.id), [child.id])
        XCTAssertTrue(childSnapshot.isOpen)
        XCTAssertEqual(childSnapshot.bodyChildren.map(\.id), [nestedPin.id])
    }

    private func renderedSnapshotSplitRow(
        sourceIconSize: CGFloat = SidebarRowLayout.faviconSize,
        memberCount: Int = 2
    ) throws -> NSBitmapImageRep {
        let rowWidth: CGFloat = 213
        let redIcon = NSImage(
            size: CGSize(width: sourceIconSize, height: sourceIconSize)
        )
        redIcon.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(
            rect: CGRect(
                x: 0,
                y: 0,
                width: sourceIconSize,
                height: sourceIconSize
            )
        ).fill()
        redIcon.unlockFocus()

        let members = (0..<memberCount).map { _ in
            SpaceSplitGroupMemberSnapshot(
                id: .regularTab(UUID()),
                title: "",
                icon: .image(Image(nsImage: redIcon)),
                desaturatesIcon: false,
                accentSource: nil,
                favoriteBackdrop: nil,
                isSelected: false
            )
        }
        let snapshot = SpaceSplitGroupSnapshot(
            id: UUID(),
            displayTitle: "",
            customIcon: nil,
            members: members,
            isSelected: false,
            isLoaded: true
        )
        let settings = makeIsolatedSettings()
        let tokens = ResolvedThemeContext.default.tokens(settings: settings)
        let root = SpaceSnapshotSplitGroupView(
            splitGroup: snapshot,
            rowCornerRadius: SidebarRowLayout.defaultCornerRadius,
            tokens: tokens
        )
        .frame(width: rowWidth, height: SidebarRowLayout.rowHeight)
        .environment(SidebarFaviconImageStore())
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(
            x: 0,
            y: 0,
            width: rowWidth,
            height: SidebarRowLayout.rowHeight
        )
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let image = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: image)
        return image
    }

    private func renderedSnapshotShortcutRow(
        showsChangedURLSlash: Bool,
        title: String = "",
        showUnloadedAppearance: Bool = true
    ) throws -> NSBitmapImageRep {
        let rowWidth: CGFloat = 213
        let rowHeight = SidebarRowLayout.rowHeight
        let redIcon = NSImage(
            size: CGSize(
                width: SidebarRowLayout.faviconSize,
                height: SidebarRowLayout.faviconSize
            )
        )
        redIcon.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(
            rect: CGRect(
                x: 0,
                y: 0,
                width: SidebarRowLayout.faviconSize,
                height: SidebarRowLayout.faviconSize
            )
        ).fill()
        redIcon.unlockFocus()

        let shortcut = SpaceShortcutSnapshot(
            id: UUID(),
            title: title,
            icon: .image(Image(nsImage: redIcon)),
            accentSource: SpaceShortcutSnapshotAccentSource(
                launchURL: URL(string: "https://example.com/pinned")!,
                partition: .regular(nil)
            ),
            favoriteBackdrop: nil,
            presentationState: .launcherOnly,
            showsAudioButton: false,
            isMuted: false,
            showsSplitOutline: false,
            showsChangedURLSlash: showsChangedURLSlash
        )
        let settings = makeIsolatedSettings()
        settings.showUnloadedTabAppearance = showUnloadedAppearance
        let tokens = ResolvedThemeContext.default.tokens(settings: settings)
        let root = SpaceSnapshotShortcutRowView(
            shortcut: shortcut,
            rowCornerRadius: 0,
            tokens: tokens
        )
        .frame(width: rowWidth, height: rowHeight)
        .environment(\.sumiSettings, settings)
        .environment(SidebarFaviconImageStore())
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(
            origin: .zero,
            size: CGSize(width: rowWidth, height: rowHeight)
        )
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let image = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: image)
        return image
    }

    private func color(
        in image: NSBitmapImageRep,
        at point: CGPoint
    ) -> NSColor? {
        let scaleX = CGFloat(image.pixelsWide) / image.size.width
        let scaleY = CGFloat(image.pixelsHigh) / image.size.height
        return image.colorAt(
            x: Int(point.x * scaleX),
            y: Int(point.y * scaleY)
        )?.usingColorSpace(.deviceRGB)
    }

    private func renderedSelectedFavoriteSplitSnapshot() throws -> (
        image: NSBitmapImageRep,
        tileFrame: CGRect
    ) {
        let padding: CGFloat = 8
        let tileWidth: CGFloat = 101
        let tileSize = CGSize(
            width: tileWidth,
            height: PinnedTileMetrics.height
        )
        let members = ["star.fill", "bolt.fill"].enumerated().map {
            index, systemImageName in
            SpaceSplitGroupMemberSnapshot(
                id: .shortcutPin(UUID()),
                title: "",
                icon: .system(systemImageName),
                desaturatesIcon: false,
                accentSource: nil,
                favoriteBackdrop: nil,
                isSelected: index == 0
            )
        }
        let splitGroup = SpaceSplitGroupSnapshot(
            id: UUID(),
            displayTitle: "",
            customIcon: nil,
            members: members,
            isSelected: true,
            isLoaded: true
        )
        let settings = makeIsolatedSettings()
        let tokens = ResolvedThemeContext.default.tokens(settings: settings)
        let root = FavoriteSnapshotGrid(
            snapshot: FavoriteSnapshot(items: [.splitGroup(splitGroup)], showsPlaceholder: false),
            width: tileWidth,
            tokens: tokens
        )
        .environment(\.sumiSettings, settings)
        .environment(SidebarFaviconImageStore())
        .padding(padding)
        let canvasSize = CGSize(
            width: tileSize.width + padding * 2,
            height: tileSize.height + padding * 2
        )
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(origin: .zero, size: canvasSize)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let image = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: image)
        return (
            image: image,
            tileFrame: CGRect(
                origin: CGPoint(x: padding, y: padding),
                size: tileSize
            )
        )
    }

    private func renderedSnapshotLauncherIcon(
        sourceIconSize: CGFloat
    ) throws -> NSBitmapImageRep {
        let canvasSize: CGFloat = 64
        let redIcon = NSImage(
            size: CGSize(width: sourceIconSize, height: sourceIconSize)
        )
        redIcon.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(
            rect: CGRect(
                x: 0,
                y: 0,
                width: sourceIconSize,
                height: sourceIconSize
            )
        ).fill()
        redIcon.unlockFocus()

        let root = SpaceSnapshotIconView(
            icon: .image(Image(nsImage: redIcon)),
            size: SidebarRowLayout.faviconSize,
            foregroundColor: .black
        )
        .frame(width: canvasSize, height: canvasSize)
        .environment(SidebarFaviconImageStore())
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(
            x: 0,
            y: 0,
            width: canvasSize,
            height: canvasSize
        )
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let image = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: image)
        return image
    }

    private func makeIsolatedSettings() -> SumiSettingsService {
        let suiteName = "SpaceSidebarTransitionStateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SumiSettingsService(userDefaults: defaults)
    }

    private func makeTransitionSnapshot(
        sourceSpace: Space,
        destinationSpace: Space,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        settings: SumiSettingsService,
        scrollViewportForSpace: (UUID) -> SpaceSidebarSnapshotViewport? = { _ in nil }
    ) -> SpaceSidebarTransitionSnapshot {
        let sidebar = TransitionStateSidebarFixture(
            browser: browserManager,
            windowState: windowState
        )
        return SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: sourceSpace,
            destinationSpace: destinationSpace,
            browserContext: browserManager.composeSidebarBrowserContext(
                spaceLifecycle: sidebar.lifecycle
            ),
            spaceCatalog: sidebar.spaceCatalog,
            inventory: sidebar.inventory,
            selection: sidebar.selection,
            pinProjection: sidebar.pinProjection,
            windowState: windowState,
            settings: settings,
            scrollViewportForSpace: scrollViewportForSpace
        )
    }

    private func makePageSnapshot(
        spaceId: UUID,
        title: String,
        iconValue: String
    ) -> SpaceSidebarPageSnapshot {
        SpaceSidebarPageSnapshot(
            spaceId: spaceId,
            title: title,
            iconValue: iconValue,
            extensionActions: nil,
            favorite: nil,
            hasPinnedContent: false,
            isPinnedContentCollapsed: false,
            pinnedItems: [],
            regularRows: [],
            showsNewTabButtonInList: true,
            showsTopNewTabButton: false,
            rowCornerRadius: SpaceTitleRowLayout.defaultCornerRadius,
            scrollViewport: .zero
        )
    }

    private func regularTabRows(
        in snapshot: SpaceSidebarPageSnapshot
    ) -> [SpaceTabRowSnapshot] {
        snapshot.regularRows.compactMap { row in
            guard case .tab(let tab) = row else { return nil }
            return tab
        }
    }

    private func makeFavoritePin(profileId: UUID, title: String) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://example.com/\(UUID().uuidString)")!,
            title: title
        )
    }

    private func makeSpacePinnedPin(
        spaceId: UUID,
        folderId: UUID,
        index: Int,
        title: String
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: URL(string: "https://example.com/\(UUID().uuidString)")!,
            title: title
        )
    }
}

@MainActor
private struct TransitionStateSidebarFixture {
    let spaceCatalog: SidebarSpaceCatalogProjection
    let inventory: SidebarSpaceInventoryProjection
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let lifecycle: SidebarSpaceLifecycle

    init(browser: BrowserManager, windowState: BrowserWindowState) {
        let registry = browser.windowRegistry
        registry.register(windowState)
        let windows = SidebarWindowIdentityQuery(registry: registry)
        spaceCatalog = SidebarSpaceCatalogProjection(
            runtime: browser.runtimePortConnection,
            spaces: browser.spaceStateOwner,
            pins: browser.shortcutPinCollectionStateOwner
        )
        inventory = SidebarSpaceInventoryProjection(
            runtime: browser.runtimePortConnection,
            spaces: browser.spaceStateOwner,
            regularTabs: browser.regularTabCollectionOwner,
            pinned: SidebarPinnedInventoryProjection(
                folders: browser.folderCollectionStateOwner,
                pins: browser.shortcutPinCollectionStateOwner,
                splitGroups: browser.splitGroupStore,
                splitOrdering: browser.splitGroupSidebarOrdering
            )
        )
        let splitQuery = browser.splitQuery
        selection = SidebarWindowSelectionQuery(
            runtimeIsAlive: { true },
            windows: windows,
            windowTabs: browser.windowTabContext,
            shortcutPresentation: browser.shortcutPresentationOwner,
            splitQuery: splitQuery
        )
        pinProjection = SidebarPinFolderProjection(
            runtimeIsAlive: { true },
            windows: windows,
            favorite: browser.favoriteShortcutPlacementOwner,
            resolution: browser.shortcutPinRuntimeResolutionOwner
        )
        lifecycle = browser.sidebarSpaceLifecycle
    }
}
