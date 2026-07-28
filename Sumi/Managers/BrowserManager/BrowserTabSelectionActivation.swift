import Foundation

@MainActor
final class BrowserTabSelectionActivation {
    private let shortcutActivation: ShortcutPresentationActivationService?

    init(shortcutActivation: ShortcutPresentationActivationService?) {
        self.shortcutActivation = shortcutActivation
    }

    func commitShortcutActivation(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        presentationSpaceID: UUID?,
        apply: (Tab) -> Void
    ) -> Bool {
        guard let shortcutActivation else { return false }
        return shortcutActivation.commitActivation(
            tab,
            in: windowState.id,
            presentationSpaceID: presentationSpaceID,
            finalizing: apply
        )
    }
}
