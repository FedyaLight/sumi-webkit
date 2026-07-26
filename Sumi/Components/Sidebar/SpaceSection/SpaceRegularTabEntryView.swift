//
//  SpaceRegularTabEntryView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Rendering leaf for one regular tab. The parent list retains insertion and
/// removal state; this view owns only row presentation and immediate actions.
struct SpaceRegularTabEntryView: View {
    let tab: Tab
    let spaceID: UUID
    let isCurrentTab: Bool
    let opacity: Double
    let isInteractive: Bool
    let projectedSplitTarget: SidebarSplitPairingTarget?
    let actionOwner: SpaceRegularTabActionOwner
    let onClose: () -> Void

    var body: some View {
        SpaceTab(
            tab: tab,
            dragSourceConfiguration: SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: tab.id,
                    title: tab.name,
                    urlString: tab.url.absoluteString
                ),
                sourceZone: .spaceRegular(spaceID),
                previewKind: .row,
                previewIcon: tab.favicon,
                exclusionZones: dragExclusionZones,
                isEnabled: !tab.isRenaming && isInteractive
            ),
            isAppKitInteractionEnabled: isInteractive,
            projectedSplitTarget: projectedSplitTarget,
            action: { actionOwner.activate(tab) },
            onClose: onClose,
            onMiddleClick: onClose,
            onMute: { tab.toggleMute() },
            contextMenuEntries: {
                actionOwner.contextMenuEntries(for: tab, close: onClose)
            },
            isCurrentTab: isCurrentTab
        )
        .opacity(opacity)
        .accessibilityIdentifier("space-regular-tab-\(tab.id.uuidString)")
        .accessibilityValue(isCurrentTab ? "selected" : "not selected")
    }

    private var dragExclusionZones: [SidebarDragSourceExclusionZone] {
        var exclusions: [SidebarDragSourceExclusionZone] = [.trailingStrip(40)]
        if tab.audioState.showsTabAudioButton {
            exclusions.append(.fixedRect(SpaceTab.audioButtonHitFrame))
        }
        return exclusions
    }
}
