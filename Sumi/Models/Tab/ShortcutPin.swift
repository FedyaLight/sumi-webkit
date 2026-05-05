import Foundation
import SwiftUI

enum ShortcutPinRole: String, Codable, Sendable {
    case essential
    case spacePinned
}

enum SumiEssentialRuntimeState {
    case launcherOnly
    case liveAttached
    case splitProxyBackgrounded
    case splitProxySelected

    var showsSplitProxyBadge: Bool {
        switch self {
        case .splitProxyBackgrounded, .splitProxySelected:
            return true
        case .launcherOnly, .liveAttached:
            return false
        }
    }

    var isSelected: Bool {
        self == .splitProxySelected
    }
}

enum ShortcutPresentationState {
    case launcherOnly
    case liveBackgrounded
    case visuallySelected

    var isOpenLive: Bool {
        switch self {
        case .launcherOnly:
            return false
        case .liveBackgrounded, .visuallySelected:
            return true
        }
    }

    var isSelected: Bool {
        self == .visuallySelected
    }

    var shouldDesaturateIcon: Bool {
        self == .launcherOnly
    }
}

enum SumiLauncherRuntimeAffordanceState {
    case launcherOnly
    case liveBackgrounded
    case liveSelected
    case driftedLiveBackgrounded
    case driftedLiveSelected

    var isOpenLive: Bool {
        switch self {
        case .launcherOnly:
            return false
        case .liveBackgrounded, .liveSelected, .driftedLiveBackgrounded, .driftedLiveSelected:
            return true
        }
    }

    var isSelected: Bool {
        switch self {
        case .liveSelected, .driftedLiveSelected:
            return true
        case .launcherOnly, .liveBackgrounded, .driftedLiveBackgrounded:
            return false
        }
    }

    var shouldDesaturateIcon: Bool {
        self == .launcherOnly
    }

    var showsChangedURLSlash: Bool {
        switch self {
        case .driftedLiveBackgrounded, .driftedLiveSelected:
            return true
        case .launcherOnly, .liveBackgrounded, .liveSelected:
            return false
        }
    }

    var usesResetLeadingAction: Bool {
        showsChangedURLSlash
    }
}

@MainActor
final class ShortcutPin: NSObject, ObservableObject, Identifiable {
    let id: UUID
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let index: Int
    let folderId: UUID?
    let launchURL: URL
    let iconAsset: String?

    @Published var title: String

    init(
        id: UUID,
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        index: Int,
        folderId: UUID? = nil,
        launchURL: URL,
        title: String,
        iconAsset: String? = nil
    ) {
        self.id = id
        self.role = role
        self.profileId = profileId
        self.spaceId = spaceId
        self.index = index
        self.folderId = folderId
        self.launchURL = launchURL
        self.title = title
        self.iconAsset = Self.normalizedIconAsset(iconAsset)
        super.init()
    }

    func refreshed(index: Int? = nil) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index ?? self.index,
            folderId: self.folderId,
            launchURL: launchURL,
            title: title,
            iconAsset: iconAsset
        )
    }

    func moved(toFolderId folderId: UUID?) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: launchURL,
            title: title,
            iconAsset: iconAsset
        )
    }

    func updated(
        title: String? = nil,
        launchURL: URL? = nil,
        iconAsset: String?? = nil,
        index: Int? = nil,
        folderId: UUID?? = nil
    ) -> ShortcutPin {
        let resolvedLaunchURL = launchURL ?? self.launchURL
        let resolvedFolderId = folderId ?? self.folderId

        return ShortcutPin(
            id: id,
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index ?? self.index,
            folderId: resolvedFolderId,
            launchURL: resolvedLaunchURL,
            title: title ?? self.title,
            iconAsset: iconAsset ?? self.iconAsset
        )
    }

    private static func normalizedIconAsset(_ iconAsset: String?) -> String? {
        if let iconAsset {
            let normalized = SumiPersistentGlyph.normalizedLauncherIconValue(iconAsset)
            return normalized == SumiPersistentGlyph.launcherSystemImageFallback ? nil : normalized
        }

        return nil
    }

    static func cachedLaunchFavicon(for url: URL) -> Image? {
        Tab.getCachedFavicon(forDocumentURL: url)
    }

    var storedFavicon: Image {
        if let cached = Self.cachedLaunchFavicon(for: launchURL) {
            return cached
        }
        return Image(systemName: SumiPersistentGlyph.launcherSystemImageFallback)
    }

    var storedFaviconIsTemplateGlobePlaceholder: Bool {
        Self.cachedLaunchFavicon(for: launchURL) == nil
    }

    var storedChromeTemplateSystemImageName: String? {
        if SumiSurface.isSettingsSurfaceURL(launchURL) {
            return SumiSurface.settingsTabFaviconSystemImageName
        }
        if storedFaviconIsTemplateGlobePlaceholder {
            return SumiPersistentGlyph.launcherSystemImageFallback
        }
        return nil
    }

    var preferredDisplayTitle: String {
        let savedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !savedTitle.isEmpty {
            return savedTitle
        }

        return launchURL.sumiSuggestedTitlePlaceholder ?? "Pinned Page"
    }

    func resolvedDisplayTitle(liveTab: Tab?) -> String {
        if let liveTab {
            let liveTitle = liveTab.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !liveTitle.isEmpty {
                return liveTitle
            }
        }

        return preferredDisplayTitle
    }
}
