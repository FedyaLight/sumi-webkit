import Foundation

enum SumiPermissionIndicatorCategory: String, Codable, CaseIterable, Sendable {
    case hidden
    case pendingRequest
    case activeRuntime
    case blockedEvent
    case systemBlocked
    case storedException
    case reloadRequired
    case mixed
}

enum SumiPermissionIndicatorVisualStyle: String, Codable, CaseIterable, Sendable {
    case neutral
    case attention
    case active
    case blocked
    case systemWarning
    case reloadRequired
}

struct SumiPermissionIndicatorState: Equatable, Sendable {
    let category: SumiPermissionIndicatorCategory
    let primaryCategory: SumiPermissionIndicatorCategory
    let primaryPermissionType: SumiPermissionType?
    let relatedPermissionTypes: [SumiPermissionType]
    let displayDomain: String
    let tabId: String
    let pageId: String
    let priority: SumiPermissionIndicatorPriority?
    let icon: SumiPermissionIconDescriptor
    let accessibilityLabel: String
    let title: String
    let visualStyle: SumiPermissionIndicatorVisualStyle
    let badgeCount: Int?
    let latestEventReason: String?

    var isVisible: Bool {
        category != .hidden
    }

    static let hidden = SumiPermissionIndicatorState(
        category: .hidden,
        primaryCategory: .hidden,
        primaryPermissionType: nil,
        relatedPermissionTypes: [],
        displayDomain: "",
        tabId: "",
        pageId: "",
        priority: nil,
        icon: SumiPermissionIconCatalog.generic,
        accessibilityLabel: "No site permissions in use",
        title: "Permissions",
        visualStyle: .neutral,
        badgeCount: nil,
        latestEventReason: nil
    )

    static func visible(
        category: SumiPermissionIndicatorCategory,
        primaryPermissionType: SumiPermissionType,
        relatedPermissionTypes: [SumiPermissionType]? = nil,
        displayDomain: String,
        tabId: String,
        pageId: String,
        priority: SumiPermissionIndicatorPriority,
        visualStyle: SumiPermissionIndicatorVisualStyle,
        badgeCount: Int? = nil,
        latestEventReason: String? = nil,
        title: String? = nil,
        accessibilityLabel: String? = nil
    ) -> SumiPermissionIndicatorState {
        let related = uniquePermissionTypes(
            relatedPermissionTypes ?? [primaryPermissionType]
        )
        let icon = SumiPermissionIconCatalog.icon(
            for: primaryPermissionType,
            visualStyle: visualStyle
        )
        let resolvedTitle = title ?? Self.title(
            category: category,
            primaryPermissionType: primaryPermissionType,
            displayDomain: displayDomain
        )
        return SumiPermissionIndicatorState(
            category: category,
            primaryCategory: category,
            primaryPermissionType: primaryPermissionType,
            relatedPermissionTypes: related,
            displayDomain: displayDomain,
            tabId: tabId,
            pageId: pageId,
            priority: priority,
            icon: icon,
            accessibilityLabel: accessibilityLabel ?? Self.accessibilityLabel(
                category: category,
                primaryPermissionType: primaryPermissionType,
                relatedPermissionTypes: related,
                displayDomain: displayDomain
            ),
            title: resolvedTitle,
            visualStyle: visualStyle,
            badgeCount: badgeCount,
            latestEventReason: latestEventReason
        )
    }

