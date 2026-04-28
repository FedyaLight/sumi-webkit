import Foundation

struct SumiPermissionSettingsProfileContext: Equatable, Hashable, Sendable {
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    let profileName: String

    @MainActor
    init(profile: Profile) {
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profile.id.uuidString)
        self.isEphemeralProfile = profile.isEphemeral
        self.profileName = profile.name
    }

    init(profilePartitionId: String, isEphemeralProfile: Bool, profileName: String = "Current Profile") {
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        self.isEphemeralProfile = isEphemeralProfile
        self.profileName = profileName
    }
}

enum SumiSiteSettingsPermissionCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case geolocation
    case camera
    case microphone
    case screenCapture
    case notifications
    case popups
    case externalScheme
    case autoplay
    case storageAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .geolocation:
            return "Location"
        case .camera:
            return "Camera"
        case .microphone:
            return "Microphone"
        case .screenCapture:
            return "Screen sharing"
        case .notifications:
            return "Notifications"
        case .popups:
            return "Pop-ups and redirects"
        case .externalScheme:
            return "External app links"
        case .autoplay:
            return "Autoplay"
        case .storageAccess:
            return "Storage access"
        }
    }

    var explanation: String {
        switch self {
        case .geolocation:
            return "Sites can ask to use your approximate or precise location."
        case .camera:
            return "Sites can ask to use cameras connected to this Mac."
        case .microphone:
            return "Sites can ask to use microphones connected to this Mac."
        case .screenCapture:
            return "Sites can ask to share windows, screens, or tabs."
        case .notifications:
            return "Sites can ask to show notifications outside the current page."
        case .popups:
            return "Sumi blocks background pop-ups by default. Site exceptions can allow them."
        case .externalScheme:
            return "Sites can ask before opening links in other apps."
        case .autoplay:
            return "Sites can be allowed to play media automatically or blocked from doing so."
        case .storageAccess:
            return "Embedded content can ask to access its saved website data."
        }
    }

    var defaultBehaviorText: String {
        switch self {
        case .geolocation, .camera, .microphone, .screenCapture, .notifications, .storageAccess:
            return "Sites ask before using this permission."
        case .popups:
            return "Background pop-ups are blocked unless a site is allowed."
        case .externalScheme:
            return "Sites ask before opening supported external app links."
        case .autoplay:
            return "Sumi uses the default autoplay behavior unless a site has an exception."
        }
    }

    var systemImage: String {
        switch self {
        case .geolocation:
            return "location"
        case .camera:
            return "video"
        case .microphone:
            return "mic"
        case .screenCapture:
            return "rectangle.on.rectangle"
        case .notifications:
            return "bell"
        case .popups:
            return "rectangle.badge.plus"
        case .externalScheme:
            return "arrow.up.forward.app"
        case .autoplay:
            return "play.rectangle"
        case .storageAccess:
            return "externaldrive"
        }
    }

    var systemKind: SumiSystemPermissionKind? {
        switch self {
        case .geolocation:
            return .geolocation
        case .camera:
            return .camera
        case .microphone:
            return .microphone
        case .screenCapture:
            return .screenCapture
        case .notifications:
            return .notifications
        case .popups, .externalScheme, .autoplay, .storageAccess:
            return nil
        }
    }

    var defaultOption: SumiCurrentSitePermissionOption {
        switch self {
        case .geolocation, .camera, .microphone, .screenCapture, .notifications, .storageAccess:
            return .ask
        case .popups, .autoplay:
            return .default
        case .externalScheme:
            return .ask
        }
    }

    func matches(_ permissionType: SumiPermissionType) -> Bool {
        switch (self, permissionType) {
        case (.geolocation, .geolocation),
             (.camera, .camera),
             (.microphone, .microphone),
             (.screenCapture, .screenCapture),
             (.notifications, .notifications),
             (.popups, .popups),
             (.autoplay, .autoplay),
             (.storageAccess, .storageAccess):
            return true
        case (.externalScheme, .externalScheme):
            return true
        default:
            return false
        }
    }

    var basePermissionType: SumiPermissionType? {
        switch self {
        case .geolocation:
            return .geolocation
        case .camera:
            return .camera
        case .microphone:
            return .microphone
        case .screenCapture:
            return .screenCapture
        case .notifications:
            return .notifications
        case .popups:
            return .popups
        case .autoplay:
            return .autoplay
        case .storageAccess:
            return .storageAccess
        case .externalScheme:
            return nil
        }
    }
}

struct SumiPermissionSiteScope: Identifiable, Equatable, Hashable, Sendable {
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    let requestingOrigin: SumiPermissionOrigin
    let topOrigin: SumiPermissionOrigin
    let displayDomain: String

    init(
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        displayDomain: String
    ) {
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        self.isEphemeralProfile = isEphemeralProfile
        self.requestingOrigin = requestingOrigin
        self.topOrigin = topOrigin
        self.displayDomain = SumiPermissionStoreRecord.normalizedDisplayDomain(displayDomain)
    }

