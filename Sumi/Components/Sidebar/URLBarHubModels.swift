import Foundation

struct SiteControlsSettingRowModel: Equatable, Identifiable {
    enum Kind: Equatable {
        case protection(
            plan: SumiProtectionRulePlan,
            reloadRequired: Bool
        )
        case cookies
        case localPage
    }

    let id: String
    let chromeIconName: String?
    let fallbackSystemName: String
    let title: String
    let subtitle: String?
    let kind: Kind

    var isDisabled: Bool {
        switch kind {
        case .protection(let plan, _):
            return plan.requestedLevel == .off || plan.siteHost == nil
        case .cookies,
             .localPage:
            return false
        }
    }

    var isInteractive: Bool {
        switch kind {
        case .protection(let plan, _):
            return plan.requestedLevel != .off && plan.siteHost != nil
        case .cookies:
            return true
        default:
            return false
        }
    }

    var showsDisclosure: Bool {
        switch kind {
        case .cookies:
            return true
        default:
            return false
        }
    }
}

struct SiteControlsSnapshot: Equatable {
    enum HubAnchorAppearance: Equatable {
        case zenPermissions
    }

    enum ReaderAvailability: Equatable {
        case disabledPlaceholder
        case available
    }

    enum SecurityState: Equatable {
        case secure
        case notSecure
        case localPage
        case internalPage

        var footerTitle: String {
            switch self {
            case .secure: return "Secure connection"
            case .notSecure: return "Connection not secure"
            case .localPage: return "Local page"
            case .internalPage: return "Page information"
            }
        }

        var chromeIconName: String? {
            switch self {
            case .secure:
                return "security"
            case .notSecure:
                return "security-broken"
            case .localPage:
                return nil
            case .internalPage:
                return nil
            }
        }

        var fallbackSystemName: String {
            switch self {
            case .secure: return "lock.fill"
            case .notSecure: return "lock.open.fill"
            case .localPage: return "doc.fill"
            case .internalPage: return "info.circle.fill"
            }
        }

        var showsFooterButton: Bool {
            self != .internalPage
        }
    }

    let hubAnchorAppearance: HubAnchorAppearance
    let securityState: SecurityState
    let readerAvailability: ReaderAvailability
    let settingsRows: [SiteControlsSettingRowModel]

    @MainActor
    static func resolve(
        url: URL?,
        profile: Profile?,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        protectionBrowserRestartRequired: Bool = false,
        protectionReloadRequired: Bool = false
    ) -> SiteControlsSnapshot {
        guard let url else {
            return SiteControlsSnapshot(
                hubAnchorAppearance: .zenPermissions,
                securityState: .internalPage,
                readerAvailability: .disabledPlaceholder,
                settingsRows: []
            )
        }

        let rawHost = url.host ?? url.absoluteString
        let displayHost = rawHost.hasPrefix("www.")
            ? String(rawHost.dropFirst(4))
            : rawHost
        let scheme = url.scheme?.lowercased() ?? ""

        let securityState: SecurityState
        switch scheme {
        case "https":
            securityState = .secure
        case "file":
            securityState = .localPage
        case "about", "data", "blob", "javascript", "sumi":
            securityState = .internalPage
        default:
            securityState = .notSecure
        }

        let settingsRows: [SiteControlsSettingRowModel]
        switch securityState {
        case .secure, .notSecure:
            var rows: [SiteControlsSettingRowModel] = []
            _ = profile

            if let protectionCoordinator {
                let plan = protectionCoordinator.cachedRulePlan(for: url, profileId: profile?.id)
                let subtitle: String
                if protectionBrowserRestartRequired {
                    subtitle = "Restart Sumi to apply global changes"
                } else if protectionReloadRequired {
                    subtitle = "Reload required"
                } else if plan.requestedLevel == .off {
                    subtitle = "Off globally"
                } else if !plan.sitePolicyAllowsProtection {
                    subtitle = "Protection off for this site"
                } else {
                    subtitle = "\(plan.effectiveLevel.displayTitle) on for this site"
                }
                rows.append(
                    .init(
                        id: "adblock-protection",
                        chromeIconName: plan.sitePolicyAllowsProtection && plan.effectiveLevel != .off
                            ? nil
                            : "shield-off",
                        fallbackSystemName: plan.sitePolicyAllowsProtection && plan.effectiveLevel != .off
                            ? "shield.lefthalf.filled"
                            : "shield.slash",
                        title: "Adblock & Protection",
                        subtitle: subtitle,
                        kind: .protection(
                            plan: plan,
                            reloadRequired: protectionReloadRequired
                        )
                    )
                )
            }
            rows.append(
                .init(
                    id: "cookies",
                    chromeIconName: "cookies-fill",
                    fallbackSystemName: "network",
                    title: "Cookies & Site Data",
                    subtitle: displayHost,
                    kind: .cookies
                )
            )
            settingsRows = rows
        case .localPage:
            settingsRows = [
                .init(
                    id: "local",
                    chromeIconName: nil,
                    fallbackSystemName: "doc",
                    title: "Page Type",
                    subtitle: "Local file or bundled resource",
                    kind: .localPage
                )
            ]
        case .internalPage:
            settingsRows = []
        }

        return SiteControlsSnapshot(
            hubAnchorAppearance: .zenPermissions,
            securityState: securityState,
            readerAvailability: .disabledPlaceholder,
            settingsRows: settingsRows
        )
    }
}
