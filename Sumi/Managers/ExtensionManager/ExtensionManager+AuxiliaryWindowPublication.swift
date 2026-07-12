import Foundation

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    @discardableResult
    func notifyAuxiliaryWindowOpened(
        _ session: AuxiliaryWindowSession
    ) -> Bool {
        guard runtimePublicationGate.admitAuxiliaryBrowserEvent() else {
            return false
        }
        return auxiliaryWindowLifecycle.opened(
            session,
            runtime: runtime,
            control: extensionAuxiliaryWindows
        )
    }

    func notifyAuxiliaryWindowFocused(_ session: AuxiliaryWindowSession) {
        guard runtimePublicationGate.admitAuxiliaryBrowserEvent() else {
            return
        }
        auxiliaryWindowLifecycle.focused(
            session,
            runtime: runtime,
            control: extensionAuxiliaryWindows
        )
    }

    func notifyAuxiliaryWindowClosed(_ session: AuxiliaryWindowSession) {
        guard runtimePublicationGate.admitAuxiliaryBrowserEvent() else {
            return
        }
        auxiliaryWindowLifecycle.closed(
            session,
            runtime: runtime,
            windowQuery: extensionWindowQuery
        )
    }
}
