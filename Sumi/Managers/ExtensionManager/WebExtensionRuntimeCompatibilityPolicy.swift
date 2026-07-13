import Foundation

/// Classifies manifest-declared APIs that WebKit cannot provide at runtime.
/// This is a pure manifest policy: it owns no context, controller, or manager.
enum WebExtensionRuntimeCompatibilityPolicy {
    nonisolated static func declaresNativeMessaging(
        _ manifest: [String: Any]
    ) -> Bool {
        stringArray(from: manifest["permissions"])
            .contains("nativeMessaging")
    }

    nonisolated static func unsupportedAPIs(
        for manifest: [String: Any]
    ) -> Set<String> {
        guard declaresWebKitBrowserTarget(manifest) else { return [] }

        // WebKit's native browser.scripting implementation is verified by
        // SafariExtensionScriptingRuntimeTests. Only legacy injection APIs
        // without a verified WebKit implementation remain unsupported.
        return [
            "browser.contentScripts.register",
            "browser.tabs.executeScript",
            "browser.tabs.insertCSS",
        ]
    }

    private nonisolated static func declaresWebKitBrowserTarget(
        _ manifest: [String: Any]
    ) -> Bool {
        guard let settings =
                manifest["browser_specific_settings"] as? [String: Any]
        else {
            return false
        }
        return settings["safari"] != nil
            || settings["webkit"] != nil
            || settings["WebKit"] != nil
    }

    private nonisolated static func stringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }
}
