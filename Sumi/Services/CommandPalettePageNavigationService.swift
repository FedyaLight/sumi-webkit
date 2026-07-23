import Foundation
import SumiDomain

/// Resolves command-palette text into page loads and settings-surface updates.
/// It owns URL interpretation only; tab selection and bar presentation live
/// in their respective services.
@MainActor
final class CommandPalettePageNavigationService {
    private let settings: @MainActor () -> SumiSettingsService?
    private let loadPage: @MainActor (URL, Tab, BrowserWindowState) -> Void

    init(
        settings: @escaping @MainActor () -> SumiSettingsService?,
        loadPage: @escaping @MainActor (URL, Tab, BrowserWindowState) -> Void
    ) {
        self.settings = settings
        self.loadPage = loadPage
    }

    var configuredNewTabPageURL: String? {
        guard let settings = settings(),
              settings.newTabMode == .specificPage
        else { return nil }

        return settings.resolvedNewTabPageURL.absoluteString
    }

    func normalizedURLString(for input: String) -> String {
        normalizeURL(input, queryTemplate: searchQueryTemplate)
    }

    func loadLiteralURL(
        _ urlString: String,
        in tab: Tab,
        windowState: BrowserWindowState
    ) {
        guard let url = URL(string: urlString) else {
            RuntimeDiagnostics.emit("Invalid URL: \(urlString)")
            return
        }
        loadPage(url, tab, windowState)
    }

    func navigate(
        to input: String,
        in tab: Tab,
        windowState: BrowserWindowState
    ) {
        let normalizedURL = normalizedURLString(for: input)
        guard let url = URL(string: normalizedURL) else {
            RuntimeDiagnostics.emit(
                "Invalid URL after normalization: \(input) -> \(normalizedURL)"
            )
            return
        }
        loadPage(url, tab, windowState)
    }

    func applySettingsSurfaceNavigation(from input: String) {
        let normalizedURL = normalizedURLString(for: input)
        guard let url = URL(string: normalizedURL),
              SumiSurface.isSettingsSurfaceURL(url)
        else { return }

        settings()?.applyNavigationFromSettingsSurfaceURL(url)
    }

    private var searchQueryTemplate: String {
        settings()?.resolvedSearchEngineTemplate
            ?? SearchProvider.google.queryTemplate
    }
}
