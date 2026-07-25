import Foundation

/// Activates a shortcut pin chosen in the command palette: materializes its
/// live tab in the requesting window, then selects that tab.
@MainActor
final class CommandPaletteShortcutActivation {
    private let pins: ShortcutPinCollectionStateOwner
    private let materializer: ShortcutTabMaterializer
    private let selection: BrowserTabSelectionOwner

    init(
        pins: ShortcutPinCollectionStateOwner,
        materializer: ShortcutTabMaterializer,
        selection: BrowserTabSelectionOwner
    ) {
        self.pins = pins
        self.materializer = materializer
        self.selection = selection
    }

    func activate(pinID: UUID, in window: BrowserWindowState) -> Bool {
        guard let pin = pins.shortcutPin(by: pinID),
              let tab = materializer.materialize(
                  pin,
                  in: window.id,
                  currentSpaceId: pin.spaceId ?? window.currentSpaceId
              )
        else { return false }
        return selection.selectTab(
            tab,
            in: window,
            loadPolicy: .immediate
        ).wasCommitted
    }
}
