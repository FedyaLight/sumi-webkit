import Foundation

@MainActor
final class ClosedShortcutLiveRestoreTransaction {
    private let pins: ShortcutPinCollectionStateOwner
    private let activation: ShortcutPresentationActivationService
    private let windows: ClosedShortcutWindowQuery
    private let selection: BrowserTabSelectionOwner
    private let launchers: ClosedShortcutLauncherRestoreTransaction

    init(
        pins: ShortcutPinCollectionStateOwner,
        activation: ShortcutPresentationActivationService,
        windows: ClosedShortcutWindowQuery,
        selection: BrowserTabSelectionOwner,
        launchers: ClosedShortcutLauncherRestoreTransaction
    ) {
        self.pins = pins
        self.activation = activation
        self.windows = windows
        self.selection = selection
        self.launchers = launchers
    }

    func restore(
        _ shortcutState: RecentlyClosedShortcutLiveState,
        preferredWindow: BrowserWindowState? = nil
    ) -> Bool {
        guard let targetWindow = windows.targetWindow(
            for: shortcutState,
            preferredWindow: preferredWindow
        ) else {
            if pins.shortcutPin(by: shortcutState.pin.id) == nil {
                return launchers.restore(
                    shortcutState.pin,
                    fallbackWindow: preferredWindow
                ) != nil
            }
            return false
        }
        guard let pin = pins.shortcutPin(by: shortcutState.pin.id) else {
            return launchers.restore(
                shortcutState.pin,
                fallbackWindow: targetWindow
            ) != nil
        }
        return activation.commitActivation(
            pin,
            in: targetWindow.id,
            presentationSpaceID: pin.spaceId ?? targetWindow.currentSpaceId
        ) { [selection] restoredTab in
            Self.apply(shortcutState, to: restoredTab)
            _ = selection.selectTab(
                restoredTab,
                in: targetWindow,
                loadPolicy: .immediate
            )
        }
    }

    private static func apply(
        _ shortcutState: RecentlyClosedShortcutLiveState,
        to tab: Tab
    ) {
        tab.name = shortcutState.title
        tab.loadURL(shortcutState.url)
        tab.restoredCanGoBack = shortcutState.canGoBack
        tab.restoredCanGoForward = shortcutState.canGoForward
        tab.applyRestoredNavigationPresentation()
        _ = tab.applyCachedFaviconOrPlaceholder(for: shortcutState.url)
    }
}
