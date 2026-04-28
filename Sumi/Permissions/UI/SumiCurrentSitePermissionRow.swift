import Foundation

struct SumiCurrentSitePermissionRow: Identifiable, Equatable, Sendable {
    enum Kind: Hashable, Sendable {
        case sitePermission(SumiPermissionType)
        case popups
        case externalApps
        case externalScheme(String)
        case autoplay
        case filePicker
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let iconName: String?
    let fallbackSystemName: String
    let currentOption: SumiCurrentSitePermissionOption?
    let availableOptions: [SumiCurrentSitePermissionOption]
    let isEditable: Bool
    let disabledReason: String?
    let systemStatus: String?
    let showsSystemSettingsAction: Bool
    let runtimeStatus: String?
    let reloadRequired: Bool
    let recentEventCount: Int
    let accessibilityLabel: String

    init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        fallbackSystemName: String,
        currentOption: SumiCurrentSitePermissionOption? = nil,
        availableOptions: [SumiCurrentSitePermissionOption] = [],
        isEditable: Bool = false,
        disabledReason: String? = nil,
        systemStatus: String? = nil,
        showsSystemSettingsAction: Bool = false,
        runtimeStatus: String? = nil,
        reloadRequired: Bool = false,
        recentEventCount: Int = 0,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.fallbackSystemName = fallbackSystemName
        self.currentOption = currentOption
        self.availableOptions = availableOptions
        self.isEditable = isEditable
        self.disabledReason = disabledReason
        self.systemStatus = systemStatus
        self.showsSystemSettingsAction = showsSystemSettingsAction
        self.runtimeStatus = runtimeStatus
        self.reloadRequired = reloadRequired
        self.recentEventCount = recentEventCount
        self.accessibilityLabel = accessibilityLabel ?? Self.makeAccessibilityLabel(
            title: title,
            option: currentOption,
            subtitle: subtitle,
            runtimeStatus: runtimeStatus,
            systemStatus: systemStatus
        )
    }

    var statusLines: [String] {
        [
            subtitle,
            runtimeStatus,
            reloadRequired ? "Reload required" : nil,
            systemStatus,
            disabledReason,
        ].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func makeAccessibilityLabel(
        title: String,
        option: SumiCurrentSitePermissionOption?,
        subtitle: String?,
        runtimeStatus: String?,
        systemStatus: String?
    ) -> String {
        [
            title,
            option.map { "Current setting: \($0.title)" },
            subtitle,
            runtimeStatus,
            systemStatus,
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
