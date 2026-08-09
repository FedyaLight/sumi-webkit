import Foundation
import SumiDomain
import SwiftUI

enum SumiFavoriteRuntimeState {
    case launcherOnly
    case liveAttached
    case splitProxyBackgrounded
    case splitProxySelected

    var showsSplitProxyOutline: Bool {
        switch self {
        case .splitProxyBackgrounded, .splitProxySelected:
            return true
        case .launcherOnly, .liveAttached:
            return false
        }
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

    func resolvingURLDrift(_ hasDrifted: Bool) -> Self {
        switch self {
        case .launcherOnly:
            return .launcherOnly
        case .liveBackgrounded, .driftedLiveBackgrounded:
            return hasDrifted
                ? .driftedLiveBackgrounded
                : .liveBackgrounded
        case .liveSelected, .driftedLiveSelected:
            return hasDrifted
                ? .driftedLiveSelected
                : .liveSelected
        }
    }
}

@MainActor
final class ShortcutPin: NSObject, ObservableObject, Identifiable {
    let id: UUID
    let role: ShortcutPinRole
    let profileId: UUID?
    let executionProfileId: UUID?
    let spaceId: UUID?
    let index: Int
    let folderId: UUID?
    let launchURL: URL
    let iconAsset: String?
    let titleIsCustom: Bool

    @Published var title: String

    init(
        id: UUID,
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        executionProfileId: UUID? = nil,
        spaceId: UUID? = nil,
        index: Int,
        folderId: UUID? = nil,
        launchURL: URL,
        title: String,
        iconAsset: String? = nil,
        titleIsCustom: Bool = false
    ) {
        self.id = id
        self.role = role
        self.profileId = profileId
        self.executionProfileId = executionProfileId
        self.spaceId = spaceId
        self.index = index
        self.folderId = folderId
        self.launchURL = launchURL
        self.title = title
        self.iconAsset = Self.normalizedIconAsset(iconAsset)
        self.titleIsCustom = titleIsCustom
        super.init()
    }

    func refreshed(index: Int? = nil) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: role,
            profileId: profileId,
            executionProfileId: executionProfileId,
            spaceId: spaceId,
            index: index ?? self.index,
            folderId: self.folderId,
            launchURL: launchURL,
            title: title,
            iconAsset: iconAsset,
            titleIsCustom: titleIsCustom
        )
    }

    static func reindexed(_ pins: [ShortcutPin]) -> [ShortcutPin] {
        pins.enumerated().map { index, pin in
            pin.refreshed(index: index)
        }
    }

    func moved(toFolderId folderId: UUID?) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: role,
            profileId: profileId,
            executionProfileId: executionProfileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: launchURL,
            title: title,
            iconAsset: iconAsset,
            titleIsCustom: titleIsCustom
        )
    }

    func updated(
        title: String? = nil,
        launchURL: URL? = nil,
        iconAsset: String?? = nil,
        profileId: UUID?? = nil,
        executionProfileId: UUID?? = nil,
        index: Int? = nil,
        folderId: UUID?? = nil,
        titleIsCustom: Bool? = nil
    ) -> ShortcutPin {
        let resolvedLaunchURL = launchURL ?? self.launchURL
        let resolvedFolderId = folderId ?? self.folderId
        let resolvedProfileId = profileId ?? self.profileId
        let resolvedExecutionProfileId = executionProfileId ?? self.executionProfileId

        return ShortcutPin(
            id: id,
            role: role,
            profileId: resolvedProfileId,
            executionProfileId: resolvedExecutionProfileId,
            spaceId: spaceId,
            index: index ?? self.index,
            folderId: resolvedFolderId,
            launchURL: resolvedLaunchURL,
            title: title ?? self.title,
            iconAsset: iconAsset ?? self.iconAsset,
            titleIsCustom: titleIsCustom ?? self.titleIsCustom
        )
    }

    private static func normalizedIconAsset(_ iconAsset: String?) -> String? {
        if let iconAsset {
            let normalized = SumiPersistentGlyph.normalizedLauncherIconValue(iconAsset)
            return normalized == SumiPersistentGlyph.launcherSystemImageFallback ? nil : normalized
        }

        return nil
    }

    /// Emoji glyph chosen by the user for this pin (`iconAsset`), if the asset
    /// renders as an emoji. `nil` when the asset is an SF Symbol or absent.
    var glyphText: String? {
        guard let iconAsset, SumiPersistentGlyph.presentsAsEmoji(iconAsset) else {
            return nil
        }
        return iconAsset
    }

    /// SF Symbol name chosen by the user for this pin (`iconAsset`), if the
    /// asset renders as a template symbol. `nil` when the asset is an emoji or
    /// absent.
    var chromeTemplateSystemImageName: String? {
        guard let iconAsset, SumiPersistentGlyph.presentsAsEmoji(iconAsset) == false else {
            return nil
        }
        return SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset)
    }

    var preferredDisplayTitle: String {
        let savedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !savedTitle.isEmpty {
            return savedTitle
        }

        return launchURL.sumiSuggestedTitlePlaceholder ?? "Pinned Page"
    }

    func resolvedDisplayTitle(liveTab: Tab?) -> String {
        if titleIsCustom {
            return preferredDisplayTitle
        }
        if let liveTab {
            let liveTitle = liveTab.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !liveTitle.isEmpty {
                return liveTitle
            }
        }

        return preferredDisplayTitle
    }

    func hasDrifted(from currentURL: URL) -> Bool {
        Self.normalizedComparisonURL(currentURL)
            != Self.normalizedComparisonURL(launchURL)
    }

    private static func normalizedComparisonURL(_ url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: true
        ) else {
            return url.absoluteString.lowercased()
        }
        components.fragment = nil
        return components.string?.lowercased()
            ?? url.absoluteString.lowercased()
    }
}
