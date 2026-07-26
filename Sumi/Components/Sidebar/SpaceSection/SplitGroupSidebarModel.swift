//
//  SplitGroupSidebarModel.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Window presentation for one durable split member.
///
/// `id` is the canonical member identity. In particular, a shortcut segment
/// keeps its pin identity even when this window currently has a live tab for
/// it. That makes SwiftUI diffing, drag payloads, and delayed actions immune to
/// live-tab replacement.
struct SplitGroupSidebarItem: Identifiable {
    let member: SplitMember
    let tab: Tab?
    let pin: ShortcutPin?

    var id: SplitMemberID { member.memberID }

    var persistentID: UUID {
        switch id {
        case .regularTab(let tabID):
            return tabID
        case .shortcutPin(let pinID):
            return pinID
        }
    }

    var stableIDDescription: String {
        switch id {
        case .regularTab(let tabID):
            return "regular-tab-\(tabID.uuidString)"
        case .shortcutPin(let pinID):
            return "shortcut-pin-\(pinID.uuidString)"
        }
    }

    @MainActor
    var title: String {
        tab?.name ?? pin?.preferredDisplayTitle ?? "Split member"
    }

    @MainActor
    static func regular(_ member: SplitMember, tab: Tab) -> Self? {
        guard case .regularTab(let tabID) = member.memberID,
              tab.id == tabID else {
            return nil
        }
        return Self(member: member, tab: tab, pin: nil)
    }

    @MainActor
    static func shortcut(
        _ member: SplitMember,
        pin: ShortcutPin,
        liveTab: Tab?
    ) -> Self? {
        guard case .shortcutPin(let pinID) = member.memberID,
              pin.id == pinID,
              liveTab?.shortcutPinId == pinID || liveTab == nil else {
            return nil
        }
        return Self(member: member, tab: liveTab, pin: pin)
    }
}

enum SplitGroupMemberIconKind: Equatable {
    case glyph
    case systemImage
    case storedLauncher
    case liveFavicon
    case storedFallback
}

struct SplitGroupMemberIconPresentation {
    let image: Image
    let glyphText: String?
    let systemImageName: String?
    let kind: SplitGroupMemberIconKind
    let shouldDesaturate: Bool
}

/// Keeps every split surface on the same launcher-favicon policy as a normal
/// pinned row: a durable launcher icon wins over transient live-tab imagery,
/// and a placeholder globe never replaces a cached site favicon.
@MainActor
enum SplitGroupMemberIconResolver {
    static func resolve(
        item: SplitGroupSidebarItem,
        loadedStoredFavicon: Image?,
        imageReader: any BrowserFaviconImageReading
    ) -> SplitGroupMemberIconPresentation {
        guard let pin = item.pin else {
            return SplitGroupMemberIconPresentation(
                image: item.tab?.favicon ?? Image(systemName: "globe"),
                glyphText: nil,
                systemImageName: nil,
                kind: item.tab == nil ? .storedFallback : .liveFavicon,
                shouldDesaturate: false
            )
        }

        let shouldDesaturate = item.tab == nil
        if let iconAsset = pin.iconAsset {
            if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
                return SplitGroupMemberIconPresentation(
                    image: Image(systemName: "globe"),
                    glyphText: iconAsset,
                    systemImageName: nil,
                    kind: .glyph,
                    shouldDesaturate: shouldDesaturate
                )
            }
            return SplitGroupMemberIconPresentation(
                image: Image(systemName:
                    SumiPersistentGlyph.resolvedLauncherSystemImageName(
                        iconAsset
                    )
                ),
                glyphText: nil,
                systemImageName:
                    SumiPersistentGlyph.resolvedLauncherSystemImageName(
                        iconAsset
                    ),
                kind: .systemImage,
                shouldDesaturate: shouldDesaturate
            )
        }

        if let liveTab = item.tab,
           SumiSurface.isSettingsSurfaceURL(liveTab.url) {
            return SplitGroupMemberIconPresentation(
                image: Image(systemName:
                    SumiSurface.settingsTabFaviconSystemImageName
                ),
                glyphText: nil,
                systemImageName: SumiSurface.settingsTabFaviconSystemImageName,
                kind: .systemImage,
                shouldDesaturate: false
            )
        }

        let partition = SumiFaviconPartition.regular(
            pin.executionProfileId ?? pin.profileId
        )
        if let storedFavicon = loadedStoredFavicon
            ?? ShortcutPin.cachedLaunchFavicon(
                for: pin.launchURL,
                partition: partition,
                imageReader: imageReader
            ) {
            return SplitGroupMemberIconPresentation(
                image: storedFavicon,
                glyphText: nil,
                systemImageName: nil,
                kind: .storedLauncher,
                shouldDesaturate: shouldDesaturate
            )
        }

