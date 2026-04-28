import Foundation
import WebKit

enum SumiAutoplayPolicy: String, Codable, CaseIterable, Hashable, Sendable {
    case `default`
    case allowAll
    case blockAudible
    case blockAll

    var displayLabel: String {
        switch self {
        case .default:
            return "Default"
        case .allowAll:
            return "Allow all autoplay"
        case .blockAudible:
            return "Block audible autoplay"
        case .blockAll:
            return "Block all autoplay"
        }
    }

    var siteControlsSubtitle: String {
        switch self {
        case .default:
            return "Default"
        case .allowAll:
            return "Allow"
        case .blockAudible:
            return "Block Audible"
        case .blockAll:
            return "Block"
        }
    }

    var chromeIconName: String {
        "autoplay-media-fill"
    }

    var fallbackSystemName: String {
        switch self {
        case .default, .allowAll:
            return "play.rectangle"
        case .blockAudible, .blockAll:
            return "play.rectangle.fill"
        }
    }

    var mediaTypesRequiringUserActionForPlayback: WKAudiovisualMediaTypes {
        switch self {
        case .default, .allowAll:
            return []
        case .blockAudible:
            return .audio
        case .blockAll:
            return .all
        }
    }

    var runtimeState: SumiRuntimeAutoplayState {
        switch self {
        case .default, .allowAll:
            return .allowAll
        case .blockAudible:
            return .blockAudible
        case .blockAll:
            return .blockAll
        }
    }

    var nextURLBarTogglePolicy: SumiAutoplayPolicy {
        switch self {
        case .default, .allowAll:
            return .blockAll
        case .blockAudible, .blockAll:
            return .allowAll
        }
    }

    static func fromMediaTypesRequiringUserActionForPlayback(
        _ mediaTypes: WKAudiovisualMediaTypes
    ) -> SumiAutoplayPolicy {
        if mediaTypes.isEmpty {
            return .allowAll
        }
        if mediaTypes == .audio {
            return .blockAudible
        }
        return .blockAll
    }
}
