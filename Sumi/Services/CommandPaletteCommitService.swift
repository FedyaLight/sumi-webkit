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
    private enum Target {
        case currentPage(Tab)
        case newTab
    }

    private let presentation: CommandPalettePresentationService
    private let tabOpening: @MainActor () -> (any CommandPaletteTabOpening)?
    private let tabTargets: CommandPaletteTabTargetCommitter
    private let tabForID: @MainActor (UUID) -> Tab?
    private let activePageTab: @MainActor (BrowserWindowState) -> Tab?
    private let pageNavigation: CommandPalettePageNavigationService
    private let activateNavigationTarget: @MainActor (
        CommandPaletteNavigationTargetPresentation.Identity,
        BrowserWindowState
    ) -> Bool

    init(
        presentation: CommandPalettePresentationService,
        tabOpening: @escaping @MainActor () -> (any CommandPaletteTabOpening)?,
        tabTargets: CommandPaletteTabTargetCommitter,
        tabForID: @escaping @MainActor (UUID) -> Tab?,
        activePageTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        pageNavigation: CommandPalettePageNavigationService,
        activateNavigationTarget: @escaping @MainActor (
            CommandPaletteNavigationTargetPresentation.Identity,
            BrowserWindowState
        ) -> Bool
    ) {
        self.presentation = presentation
        self.tabOpening = tabOpening
        self.tabTargets = tabTargets
        self.tabForID = tabForID
        self.activePageTab = activePageTab
        self.pageNavigation = pageNavigation
        self.activateNavigationTarget = activateNavigationTarget
    }

    @discardableResult
    func openNewTabSurface(in windowState: BrowserWindowState) -> Bool {
        if let configuredURL = pageNavigation.configuredNewTabPageURL {
            tabOpening()?.createNewTab(in: windowState, url: configuredURL)
            return false
        } else {
            presentation.showNewTab(in: windowState)
            return true
        }
    }

    func commitActivation(
        _ activation: CommandPaletteRow.Activation,
        in windowState: BrowserWindowState
    ) {
        let target = resolveTarget(in: windowState)
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
        let target = resolveTarget(in: windowState)
        presentation.dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false
        )

        switch target {
        case .currentPage(let tab):
            tabTargets.commitPlaceholder(for: tab, in: windowState.id)
            pageNavigation.loadLiteralURL(
                urlString,
                in: tab,
                windowState: windowState
            )
            pageNavigation.applySettingsSurfaceNavigation(from: urlString)
        case .newTab:
            tabOpening()?.createNewTabAfterSidebarInsertion(
                in: windowState,
                url: urlString
            )
        }
    }

    @discardableResult
    private func openActivation(
        _ activation: CommandPaletteRow.Activation,
        in windowState: BrowserWindowState,
        target: Target
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
            openURL(
                urlString,
                source: "literal",
                target: target,
                windowState: windowState
            )
        case .input(let input):
            openInput(
                input,
                target: target,
                windowState: windowState
            )
        case .browserAction, .space, .extensionAction:
            return false
        }
        return true
    }

    private func openURL(
        _ urlString: String,
        source: String,
        target: Target,
        windowState: BrowserWindowState
    ) {
        switch target {
        case .currentPage(let tab):
            tabTargets.commitPlaceholder(for: tab, in: windowState.id)
            pageNavigation.loadLiteralURL(
                urlString,
                in: tab,
                windowState: windowState
            )
            pageNavigation.applySettingsSurfaceNavigation(from: urlString)
            RuntimeDiagnostics.debug(
                "Navigated current tab to \(source) URL: \(urlString)",
                category: "CommandPalette"
            )
        case .newTab:
            tabOpening()?.createNewTabAfterSidebarInsertion(
                in: windowState,
                url: urlString
            )
            RuntimeDiagnostics.debug(
                "Created new tab from \(source) in window \(windowState.id)",
                category: "CommandPalette"
            )
        }
    }

    private func openInput(
        _ input: String,
        target: Target,
        windowState: BrowserWindowState
    ) {
        switch target {
        case .currentPage(let tab):
            tabTargets.commitPlaceholder(for: tab, in: windowState.id)
            pageNavigation.navigate(to: input, in: tab, windowState: windowState)
            pageNavigation.applySettingsSurfaceNavigation(from: input)
            RuntimeDiagnostics.debug(
                "Navigated current tab to: \(input)",
                category: "CommandPalette"
            )
        case .newTab:
            let resolvedURL = pageNavigation.normalizedURLString(for: input)
            tabOpening()?.createNewTabAfterSidebarInsertion(
                in: windowState,
                url: resolvedURL
            )
            RuntimeDiagnostics.debug(
                "Created new tab in window \(windowState.id)",
                category: "CommandPalette"
            )
        }
    }

    private func resolveTarget(in windowState: BrowserWindowState) -> Target {
        guard windowState.commandPaletteDraftNavigatesCurrentTab,
              let activePageTab = activePageTab(windowState)
        else { return .newTab }

        return .currentPage(activePageTab)
    }
}
