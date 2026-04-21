import Foundation
import SwiftUI

enum ShortcutPinRole: String, Codable {
    case essential
    case spacePinned
}

enum SumiLauncherRole: String, Codable {
    case essentialLauncher
    case pinnedLauncher
    case folderChildLauncher
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
    let systemIconName: String
    let iconAsset: String?
    private(set) var faviconCacheKey: String?

    @Published var title: String
    @Published var favicon: Image

    var sumiLauncherRole: SumiLauncherRole {
        switch (role, folderId) {
        case (.essential, _):
            return .essentialLauncher
        case (.spacePinned, .some):
            return .folderChildLauncher
        case (.spacePinned, .none):
            return .pinnedLauncher
        }
    }

    var isEssentialLauncher: Bool {
        sumiLauncherRole == .essentialLauncher
    }

    var isPinnedLauncher: Bool {
        sumiLauncherRole == .pinnedLauncher
    }

    var isFolderChildLauncher: Bool {
        sumiLauncherRole == .folderChildLauncher
    }

    init(
        id: UUID,
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        index: Int,
        folderId: UUID? = nil,
        launchURL: URL,
        title: String,
        faviconCacheKey: String? = nil,
        systemIconName: String = SumiPersistentGlyph.launcherSystemImageFallback,
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
        self.systemIconName = systemIconName
        self.iconAsset = Self.normalizedIconAsset(iconAsset, fallbackSystemIconName: systemIconName)
        self.faviconCacheKey = faviconCacheKey ?? Self.makeFaviconCacheKey(for: launchURL)
        self.favicon = Self.cachedFavicon(
            cacheKey: self.faviconCacheKey,
            fallbackSystemIconName: systemIconName
        )
        super.init()
    }

    func refreshFromLiveTab(_ tab: Tab) {
        favicon = tab.favicon
        faviconCacheKey = Self.makeFaviconCacheKey(for: launchURL) ?? Self.makeFaviconCacheKey(for: tab.url)
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
            faviconCacheKey: faviconCacheKey,
            systemIconName: systemIconName,
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
            faviconCacheKey: faviconCacheKey,
            systemIconName: systemIconName,
            iconAsset: iconAsset
        )
    }

    func updated(
        title: String? = nil,
        launchURL: URL? = nil,
        faviconCacheKey: String? = nil,
        systemIconName: String? = nil,
        iconAsset: String?? = nil,
        index: Int? = nil,
        folderId: UUID?? = nil
    ) -> ShortcutPin {
        let resolvedLaunchURL = launchURL ?? self.launchURL
        let resolvedFolderId = folderId ?? self.folderId
        let resolvedCacheKey = faviconCacheKey
            ?? Self.makeFaviconCacheKey(for: resolvedLaunchURL)
            ?? self.faviconCacheKey

        return ShortcutPin(
            id: id,
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index ?? self.index,
            folderId: resolvedFolderId,
            launchURL: resolvedLaunchURL,
            title: title ?? self.title,
            faviconCacheKey: resolvedCacheKey,
            systemIconName: systemIconName ?? self.systemIconName,
            iconAsset: iconAsset ?? self.iconAsset
        )
    }

    func applyCachedFaviconIfAvailable() {
        favicon = Self.cachedFavicon(
            cacheKey: faviconCacheKey,
            fallbackSystemIconName: systemIconName
        )
    }

    static func makeFaviconCacheKey(for url: URL) -> String? {
        SumiFaviconResolver.cacheKey(for: url)
    }

    private static func normalizedIconAsset(_ iconAsset: String?, fallbackSystemIconName: String) -> String? {
        if let iconAsset {
            let normalized = SumiPersistentGlyph.normalizedLauncherIconValue(iconAsset)
            return normalized
        }

        let trimmedFallback = fallbackSystemIconName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFallback.isEmpty,
              trimmedFallback != SumiPersistentGlyph.launcherSystemImageFallback else {
            return nil
        }

        return SumiPersistentGlyph.normalizedLauncherIconValue(trimmedFallback)
    }

    private static func cachedFavicon(cacheKey: String?, fallbackSystemIconName: String) -> Image {
        if let cacheKey, let cached = Tab.getCachedFavicon(for: cacheKey) {
            return cached
        }
        return Image(systemName: fallbackSystemIconName)
    }

    /// Aligns with `Tab.faviconIsTemplateGlobePlaceholder` when assigning `pin.favicon` to a tab.
    var faviconIsUncachedGlobeTemplate: Bool {
        guard systemIconName == SumiPersistentGlyph.launcherSystemImageFallback else { return false }
        guard let key = faviconCacheKey else { return true }
        return Tab.getCachedFavicon(for: key) == nil
    }

    /// When set, Essentials / space-pinned UI should draw this SF Symbol with chrome tokens (same as regular tab rows).
    var pinnedChromeTemplateSystemImageName: String? {
        if SumiSurface.isSettingsSurfaceURL(launchURL) {
            return SumiSurface.settingsTabFaviconSystemImageName
        }
        if faviconIsUncachedGlobeTemplate {
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