        if let liveTab = item.tab,
           !liveTab.faviconIsTemplateGlobePlaceholder {
            return SplitGroupMemberIconPresentation(
                image: liveTab.favicon,
                glyphText: nil,
                systemImageName: nil,
                kind: .liveFavicon,
                shouldDesaturate: false
            )
        }

        if item.tab?.faviconIsTemplateGlobePlaceholder == true {
            return SplitGroupMemberIconPresentation(
                image: Image(systemName:
                    SumiPersistentGlyph.launcherSystemImageFallback
                ),
                glyphText: nil,
                systemImageName:
                    SumiPersistentGlyph.launcherSystemImageFallback,
                kind: .systemImage,
                shouldDesaturate: false
            )
        }

        if let systemImageName = pin.storedChromeTemplateSystemImageName(
            for: partition,
            imageReader: imageReader
        ) {
            return SplitGroupMemberIconPresentation(
                image: Image(systemName: systemImageName),
                glyphText: nil,
                systemImageName: systemImageName,
                kind: .systemImage,
                shouldDesaturate: shouldDesaturate
            )
        }

        return SplitGroupMemberIconPresentation(
            image: pin.storedFaviconImage(
                partition: partition,
                imageReader: imageReader
            ),
            glyphText: nil,
            systemImageName: nil,
            kind: .storedFallback,
            shouldDesaturate: shouldDesaturate
        )
    }
}

enum SplitGroupSidebarAction: Equatable {
    case unload

    var systemImageName: String {
        "minus"
    }

    var accessibilityPrefix: String {
        "space-split-group-unload"
    }

    var help: String {
        String(localized: "Unload Split View")
    }
}

enum SplitGroupSidebarMemberAction: Equatable {
    case close

    var systemImageName: String { "xmark" }
    var accessibilityPrefix: String { "space-split-member-close" }
    var help: String { String(localized: "Close Tab") }
}

enum SplitGroupSidebarModel {
    static func displayTitle(for group: SplitGroup) -> String {
        let title = group.title?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        guard title.isEmpty else { return title }
        return String.localizedStringWithFormat(
            String(localized: "%lld Tabs"),
            group.memberIDs.count
        )
    }

    @MainActor
    static func items(
        for group: SplitGroup,
        inventory: SidebarSpaceInventorySnapshot,
        selection: SidebarWindowSelectionQuery,
        windowState: BrowserWindowState
    ) -> [SplitGroupSidebarItem] {
        group.members.compactMap { member in
            switch member.memberID {
            case .regularTab(let tabID):
                guard let tab = inventory.tab(id: tabID) else {
                    return nil
                }
                return .regular(member, tab: tab)

            case .shortcutPin(let pinID):
                guard let pin = inventory.pin(id: pinID) else {
                    return nil
                }
                let liveTab = selection.liveTab(for: pinID, in: windowState)
                return .shortcut(member, pin: pin, liveTab: liveTab)
            }
        }
    }

    static func rowAction(
        for group: SplitGroup,
        items: [SplitGroupSidebarItem]
    ) -> SplitGroupSidebarAction? {
        switch group.container {
        case .regularTabs:
            return nil
        case .essentialSidebar, .shortcutSidebar:
            return items.contains { $0.tab != nil } ? .unload : nil
        }
    }

    static func memberAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupSidebarMemberAction? {
        guard case .regularTabs = group.container,
              case .regularTab = item.id,
              item.tab != nil else {
            return nil
        }
        return .close
    }

    /// Animation state may retain removed members briefly, but it must never
    /// retain stale runtime data for a member that still exists.
    static func displayItems(
        current: [SplitGroupSidebarItem],
        animationSnapshot: [SplitGroupSidebarItem]
    ) -> [SplitGroupSidebarItem] {
        guard !animationSnapshot.isEmpty else { return current }
        let currentByID = Dictionary(
            uniqueKeysWithValues: current.map { ($0.id, $0) }
        )
        return animationSnapshot.map { currentByID[$0.id] ?? $0 }
    }

    static func sourceZone(
        for pin: ShortcutPin,
        fallbackSpaceId: UUID
    ) -> DropZoneID {
        switch pin.role {
        case .essential:
            return .essentials
        case .spacePinned:
            if let folderId = pin.folderId {
                return .folder(folderId)
            }
            return .spacePinned(pin.spaceId ?? fallbackSpaceId)
        }
    }
}
