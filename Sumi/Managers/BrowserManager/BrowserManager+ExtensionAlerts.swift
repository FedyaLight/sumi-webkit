import AppKit

@MainActor
extension BrowserManager {
    func showBrowserExtensionsUnavailableAlert(
        extensionName: String? = nil,
        informativeText: String? = nil
    ) {
        let alert = NSAlert()
        alert.messageText = extensionName.map {
            "\($0) is currently unavailable"
        } ?? "Browser extensions are currently unavailable"
        alert.informativeText =
            informativeText
            ?? "Sumi could not open the requested extension action. "
            + "Check Settings > Extensions to confirm the extension is installed, enabled, and supported on this macOS build."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
