import Foundation

/// AppKit keeps this tiny adapter for the process lifetime. It owns no browser
/// subsystem; confirmed termination synchronously promotes its weak root into
/// one bounded finalization lease.
@MainActor
final class BrowserTerminationCoordinator: BrowserTerminationCoordinating {
    private weak var browserRuntime: BrowserManager?

    init(browserRuntime: BrowserManager) {
        self.browserRuntime = browserRuntime
    }

    func prepareForTermination() {
        guard let browserRuntime else { return }
        browserRuntime.urlBarBundle.commandPalette.presentation
            .dismissActiveWindow(preserveDraft: true)
        browserRuntime.chromeBundle.workspaceThemeEditorOwner
            .dismissThemePickerCommittingIfNeeded()
    }

    func acquireFinalizationLease() -> (any BrowserTerminationFinalizing)? {
        guard let browserRuntime else { return nil }
        return BrowserTerminationRuntimeLease(browserRuntime: browserRuntime)
    }
}
