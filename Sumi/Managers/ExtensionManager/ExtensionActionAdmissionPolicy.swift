import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionActionAdmissionPolicy {
    func rejection(
        for extensionRecord: InstalledExtension,
        currentTab: Tab?
    ) -> BrowserExtensionActionPopupRequestResult? {
        guard extensionRecord.isEnabled else {
            return .blocked(
                .extensionDisabled,
                message: "\(extensionRecord.name) is disabled."
            )
        }
        guard extensionRecord.hasAction else {
            return .blocked(
                .actionMissing,
                message: "\(extensionRecord.name) does not declare a Chrome action."
            )
        }
        if currentTab?.isEphemeral == true {
            return .blocked(
                .noEligibleTab,
                message: "Private tabs are not eligible for extension action popups."
            )
        }
        guard isModuleWorkerUnsupported(extensionRecord) == false else {
            return .blocked(
                .moduleWorkerUnsupported,
                message: "\(extensionRecord.name) declares a module service worker, which remains unsupported in this popup path."
            )
        }
        return nil
    }

    func sanitizedTraceURL(_ url: URL?) -> String {
        guard let url, let scheme = url.scheme?.lowercased() else {
            return "nil"
        }
        if ExtensionUtils.isExtensionOwnedURL(url) {
            let resource = url.lastPathComponent.isEmpty
                ? "<resource>"
                : url.lastPathComponent
            return "\(scheme)://<extension>/\(resource)"
        }
        if scheme == "http" || scheme == "https" {
            return "\(scheme)://<host>/<redacted-path>"
        }
        return "\(scheme)://<redacted>"
    }

    private func isModuleWorkerUnsupported(
        _ extensionRecord: InstalledExtension
    ) -> Bool {
        guard let background = extensionRecord.manifest["background"] as? [String: Any],
              let type = background["type"] as? String else {
            return false
        }
        return type.caseInsensitiveCompare("module") == .orderedSame
    }
}
