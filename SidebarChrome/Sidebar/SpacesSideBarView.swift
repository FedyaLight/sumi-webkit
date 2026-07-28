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

    @State var isSidebarHovered: Bool = false
    @State var transitionCoordinator = SpaceSidebarTransitionCoordinator()
    @State private var spaceSwitchConsumerID = UUID()
    @StateObject var scrollHoverCoordinator = NativeSurfaceScrollHoverCoordinator()
    let browserContext: SidebarBrowserContext
    let spaceCatalog: SidebarSpaceCatalogProjection
    let inventory: SidebarSpaceInventoryProjection
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let dragTransactions: SidebarDragTransactionPort
    let dragState: SidebarDragState
    let dragGeometry: SidebarDragGeometryModule
    let inventoryUpdates: SidebarInventoryUpdates
    let profileUpdates: SidebarProfileUpdates
    let nowPlayingController: SumiNativeNowPlayingController
    let updaterService: SumiUpdaterService
    let persistWindowSession: (BrowserWindowState) -> Void

    init(
        browserContext: SidebarBrowserContext,
        spaceCatalog: SidebarSpaceCatalogProjection,
        inventory: SidebarSpaceInventoryProjection,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        pinCommands: SidebarPinCommands,
        pinExecution: SidebarPinExecutionCommands,
        folderCommands: SidebarFolderCommands,
        spaceLifecycle: SidebarSpaceLifecycle,
        regularTabCatalog: SidebarRegularTabCatalog,
        regularTabTargets: SidebarRegularTabTargetQuery,
        regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands,
        regularTabShortcutCommands: SidebarRegularTabShortcutCommands,
        regularTabPlacementCommands: SidebarRegularTabPlacementCommands,
        dragTransactions: SidebarDragTransactionPort,
        dragState: SidebarDragState,
        dragGeometry: SidebarDragGeometryModule,
        inventoryUpdates: SidebarInventoryUpdates,
        profileUpdates: SidebarProfileUpdates,
        nowPlayingController: SumiNativeNowPlayingController,
        updaterService: SumiUpdaterService,
        persistWindowSession: @escaping (BrowserWindowState) -> Void
    ) {
        self.browserContext = browserContext
        self.spaceCatalog = spaceCatalog
        self.inventory = inventory
        self.selection = selection
        self.pinProjection = pinProjection
        self.pinCommands = pinCommands
        self.pinExecution = pinExecution
        self.folderCommands = folderCommands
        self.spaceLifecycle = spaceLifecycle
        self.regularTabCatalog = regularTabCatalog
        self.regularTabTargets = regularTabTargets
        self.regularTabLifecycleCommands = regularTabLifecycleCommands
        self.regularTabShortcutCommands = regularTabShortcutCommands
        self.regularTabPlacementCommands = regularTabPlacementCommands
        self.dragTransactions = dragTransactions
        self.dragState = dragState
        self.dragGeometry = dragGeometry
        self.inventoryUpdates = inventoryUpdates
        self.profileUpdates = profileUpdates
        self.nowPlayingController = nowPlayingController
        self.updaterService = updaterService
        self.persistWindowSession = persistWindowSession
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
                windowState.presentationState.spaceSwitch.unregisterConsumer(
                    spaceSwitchConsumerID
                )
                transitionCoordinator.cancelLocalSpaceTransitionIfNeeded(
                    context: makeTransitionContext(spaces: availableSpaces),
                    cancelTheme: true
                )
                scrollHoverCoordinator.reset()
            }
            .onAppear {
                syncSpaceSwitchConsumer(isEnabled: allowsSidebarInteractiveWork)
            }
            .sidebarHover { state in
                isSidebarHovered = allowsSidebarInteractiveWork ? state : false
            }
            .onChange(of: allowsSidebarInteractiveWork) { _, allowsInteractiveWork in
                syncSpaceSwitchConsumer(isEnabled: allowsInteractiveWork)
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
            SidebarHeader(
                browserContext: browserContext.headerContextOwner
                    .sidebarHeaderContext(for: windowState)
            )
                .environment(windowState)

            if let creationSession = windowState.spaceCreationSession.activeSession {
                SidebarSpaceCreationProfilesView(
                    session: creationSession,
                    currentProfiles: { browserContext.profileManager.profiles },
                    profileUpdates: profileUpdates,
                    isActive: allowsSidebarInteractiveWork,
                    currentProfileID: {
                        browserContext.profileAuthority.currentProfile?.id
                    },
                    onThemePreview: { [browserContext, windowState] theme in
                        browserContext.spaceTransitions.previewWorkspaceTheme(
                            theme,
                            in: windowState
                        )
                    },
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
                    areEquivalent: ==,
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
    }

    @ViewBuilder
    private func sidebarInventoryContent(spaces: [Space]) -> some View {
        let visualSpaceId = transitionCoordinator.visualSelectedSpaceId(
            in: makeTransitionContext(spaces: spaces)
        )

        VStack(spacing: 8) {
            spacesPageView(spaces: spaces)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            VStack(spacing: 8) {
                if allowsSidebarInteractiveWork {
                    SpaceSidebarUpdateNoticeReader(updaterService: updaterService)

                    SpaceSidebarMiniPlayer(
                        nowPlayingController: nowPlayingController,
                        faviconImageReader: browserContext.faviconImageReader,
                        mediaStoreConfiguration: browserContext.mediaStoreConfiguration
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
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            handlePendingSplitGroupFocusRequest(
                windowState.presentationState.pendingSplitGroupFocusRequest,
                spaces: spaces
            )
        }
        .onChange(of: windowState.presentationState.pendingSplitGroupFocusRequest) { _, request in
            handlePendingSplitGroupFocusRequest(request, spaces: spaces)
        }
        .onChange(of: windowState.presentationState.spaceSwitch.request) { _, request in
            handleSpaceSwitchRequest(request, spaces: spaces)
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
            spaceCatalog: spaceCatalog,
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
                in: windowState,
                spaceID: request.targetSpaceID
            )
            return
        }

        guard let targetSpace = space(for: request.targetSpaceID, in: spaces) else {
            windowState.presentationState.pendingSplitGroupFocusRequest = nil
            return
        }

        switchSpace(to: targetSpace, spaces: spaces)
    }

    func handleSpaceSwitchRequest(
        _ request: WindowSpaceSwitchRequest?,
        spaces: [Space]
    ) {
        guard let request else { return }
        defer {
            windowState.presentationState.spaceSwitch.consume(request)
        }
        guard allowsSidebarInteractiveWork,
              let targetSpace = space(for: request.targetSpaceID, in: spaces)
        else { return }
        switchSpace(to: targetSpace, spaces: spaces)
    }

    func syncSpaceSwitchConsumer(isEnabled: Bool) {
        if isEnabled {
            windowState.presentationState.spaceSwitch.registerConsumer(
                spaceSwitchConsumerID
            )
        } else {
            windowState.presentationState.spaceSwitch.unregisterConsumer(
                spaceSwitchConsumerID
            )
        }
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
            browserContext.downloadsPopoverPresenter.close(in: windowState)
        }
    }

    func resolvedPageProfileId(for space: Space?) -> UUID? {
        transitionCoordinator.resolvedPageProfileId(
            for: space,
            context: makeTransitionContext(spaces: availableSpaces)
        )
    }
}
