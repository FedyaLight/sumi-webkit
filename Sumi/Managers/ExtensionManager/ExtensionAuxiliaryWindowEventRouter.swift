import Foundation

/// Weak, browser-session-safe adapter from native auxiliary-window events to
/// the exact attached extension publication roles. A retained native session
/// cannot prolong the extension runtime or recover its composition root.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryWindowEventRouter:
    AuxiliaryWindowExtensionEventHandling {
    private weak var gate: ExtensionRuntimePublicationGate?
    private weak var lifecycle: ExtensionAuxiliaryWindowLifecycle?
    private weak var control: (any ExtensionAuxiliaryWindowControl)?
    private weak var windows: (any ExtensionWindowQuery)?

    init(
        gate: ExtensionRuntimePublicationGate,
        lifecycle: ExtensionAuxiliaryWindowLifecycle,
        control: any ExtensionAuxiliaryWindowControl,
        windows: any ExtensionWindowQuery
    ) {
        self.gate = gate
        self.lifecycle = lifecycle
        self.control = control
        self.windows = windows
    }

    func notifyAuxiliaryWindowOpened(
        _ session: AuxiliaryWindowSession
    ) -> Bool {
        guard gate?.admitAuxiliaryBrowserEvent() == true,
              let lifecycle,
              let control
        else {
            return false
        }
        return lifecycle.opened(session, control: control)
    }

    func notifyAuxiliaryWindowFocused(_ session: AuxiliaryWindowSession) {
        guard gate?.admitAuxiliaryBrowserEvent() == true,
              let lifecycle,
              let control
        else {
            return
        }
        lifecycle.focused(session, control: control)
    }

    func notifyAuxiliaryWindowClosed(_ session: AuxiliaryWindowSession) {
        guard gate?.admitAuxiliaryBrowserEvent() == true,
              let lifecycle
        else {
            return
        }
        lifecycle.closed(session, windowQuery: windows)
    }
}
