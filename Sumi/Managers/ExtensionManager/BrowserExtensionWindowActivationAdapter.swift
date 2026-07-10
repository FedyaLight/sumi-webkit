import Foundation

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionWindowActivationAdapter: ExtensionWindowActivation {
    private let activate: @MainActor (BrowserWindowState) -> Void

    init(activate: @escaping @MainActor (BrowserWindowState) -> Void) {
        self.activate = activate
    }

    func setActiveExtensionWindow(_ windowState: BrowserWindowState) {
        activate(windowState)
    }
}
