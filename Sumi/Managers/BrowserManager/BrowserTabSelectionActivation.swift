import Foundation

@MainActor
final class BrowserTabSelectionActivation {
    private let batcher = WindowTabActivationBatcher()
    private let shortcutActivation: ShortcutPresentationActivationService?

    init(shortcutActivation: ShortcutPresentationActivationService?) {
        self.shortcutActivation = shortcutActivation
    }

    func request(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy,
        commit: @escaping @MainActor (
            UUID,
            WindowTabActivationBatcher.Activation
        ) -> Void
    ) {
        batcher.requestActivation(
            tabId: tab.id,
            in: windowState.id,
            loadPolicy: loadPolicy,
            onFlush: commit
        )
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
