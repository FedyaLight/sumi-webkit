import Foundation

/// Reader-mode keyboard command for the page captured by shortcut routing.
@MainActor
final class BrowserKeyboardReaderCommands {
    func toggleReaderMode(on page: ActivePageResolution?) {
        guard let page,
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
