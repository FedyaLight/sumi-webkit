import Foundation

@MainActor
protocol CommandPaletteTabOpening: AnyObject {
    @discardableResult
    func createNewTab(in windowState: BrowserWindowState, url: String) -> Tab

    @discardableResult
    func createNewTabAfterSidebarInsertion(
        in windowState: BrowserWindowState,
        url: String
    ) -> Tab
}

extension BrowserTabOpeningOwner: CommandPaletteTabOpening {}

/// Commits a captured command-palette destination. The target is resolved before
/// dismiss resets the draft, preserving current-page intent without coupling
/// presentation state to tab routing.
@MainActor
final class CommandPaletteCommitService {
    private let presentation: CommandPalettePresentationService
    private let destinations: CommandPaletteDestinationRouter
    private let tabTargets: CommandPaletteTabTargetCommitter
    private let tabForID: @MainActor (UUID) -> Tab?
    private let activateNavigationTarget: @MainActor (
        CommandPaletteNavigationTargetPresentation.Identity,
        BrowserWindowState
    ) -> Bool

    init(
        presentation: CommandPalettePresentationService,
        destinations: CommandPaletteDestinationRouter,
        tabTargets: CommandPaletteTabTargetCommitter,
        tabForID: @escaping @MainActor (UUID) -> Tab?,
        activateNavigationTarget: @escaping @MainActor (
            CommandPaletteNavigationTargetPresentation.Identity,
            BrowserWindowState
        ) -> Bool
    ) {
        self.presentation = presentation
        self.destinations = destinations
        self.tabTargets = tabTargets
        self.tabForID = tabForID
        self.activateNavigationTarget = activateNavigationTarget
    }

    @discardableResult
    func openNewTabSurface(in windowState: BrowserWindowState) -> Bool {
        guard destinations.openConfiguredNewTabPage(in: windowState) == false
        else { return false }
        presentation.showNewTab(in: windowState)
        return true
    }

    func commitActivation(
        _ activation: CommandPaletteRow.Activation,
        in windowState: BrowserWindowState
    ) {
        let target = destinations.resolveTarget(in: windowState)
        let requiresSuccessfulActivation: Bool
        switch activation {
        case .tab, .navigationTarget:
            requiresSuccessfulActivation = true
        default:
            requiresSuccessfulActivation = false
        }
        if requiresSuccessfulActivation {
            guard openActivation(
                activation,
                in: windowState,
                target: target
            ) else { return }
            presentation.dismiss(
                in: windowState,
                preserveDraft: false,
                cancelEmptySplitPlaceholder: false
            )
            return
        }
        presentation.dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false
        )
        _ = openActivation(activation, in: windowState, target: target)
    }

    func commitNavigation(to urlString: String, in windowState: BrowserWindowState) {
        let target = destinations.resolveTarget(in: windowState)
        presentation.dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false
        )
        destinations.openLiteralURL(
            urlString,
            target: target,
            windowState: windowState,
            source: nil
        )
    }

    @discardableResult
    private func openActivation(
        _ activation: CommandPaletteRow.Activation,
        in windowState: BrowserWindowState,
        target: CommandPaletteCommitTarget
    ) -> Bool {
        switch activation {
        case .tab(let tabID):
            guard let existingTab = tabForID(tabID) else {
                return false
            }
            guard tabTargets.select(existingTab, in: windowState) else {
                return false
            }
            RuntimeDiagnostics.debug(
                "Switched to existing tab: \(existingTab.name)",
                category: "CommandPalette"
            )
        case .navigationTarget(let identity):
            guard activateNavigationTarget(
                identity,
                windowState
            ) else {
                return false
            }
            RuntimeDiagnostics.debug(
                "Activated navigation target: \(identity)",
                category: "CommandPalette"
            )
        case .literalURL(let urlString):
            destinations.openLiteralURL(
                urlString,
                target: target,
                windowState: windowState,
                source: "literal"
            )
        case .input(let input):
            destinations.openInput(
                input,
                target: target,
                windowState: windowState
            )
        case .browserAction, .space, .extensionAction:
            return false
        }
        return true
    }

}
