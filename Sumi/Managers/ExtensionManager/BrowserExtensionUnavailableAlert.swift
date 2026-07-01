import AppKit

/// Modal alert shown when a browser-extension action cannot be routed
/// (extension missing, disabled, or unsupported on this macOS build).
@MainActor
enum BrowserExtensionUnavailableAlert {
    static func present(
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
