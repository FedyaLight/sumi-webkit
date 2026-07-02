enum URLBarPermissionInlineCycleResolver {
    static func nextOption(
        for row: SumiCurrentSitePermissionRow
    ) -> SumiCurrentSitePermissionOption? {
        guard let proposed = proposedOption(
            for: row.kind,
            currentOption: row.currentOption
        ) else {
            return nil
        }

        return row.availableOptions.contains(proposed) ? proposed : row.availableOptions.first
    }

    private static func proposedOption(
        for kind: SumiCurrentSitePermissionRow.Kind,
        currentOption: SumiCurrentSitePermissionOption?
    ) -> SumiCurrentSitePermissionOption? {
        switch kind {
        case .autoplay:
            return nextAutoplayOption(after: currentOption ?? .default)
        case .popups:
            return nextPopupOption(after: currentOption ?? .default)
        case .sitePermission, .externalScheme:
            return nextSitePermissionOption(after: currentOption ?? .ask)
        case .externalApps, .filePicker:
            return nil
        }
    }

    private static func nextAutoplayOption(
        after option: SumiCurrentSitePermissionOption
    ) -> SumiCurrentSitePermissionOption {
        switch option {
        case .default, .ask:
            return .blockAll
        case .blockAll, .blockAudible, .block:
            return .allowAll
        case .allowAll, .allow:
            return .blockAll
        }
    }

    private static func nextPopupOption(
        after option: SumiCurrentSitePermissionOption
    ) -> SumiCurrentSitePermissionOption {
        switch option {
        case .default, .ask:
            return .block
        case .block:
            return .allow
        case .allow:
            return .block
        case .allowAll, .blockAudible, .blockAll:
            return .block
        }
    }

    private static func nextSitePermissionOption(
        after option: SumiCurrentSitePermissionOption
    ) -> SumiCurrentSitePermissionOption {
        switch option {
        case .ask, .default:
            return .block
        case .block:
            return .allow
        case .allow:
            return .block
        case .allowAll, .blockAudible, .blockAll:
            return .block
        }
    }
}
