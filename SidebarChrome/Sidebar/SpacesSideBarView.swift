//
//  SpacesSideBarView.swift
//  Sumi
//
//

import Combine
import SwiftUI

struct SidebarPageInputGraphIdentity: Hashable {
    let spaceId: UUID
    let profileId: UUID?
    let recoveryGeneration: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.spaceId == rhs.spaceId
            && lhs.profileId == rhs.profileId
            && lhs.recoveryGeneration == rhs.recoveryGeneration
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spaceId)
        hasher.combine(profileId)
        hasher.combine(recoveryGeneration)
    }
}

struct SpacesSideBarView: View {
    @Environment(BrowserWindowState.self) var windowState
    @Environment(WindowRegistry.self) var windowRegistry
    @Environment(\.sidebarPresentationContext) var sidebarPresentationContext
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @EnvironmentObject var dragState: SidebarDragState

    @State var isSidebarHovered: Bool = false
    @State var transitionCoordinator = SpaceSidebarTransitionCoordinator()
    @StateObject var scrollHoverCoordinator = NativeSurfaceScrollHoverCoordinator()
    let browserContext: SidebarBrowserContext
    let inventory: SidebarInventoryProjection
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabs: any SidebarRegularTabsControlling
    let dragTransactions: SidebarDragTransactionPort
    let inventoryUpdates: SidebarInventoryUpdates
    let profileUpdates: SidebarProfileUpdates
    let nowPlayingController: SumiNativeNowPlayingController
    let updaterService: SumiUpdaterService

    init(
        browserContext: SidebarBrowserContext,
        inventory: SidebarInventoryProjection,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        pinCommands: SidebarPinFolderCommands,
        spaceLifecycle: SidebarSpaceLifecycle,
        regularTabs: any SidebarRegularTabsControlling,
        dragTransactions: SidebarDragTransactionPort,
        inventoryUpdates: SidebarInventoryUpdates,
        profileUpdates: SidebarProfileUpdates,
        nowPlayingController: SumiNativeNowPlayingController,
        updaterService: SumiUpdaterService
    ) {
        self.browserContext = browserContext
        self.inventory = inventory
        self.selection = selection
        self.pinProjection = pinProjection
        self.pinCommands = pinCommands
        self.spaceLifecycle = spaceLifecycle
        self.regularTabs = regularTabs
        self.dragTransactions = dragTransactions
        self.inventoryUpdates = inventoryUpdates
        self.profileUpdates = profileUpdates
        self.nowPlayingController = nowPlayingController
        self.updaterService = updaterService
    }

    var sidebarBrowserContext: SidebarBrowserContext {
        browserContext
    }

    var transitionState: SpaceSidebarTransitionState {
        transitionCoordinator.transitionState
    }

    var transitionSnapshot: SpaceSidebarTransitionSnapshot? {
        transitionCoordinator.transitionSnapshot
    }