    static func resolved(
        from candidates: [SumiPermissionIndicatorState]
    ) -> SumiPermissionIndicatorState {
        let visibleCandidates = candidates
            .filter(\.isVisible)
            .sorted { lhs, rhs in
                guard let lhsPriority = lhs.priority,
                      let rhsPriority = rhs.priority
                else {
                    return lhs.priority != nil
                }
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        guard let primary = visibleCandidates.first else {
            return .hidden
        }
        guard visibleCandidates.count > 1 else {
            return primary
        }

        let related = uniquePermissionTypes(
            visibleCandidates.flatMap(\.relatedPermissionTypes)
        )
        let accessibilityLabel = "Multiple permission states on \(primary.displayDomain): "
            + related.map(\.indicatorDisplayName).joined(separator: ", ")
        let badge = max(primary.badgeCount ?? 0, related.count)

        return SumiPermissionIndicatorState(
            category: .mixed,
            primaryCategory: primary.primaryCategory,
            primaryPermissionType: primary.primaryPermissionType,
            relatedPermissionTypes: related,
            displayDomain: primary.displayDomain,
            tabId: primary.tabId,
            pageId: primary.pageId,
            priority: primary.priority,
            icon: primary.icon,
            accessibilityLabel: accessibilityLabel,
            title: primary.title,
            visualStyle: primary.visualStyle,
            badgeCount: badge > 1 ? badge : primary.badgeCount,
            latestEventReason: primary.latestEventReason
        )
    }

    private static func title(
        category: SumiPermissionIndicatorCategory,
        primaryPermissionType: SumiPermissionType,
        displayDomain: String
    ) -> String {
        switch category {
        case .hidden:
            return "Permissions"
        case .pendingRequest:
            return "\(primaryPermissionType.indicatorDisplayName) requested by \(displayDomain)"
        case .activeRuntime:
            return "\(primaryPermissionType.indicatorDisplayName) active on \(displayDomain)"
        case .blockedEvent:
            return "\(primaryPermissionType.indicatorDisplayName) blocked on \(displayDomain)"
        case .systemBlocked:
            return "\(primaryPermissionType.indicatorDisplayName) blocked by macOS for \(displayDomain)"
        case .storedException:
            return "\(primaryPermissionType.indicatorDisplayName) setting for \(displayDomain)"
        case .reloadRequired:
            return "\(primaryPermissionType.indicatorDisplayName) reload required on \(displayDomain)"
        case .mixed:
            return "Site permissions"
        }
    }

    private static func accessibilityLabel(
        category: SumiPermissionIndicatorCategory,
        primaryPermissionType: SumiPermissionType,
        relatedPermissionTypes: [SumiPermissionType],
        displayDomain: String
    ) -> String {
        switch category {
        case .hidden:
            return "No site permissions in use"
        case .pendingRequest:
            return "\(primaryPermissionType.indicatorAccessName) access requested by \(displayDomain)"
        case .activeRuntime:
            if primaryPermissionType == .cameraAndMicrophone {
                return "Camera and microphone are active on \(displayDomain)"
            }
            if Set(relatedPermissionTypes.map(\.identity)) == Set([
                SumiPermissionType.camera.identity,
                SumiPermissionType.microphone.identity,
            ]) {
                return "Camera and microphone are active on \(displayDomain)"
            }
            return "\(primaryPermissionType.indicatorAccessName) is active on \(displayDomain)"
        case .blockedEvent:
            return "\(primaryPermissionType.indicatorBlockedName) on \(displayDomain)"
        case .systemBlocked:
            return "\(primaryPermissionType.indicatorAccessName) blocked by macOS system settings for \(displayDomain)"
        case .storedException:
            return "\(primaryPermissionType.indicatorAccessName) site setting exists for \(displayDomain)"
        case .reloadRequired:
            return "\(primaryPermissionType.indicatorAccessName) change requires reload on \(displayDomain)"
        case .mixed:
            return "Multiple permission states on \(displayDomain)"
        }
    }

    private static func uniquePermissionTypes(
        _ permissionTypes: [SumiPermissionType]
    ) -> [SumiPermissionType] {
        var seen = Set<String>()
        var result: [SumiPermissionType] = []
        for permissionType in permissionTypes {
            guard seen.insert(permissionType.identity).inserted else { continue }
            result.append(permissionType)
        }
        return result
    }
}

extension SumiPermissionType {
    var indicatorDisplayName: String {
        switch self {
        case .cameraAndMicrophone:
            return "Camera and microphone"
        case .screenCapture:
            return "Screen capture"
        case .storageAccess:
            return "Storage access"
        case .filePicker:
            return "File picker"
        case .externalScheme(let scheme):
            let normalizedScheme = Self.normalizedExternalScheme(scheme)
            return normalizedScheme.isEmpty ? "External app" : "\(normalizedScheme) links"
        default:
            return displayLabel
        }
    }

    var indicatorAccessName: String {
        switch self {
        case .popups:
            return "Pop-up"
        case .externalScheme:
            return "External app"
        default:
            return indicatorDisplayName
        }
    }

    var indicatorBlockedName: String {
        switch self {
        case .popups:
            return "Pop-up blocked"
        case .externalScheme:
            return "External app attempt blocked"
        case .notifications:
            return "Notification blocked"
        case .storageAccess:
            return "Storage access blocked"
        default:
            return "\(indicatorDisplayName) blocked"
        }
    }
}
