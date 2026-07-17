import Foundation

/// Reader-mode keyboard command resolved from one canonical active page.
@MainActor
final class BrowserKeyboardReaderCommands {
    private let activePage: ActivePageResolver

    init(activePage: ActivePageResolver) {
        self.activePage = activePage
    }

    func toggleReaderModeInActiveWindow() {
        guard let page = activePage.resolveActiveWindow(),
              page.tab.representsSumiNativeSurface == false,
              let webView = page.canonicalWebView else {
            return
        }

        Task { @MainActor in
            do {
                try await SumiReaderModeService.toggleReaderMode(
                    on: webView,
                    tab: page.tab
                )
            } catch {
                RuntimeDiagnostics.debug(category: "ReaderMode") {
                    "Keyboard reader mode toggle failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
