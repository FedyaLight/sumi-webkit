import Foundation

enum SumiCurrentSitePermissionOption: String, CaseIterable, Identifiable, Hashable, Sendable {
    case ask
    case allow
    case block
    case `default`
    case allowAll
    case blockAudible
    case blockAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask:
            return SumiCurrentSitePermissionsStrings.ask
        case .allow:
            return SumiCurrentSitePermissionsStrings.allow
        case .block:
            return SumiCurrentSitePermissionsStrings.block
        case .default:
            return SumiCurrentSitePermissionsStrings.defaultOption
        case .allowAll:
            return SumiCurrentSitePermissionsStrings.allowAllAutoplay
        case .blockAudible:
            return SumiCurrentSitePermissionsStrings.blockAudibleAutoplay
        case .blockAll:
            return SumiCurrentSitePermissionsStrings.blockAllAutoplay
        }
    }

    var shortTitle: String {
        switch self {
        case .ask:
            return SumiCurrentSitePermissionsStrings.ask
        case .allow:
            return SumiCurrentSitePermissionsStrings.allow
        case .block:
            return SumiCurrentSitePermissionsStrings.block
        case .default:
            return SumiCurrentSitePermissionsStrings.defaultOption
        case .allowAll:
            return "Allow all"
        case .blockAudible:
            return "Block audible"
        case .blockAll:
            return "Block all"
        }
    }
}
