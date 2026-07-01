import Foundation

/// Presents transient browser toasts in the target (or active) window,
/// honoring the user's toast visibility setting.
@MainActor
final class BrowserToastPresenter {
    struct Dependencies {
        let showBrowserToasts: @MainActor () -> Bool
        let activeWindow: @MainActor () -> BrowserWindowState?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func presentToast(_ toast: BrowserToast, in windowState: BrowserWindowState? = nil) {
        guard dependencies.showBrowserToasts() else { return }
        guard let targetWindow = windowState ?? dependencies.activeWindow() else { return }
        targetWindow.presentToast(toast)
    }

    func showProfileSwitchToast(to profile: Profile, in windowState: BrowserWindowState?) {
        guard let targetWindow = windowState ?? dependencies.activeWindow() else { return }
        presentToast(.init(kind: .profileSwitch(profileName: profile.name)), in: targetWindow)
    }

    func presentTabClosureToast(tabCount: Int) {
        presentToast(.init(kind: .tabClosure(count: tabCount)))
    }
}

extension BrowserToastPresenter.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            showBrowserToasts: { [weak browserManager] in
                browserManager?.sumiSettings?.showBrowserToasts != false
            },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            }
        )
    }
}