    var body: some View {
        sidebarContent
            .contentShape(Rectangle())
            .overlay {
                SidebarMouseButtonCaptureSurface(
                    isEnabled: allowsSidebarInteractiveWork,
                    onNavigate: switchRelativeSpace
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onDisappear {
                transitionCoordinator.cancelLocalSpaceTransitionIfNeeded(
                    context: makeTransitionContext(spaces: availableSpaces),
                    cancelTheme: true
                )
                scrollHoverCoordinator.reset()
            }
            .onHover { state in
                isSidebarHovered = allowsSidebarInteractiveWork ? state : false
            }
            .onChange(of: allowsSidebarInteractiveWork) { _, allowsInteractiveWork in
                if !allowsInteractiveWork {
                    isSidebarHovered = false
                }
            }
    }

    // MARK: - Main Content

    var sidebarContent: some View {
        mainSidebarContent
            .overlay {
                ZStack {
                    SidebarGlobalDragOverlay(
                        transactionPort: dragTransactions,
                        dragAutoscrollRegistry: dragState.dragAutoscrollRegistry
                    )
                        .allowsHitTesting(allowsSidebarInteractiveWork)
                }
            }
    }

    var mainSidebarContent: some View {
        VStack(spacing: 8) {
            SidebarHeader(browserContext: browserContext.headerContext(windowState))
                .environment(windowState)

            if let creationSession = windowState.spaceCreationSession.activeSession {
                SidebarSpaceCreationProfilesView(
                    session: creationSession,
                    currentProfiles: { browserContext.profileManager.profiles },
                    profileUpdates: profileUpdates,
                    isActive: allowsSidebarInteractiveWork,
                    currentProfileID: { browserContext.currentProfile()?.id },
                    onCreate: { commitSpaceCreationSession(creationSession) },
                    onCancel: { cancelSpaceCreationSession(creationSession) }
                )
                .environment(windowState)
                .transition(spaceCreationTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SidebarScopedSnapshotReader(
                    current: { [spaceLifecycle, windowState] in
                        spaceLifecycle.availableSpaces(
                            isIncognito: windowState.isIncognito,
                            ephemeralSpaces: windowState.ephemeralSpaces
                        )
                    },
                    changes: sidebarSpaceCatalogChanges.map { [spaceLifecycle, windowState] _ in
                        spaceLifecycle.availableSpaces(
                            isIncognito: windowState.isIncognito,
                            ephemeralSpaces: windowState.ephemeralSpaces
                        )
                    }
                    .eraseToAnyPublisher(),
                    isActive: allowsSidebarInteractiveWork
                ) { spaces in
                    sidebarInventoryContent(spaces: spaces)
                }
            }
        }
        .padding(.top, SidebarChromeMetrics.topControlInset)
        .environment(sidebarInteractionState)
        .sidebarAppKitBackgroundContextMenu(
            controller: windowState.sidebarContextMenuController,
            entries: { sidebarContextMenuEntries() },
            onMenuVisibilityChanged: handleSidebarContextMenuVisibility
        )
        .onChange(of: dragState.isDragging) { _, isDragging in
            Task { @MainActor in
                sidebarInteractionState.syncSidebarItemDrag(isDragging)
            }
        }
    }

    @ViewBuilder
    private func sidebarInventoryContent(spaces: [Space]) -> some View {
        let visualSpaceId = transitionCoordinator.visualSelectedSpaceId(
            in: makeTransitionContext(spaces: spaces)
        )

        Group {
            spacesPageView(spaces: spaces)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                if allowsSidebarInteractiveWork {
                    SpaceSidebarUpdateNoticeReader(updaterService: updaterService)

                    SpaceSidebarMiniPlayer(
                        nowPlayingController: nowPlayingController,
                        faviconImageReader: browserContext.faviconImageReader,
                        configureMediaStore: browserContext.configureMediaStore
                    )
                }

                SidebarBottomBar(
                    browserContext: sidebarBrowserContext,
                    spaceLifecycle: spaceLifecycle,
                    visualSelectedSpaceId: visualSpaceId,
                    onNewSpaceTap: beginSpaceCreationMode,
                    onSelectSpace: { switchSpace(to: $0, spaces: spaces) }
                )
                .environment(windowState)
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            handlePendingSplitGroupFocusRequest(
                windowState.presentationState.pendingSplitGroupFocusRequest,
                spaces: spaces
            )
        }
        .onChange(of: windowState.presentationState.pendingSplitGroupFocusRequest) { _, request in
            handlePendingSplitGroupFocusRequest(request, spaces: spaces)
        }
    }

    var availableSpaces: [Space] {
        spaceLifecycle.availableSpaces(
            isIncognito: windowState.isIncognito,
            ephemeralSpaces: windowState.ephemeralSpaces
        )
    }

    var sidebarInteractionState: SidebarInteractionState {
        windowState.sidebarInteractionState
    }

    var allowsSidebarInteractiveWork: Bool {
        sidebarPresentationContext.allowsInteractiveWork
    }

    var sidebarSpaceCatalogChanges: AnyPublisher<Void, Never> {
        if windowState.isIncognito {
            return windowState.ephemeralInventoryAuthority.spaceCatalogChanges
        }
        return inventoryUpdates.catalogChanges
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func sidebarPageInventoryChanges(
        spaceID: UUID,
        profileID: UUID?
    ) -> AnyPublisher<Void, Never> {
        if windowState.isIncognito {
            return windowState.ephemeralInventoryAuthority.tabInventoryChanges
        }
        return inventoryUpdates.pageChanges(
            windowID: windowState.id,
            spaceID: spaceID,
            profileID: profileID
        )
        .map { _ in () }
        .eraseToAnyPublisher()
    }

    func makeTransitionContext(spaces: [Space]) -> SpaceSidebarTransitionCoordinator.Context {
        SpaceSidebarTransitionCoordinator.Context(
            spaces: spaces,
            currentSpaces: { [windowState, spaceLifecycle] in
                spaceLifecycle.availableSpaces(
                    isIncognito: windowState.isIncognito,
                    ephemeralSpaces: windowState.ephemeralSpaces
                )
            },
            windowState: windowState,
            browserContext: browserContext,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            dragState: dragState,
            settings: sumiSettings,
            allowsInteractiveWork: allowsSidebarInteractiveWork,
            reduceMotion: reduceMotion
        )
    }

    func handlePendingSplitGroupFocusRequest(
        _ request: SplitGroupFocusRequest?,
        spaces: [Space]
    ) {
        guard let request else { return }

        if windowState.currentSpaceId == request.targetSpaceID {
            browserContext.spaceTransitions.completePendingSplitGroupFocusIfReady(
                windowState,
                request.targetSpaceID
            )
            return
        }

        guard let targetSpace = space(for: request.targetSpaceID, in: spaces) else {
            windowState.presentationState.pendingSplitGroupFocusRequest = nil
            return
        }

        switchSpace(to: targetSpace, spaces: spaces)
    }

    func switchSpace(
        to targetSpace: Space,
        spaces: [Space]
    ) {
        transitionCoordinator.switchSpace(
            to: targetSpace,
            context: makeTransitionContext(spaces: spaces)
        )
    }

    func switchRelativeSpace(offset: Int) {
        transitionCoordinator.switchRelativeSpace(
            offset: offset,
            context: makeTransitionContext(spaces: availableSpaces)
        )
    }

    func handleSidebarContextMenuVisibility(_ presented: Bool) {
        if presented {
            browserContext.commands.closeDownloadsPopover(windowState)
        }
    }

    func resolvedPageProfileId(for space: Space?) -> UUID? {
        transitionCoordinator.resolvedPageProfileId(
            for: space,
            context: makeTransitionContext(spaces: availableSpaces)
        )
    }
}