    init(record: SumiPermissionStoreRecord) {
        self.init(
            profilePartitionId: record.key.profilePartitionId,
            isEphemeralProfile: record.key.isEphemeralProfile,
            requestingOrigin: record.key.requestingOrigin,
            topOrigin: record.key.topOrigin,
            displayDomain: record.displayDomain
        )
    }

    var id: String {
        [
            profilePartitionId,
            isEphemeralProfile ? "ephemeral" : "persistent",
            requestingOrigin.identity,
            topOrigin.identity,
        ].joined(separator: "|")
    }

    var title: String {
        requestingOrigin.displayDomain
    }

    var subtitle: String? {
        guard requestingOrigin.identity != topOrigin.identity else { return requestingOrigin.identity }
        return "\(requestingOrigin.displayDomain) embedded on \(topOrigin.displayDomain)"
    }

    var originSummary: String {
        requestingOrigin.identity == topOrigin.identity
            ? requestingOrigin.identity
            : "\(requestingOrigin.identity) embedded on \(topOrigin.identity)"
    }

    func key(for permissionType: SumiPermissionType) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            permissionType: permissionType,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile
        )
    }
}

struct SumiSiteSettingsCategoryRow: Identifiable, Equatable, Sendable {
    let category: SumiSiteSettingsPermissionCategory
    let exceptionCount: Int

    var id: String { category.id }
    var title: String { category.title }
    var systemImage: String { category.systemImage }
    var subtitle: String {
        exceptionCount == 0
            ? category.defaultBehaviorText
            : "\(exceptionCount) site exception\(exceptionCount == 1 ? "" : "s")"
    }
}

struct SumiSiteSettingsSiteRow: Identifiable, Equatable, Sendable {
    let scope: SumiPermissionSiteScope
    let storedPermissionCount: Int
    let recentActivityCount: Int
    let dataSummary: SumiSiteSettingsDataSummary?

    var id: String { scope.id }
    var title: String { scope.title }
    var subtitle: String {
        var parts: [String] = []
        parts.append("\(storedPermissionCount) stored permission\(storedPermissionCount == 1 ? "" : "s")")
        if let dataSummary {
            parts.append(dataSummary.displayText)
        }
        if recentActivityCount > 0 {
            parts.append("\(recentActivityCount) recent activit\(recentActivityCount == 1 ? "y" : "ies")")
        }
        if let embedded = scope.subtitle, embedded != scope.requestingOrigin.identity {
            parts.append(embedded)
        }
        return parts.joined(separator: " | ")
    }
}

struct SumiSiteSettingsDataSummary: Equatable, Hashable, Sendable {
    let displayText: String
    let canDelete: Bool
}

struct SumiSiteSettingsPermissionRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        case sitePermission(SumiPermissionType)
        case popups
        case externalScheme(String)
        case autoplay
        case filePicker
    }

    let id: String
    let kind: Kind
    let scope: SumiPermissionSiteScope
    let category: SumiSiteSettingsPermissionCategory?
    let title: String
    let subtitle: String?
    let systemImage: String
    let currentOption: SumiCurrentSitePermissionOption?
    let availableOptions: [SumiCurrentSitePermissionOption]
    let isEditable: Bool
    let disabledReason: String?
    let systemStatus: String?
    let showsSystemSettingsAction: Bool
    let isStoredException: Bool
    let updatedAt: Date?
    let accessibilityLabel: String

    var statusLines: [String] {
        [
            subtitle,
            systemStatus,
            disabledReason,
        ].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

struct SumiSiteSettingsCategoryDetail: Equatable, Sendable {
    let category: SumiSiteSettingsPermissionCategory
    let defaultBehaviorText: String
    let systemSnapshot: SumiSystemPermissionSnapshot?
    let rows: [SumiSiteSettingsPermissionRow]
}

struct SumiSiteSettingsSiteDetail: Equatable, Sendable {
    let scope: SumiPermissionSiteScope
    let profileName: String
    let dataSummary: SumiSiteSettingsDataSummary?
    let permissionRows: [SumiSiteSettingsPermissionRow]
    let filePickerRow: SumiSiteSettingsPermissionRow?
}

struct SumiSiteSettingsRecentActivityItem: Identifiable, Equatable, Sendable {
    let id: String
    let displayDomain: String
    let originSummary: String
    let profileName: String?
    let permissionTitle: String
    let actionTitle: String
    let timestamp: Date
    let systemImage: String
    let count: Int
    var customTitle: String? = nil
    var customSubtitle: String? = nil

    var title: String {
        if let customTitle { return customTitle }
        return "\(displayDomain) - \(permissionTitle) \(actionTitle)"
    }

    var subtitle: String {
        if let customSubtitle { return customSubtitle }
        var parts = [originSummary]
        if let profileName, !profileName.isEmpty {
            parts.append(profileName)
        }
        if count > 1 {
            parts.append("\(count) attempts")
        }
        return parts.joined(separator: " | ")
    }
}
