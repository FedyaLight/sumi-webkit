import Foundation

/// Lifetime projection used by browser-owned auxiliary sessions. Holding an
/// integration receipt must never prolong the extension runtime root.
@MainActor
final class WeakAuxiliaryWindowExtensionEvents:
    AuxiliaryWindowExtensionEventHandling {
    private weak var target: (any AuxiliaryWindowExtensionEventHandling)?

    init(target: any AuxiliaryWindowExtensionEventHandling) {
        self.target = target
    }

    func notifyAuxiliaryWindowOpened(
        _ session: AuxiliaryWindowSession
    ) -> Bool {
        target?.notifyAuxiliaryWindowOpened(session) ?? false
    }

    func notifyAuxiliaryWindowFocused(_ session: AuxiliaryWindowSession) {
        target?.notifyAuxiliaryWindowFocused(session)
    }

    func notifyAuxiliaryWindowClosed(_ session: AuxiliaryWindowSession) {
        target?.notifyAuxiliaryWindowClosed(session)
    }
}
