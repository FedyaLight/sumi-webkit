import Foundation

@MainActor
extension BrowserManager {
    func composeWindowSpaceTransitions(splitFocus: SplitShortcutFocusService) -> BrowserWindowSpaceTransitionService {
        let selectionHandoff = BrowserWindowSpaceSelectionHandoff(
            tabContext: shellRuntime.windowTabs,
            selection: browserTabSelection,
            visuals: shellRuntime.windowVisuals
        )
        let workspaceThemes = chromeBundle.workspaceThemeTransitionOwner
        let contextTransition = BrowserWindowSpaceContextTransition(
            contextReconciler: BrowserWindowSpaceContextReconciler(
                membership: tabCollectionMembershipOwner,
                spaces: spaceStateOwner
            ),
            commandPalette: urlBarBundle.commandPalettePresentation,
            selection: browserTabSelection,
            workspaceThemes: workspaceThemes
        )

        let settlement = BrowserWindowSpaceTransitionSettlement(
            windows: windowRegistry,
            windowState: windowStateReconciler,
            profileAdoption: profileAdoption,
            persistence: windowSessionPersistenceCoordinator,
            splitFocus: splitFocus
        )
        return BrowserWindowSpaceTransitionService(
            spaceActivation: spaceActivation,
            preservedSelection: BrowserWindowSpacePreservedSelectionTransaction(
                selection: selectionHandoff,
                context: contextTransition,
                settlement: settlement
            ),
            spaceChange: BrowserWindowSpaceChangeTransaction(
                activation: spaceActivation,
                selection: selectionHandoff,
                context: contextTransition,
                settlement: settlement
            ),
            settlement: settlement
        )
    }
}
