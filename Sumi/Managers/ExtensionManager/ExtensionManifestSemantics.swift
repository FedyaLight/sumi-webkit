import Foundation

enum ExtensionManifestSemantics {
    static func defaultPopupPath(from manifest: [String: Any]) -> String? {
        if let action = manifest["action"] as? [String: Any],
           let popup = action["default_popup"] as? String,
           popup.isEmpty == false {
            return popup
        }
        if let action = manifest["browser_action"] as? [String: Any],
           let popup = action["default_popup"] as? String,
           popup.isEmpty == false {
            return popup
        }
        return nil
    }

    static func optionsPagePath(from manifest: [String: Any]) -> String? {
        if let options = manifest["options_ui"] as? [String: Any],
           let page = options["page"] as? String,
           page.isEmpty == false {
            return page
        }
        if let page = manifest["options_page"] as? String,
           page.isEmpty == false {
            return page
        }
        if let overrides = manifest["chrome_url_overrides"] as? [String: Any],
           let page = overrides["options"] as? String,
           page.isEmpty == false {
            return page
        }
        return nil
    }

    static func hasContentScripts(in manifest: [String: Any]) -> Bool {
        (manifest["content_scripts"] as? [[String: Any]])?.isEmpty == false
    }

    static func backgroundModel(
        from manifest: [String: Any]
    ) -> WebExtensionBackgroundModel {
        guard let background = manifest["background"] as? [String: Any] else {
            return .none
        }
        if background["service_worker"] as? String != nil {
            return .serviceWorker
        }
        if background["page"] as? String != nil
            || (background["scripts"] as? [String])?.isEmpty == false {
            return .persistentPage
        }
        return .none
    }

    static func activationSummary(
        from manifest: [String: Any]
    ) -> ExtensionActivationSummary {
        let requestedMatches = (manifest["host_permissions"] as? [String] ?? [])
            + ((manifest["content_scripts"] as? [[String: Any]] ?? [])
                .flatMap { $0["matches"] as? [String] ?? [] })
        let normalizedMatches = Array(
            NSOrderedSet(array: requestedMatches)
        ) as? [String] ?? requestedMatches
        let broadScope = normalizedMatches.contains {
            $0 == "<all_urls>" || $0 == "*://*/*" || $0.contains("://*")
        }

        return ExtensionActivationSummary(
            matchPatternStrings: normalizedMatches.sorted(),
            broadScope: broadScope,
            hasContentScripts: hasContentScripts(in: manifest),
            hasAction: defaultPopupPath(from: manifest) != nil
                || manifest["action"] != nil
                || manifest["browser_action"] != nil,
            hasOptionsPage: optionsPagePath(from: manifest) != nil,
            hasExtensionPages: hasExtensionPages(in: manifest)
        )
    }

    static func hasExtensionPages(in manifest: [String: Any]) -> Bool {
        optionsPagePath(from: manifest) != nil
            || defaultPopupPath(from: manifest) != nil
    }
}
