import Foundation

/// Chooses the exact browser-side factory call that materializes the Tab model
/// for a resolved extension tab request. Transient internal pages get a
/// transient extension Tab; everything else becomes an inactive extension Tab
/// that the caller places, validates and commits.
@available(macOS 15.5, *)
@MainActor
enum ExtensionRequestedTabCreation {
    static func makeTab(
        for load: ExtensionRequestedTabLoad,
        opensTransientInternalTab: Bool,
        in space: Space?,
        browserContext: any ExtensionTabCreation
    ) -> Tab {
        if opensTransientInternalTab, let loadURL = load.url {
            return browserContext.createTransientExtensionTab(
                url: loadURL,
                in: space,
                webExtensionContextOverride: load.extensionContext
            )
        }
        return browserContext.createExtensionTab(
            url: load.url,
            in: space,
            activate: false,
            webExtensionContextOverride: load.extensionContext
        )
    }
}
